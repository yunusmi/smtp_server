echo "Start uninstalling SMTP server"

echo 'debconf debconf/frontend select noninteractive'
apt purge -y mailutils
apt purge -y certbot

apt autoremove

if [ -d "/etc/ssl/postfix" ]; then
  rm -rf /etc/ssl/postfix
fi

if [ -d "/etc/letsencrypt" ]; then
  rm -rf /etc/letsencrypt
fi

echo 'debconf debconf/frontend select interactive'

echo "SMTP server is removed"