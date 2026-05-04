#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "Start installing SMTP server"

apt-get update

apt-get install -y postfix mailutils

echo "Type your main domain name (ex. example.com):"
read DOMAIN_NAME

echo "Type your SMTP hostname (ex. smtp.example.com):"
read SMTP_HOST

sed -i '/^DOMAIN_NAME=/d' /etc/environment
sed -i '/^SMTP_HOST=/d' /etc/environment
echo "DOMAIN_NAME=$DOMAIN_NAME" >> /etc/environment
echo "SMTP_HOST=$SMTP_HOST" >> /etc/environment

hostnamectl set-hostname "$SMTP_HOST"

sed -i '/127.0.0.1/d' /etc/hosts
echo "127.0.0.1 $SMTP_HOST" >> /etc/hosts

systemctl restart systemd-logind.service

apt-get install -y certbot

certbot certonly --non-interactive --agree-tos --register-unsafely-without-email --standalone -d "$SMTP_HOST"

if [ ! -d "/etc/ssl/postfix" ]; then
  mkdir -p /etc/ssl/postfix
fi

HOSTNAME_SSL_PATH=/etc/ssl/postfix/fullchain.crt
HOSTNAME_PRIVKEY_PATH=/etc/ssl/postfix/privkey.pem

sed -i '/^HOSTNAME_SSL_PATH=/d' /etc/environment
sed -i '/^HOSTNAME_PRIVKEY_PATH=/d' /etc/environment
echo "HOSTNAME_SSL_PATH=$HOSTNAME_SSL_PATH" >> /etc/environment
echo "HOSTNAME_PRIVKEY_PATH=$HOSTNAME_PRIVKEY_PATH" >> /etc/environment

cp "/etc/letsencrypt/live/$SMTP_HOST/fullchain.pem" "$HOSTNAME_SSL_PATH"
cp "/etc/letsencrypt/live/$SMTP_HOST/privkey.pem" "$HOSTNAME_PRIVKEY_PATH"

rm -f /etc/postfix/main.cf

cat > /etc/postfix/main.cf <<EOF
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

smtpd_banner = \$myhostname ESMTP (Ubuntu)
biff = no

append_dot_mydomain = no

readme_directory = no

compatibility_level = 3.6

# TLS parameters
smtpd_tls_cert_file=$HOSTNAME_SSL_PATH
smtpd_tls_key_file=$HOSTNAME_PRIVKEY_PATH
smtpd_tls_security_level=may
smtpd_tls_auth_only=yes

smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=may
smtp_tls_session_cache_database = btree:/var/lib/postfix/smtp_scache

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = $SMTP_HOST
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = $DOMAIN_NAME, $SMTP_HOST, localhost.$SMTP_HOST, localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all
EOF

# Open SMTP-related ports
iptables -C INPUT -p tcp --dport 25 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 25 -j ACCEPT
iptables -C INPUT -p tcp --dport 465 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 465 -j ACCEPT
iptables -C INPUT -p tcp --dport 587 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 587 -j ACCEPT

# Persist iptables rules
apt-get install -y iptables-persistent
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# Enable submission and smtps in master.cf if not already enabled
if ! grep -qE '^submission inet' /etc/postfix/master.cf; then
  cat >> /etc/postfix/master.cf <<'EOF'

submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=no
  -o smtpd_client_restrictions=permit_mynetworks,reject
EOF
fi

if ! grep -qE '^smtps     inet' /etc/postfix/master.cf; then
  cat >> /etc/postfix/master.cf <<'EOF'

smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=no
  -o smtpd_client_restrictions=permit_mynetworks,reject
EOF
fi

chmod 644 /etc/environment

# shellcheck disable=SC1091
source /etc/environment

echo "Saving up system settings"

systemctl restart postfix

echo "Enabling SMTP server on system start up"

systemctl enable postfix

echo "SMTP server successfully installed and configured"
