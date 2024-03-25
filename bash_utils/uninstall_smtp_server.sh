echo "Start uninstalling SMTP server"

echo 'debconf debconf/frontend select noninteractive'

apt purge -y mailutils
apt purge -y certbot
apt purge -y sendmail

apt purge -y opendkim
apt purge -y opendkim-tools

apt autoremove -y

if [ -d "/etc/ssl/postfix" ]; then
  rm -rf /etc/ssl/postfix
fi

if [ -d "/etc/letsencrypt" ]; then
  rm -rf /etc/letsencrypt
fi

if [ -d "/etc/opendkim" ]; then
  rm -rf /etc/opendkim
fi

sed -i '/DOMAIN_NAME/d' /etc/environment
sed -i '/SMTP_HOST/d' /etc/environment
sed -i '/HOSTNAME_SSL_PATH/d' /etc/environment
sed -i '/HOSTNAME_PRIVKEY_PATH/d' /etc/environment

echo 'debconf debconf/frontend select interactive'

echo "SMTP server is removed"