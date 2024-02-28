apt-get update
echo "Start installing SMTP server"
echo 'debconf debconf/frontend select noninteractive'

apt-get install -y mailutils
echo "Type your main domain name (ex. example.com):"
read domain_name
echo "Type your SMTP hostname (ex. smtp.example.com):"
read smtp_host

apt-get install -y certbot

certbot certonly --standalone -d $smtp_host

hostname_ssl_path=/etc/ssl/postfix/fullchain.crt
hostname_privkey_path=/etc/ssl/postfix/privkey.pem

if [ ! -d /etc/ssl/postfix ]; then
  mkdir /etc/ssl/postfix
fi

cp /etc/letsencrypt/live/$smtp_host/fullchain.pem $hostname_ssl_path
cp /etc/letsencrypt/live/$smtp_host/privkey.pem $hostname_privkey_path

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
smtpd_tls_cert_file=$hostname_ssl_path
smtpd_tls_key_file=$hostname_privkey_path
smtpd_tls_security_level=encrypt

smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=may
smtp_tls_session_cache_database = btree:/smtp_scache

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = $smtp_host
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = $domain_name, $smtp_host, localhost.$smtp_host, localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = loopback_only
inet_protocols = all" >> /etc/postfix/main.cf

iptables -A INPUT -p tcp --dport 465 -j ACCEPT
echo "465 inet n - n - - smtpd" >> /etc/postfix/master.cf

iptables -A INPUT -p tcp --dport 25 -j ACCEPT

iptables-save

echo 'debconf debconf/frontend select interactive'

echo "Saving up system settings"
systemctl restart postfix
echo "Enabling SMTP server on system start up"
systemctl enable postfix