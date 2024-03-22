apt-get update
echo "Start installing SMTP server"
echo 'debconf debconf/frontend select noninteractive'
apt-get install -y mailutils
echo "Type your main domain name (ex. example.com):"
read DOMAIN_NAME
echo "Type your SMTP hostname (ex. smtp.example.com):"
read SMTP_HOST
echo "DOMAIN_NAME=$DOMAIN_NAME" >> /etc/environment
echo "SMTP_HOST=$SMTP_HOST" >> /etc/environment
apt-get install -y certbot
certbot certonly --standalone -d $SMTP_HOST
if [ ! -d "/etc/ssl/postfix" ]; then
  mkdir /etc/ssl/postfix
fi
HOSTNAME_SSL_PATH=/etc/ssl/postfix/fullchain.crt
HOSTNAME_PRIVKEY_PATH=/etc/ssl/postfix/privkey.pem
echo "HOSTNAME_SSL_PATH=$HOSTNAME_SSL_PATH" >> /etc/environment
echo "HOSTNAME_PRIVKEY_PATH=$HOSTNAME_PRIVKEY_PATH" >> /etc/environment
cp /etc/letsencrypt/live/$SMTP_HOST/fullchain.pem $HOSTNAME_SSL_PATH
cp /etc/letsencrypt/live/$SMTP_HOST/privkey.pem $HOSTNAME_PRIVKEY_PATH
rm /etc/postfix/main.cf
echo "# See /usr/share/postfix/main.cf.dist for a commented, more complete version

# Debian specific:  Specifying a file name will cause the first
# line of that file to be used as the name.  The Debian default
# is /etc/mailname.
#myorigin = /etc/mailname

smtpd_banner =  ESMTP  (Ubuntu)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate delayed mail warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 3.6 on
# fresh installs.
compatibility_level = 3.6

# TLS parameters
smtpd_tls_cert_file=$HOSTNAME_SSL_PATH
smtpd_tls_key_file=$HOSTNAME_PRIVKEY_PATH
smtpd_tls_security_level=encrypt

smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=may
smtp_tls_session_cache_database = btree:/smtp_scache

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = $SMTP_HOST
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = $DOMAIN_NAME, $SMTP_HOST, localhost.$SMTP_HOST, localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = loopback_only
inet_protocols = all" >> /etc/postfix/main.cf
iptables -A INPUT -p tcp --dport 465 -j ACCEPT
echo "465 inet n - n - - smtpd" >> /etc/postfix/master.cf
iptables -A INPUT -p tcp --dport 25 -j ACCEPT
iptables-save
chmod 644 /etc/environment
source /etc/environment
echo 'debconf debconf/frontend select interactive'
echo "Saving up system settings"
systemctl restart postfix
echo "Enabling SMTP server on system start up"
systemctl enable postfix