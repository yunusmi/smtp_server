echo "Start uninstalling SMTP server"

echo 'debconf debconf/frontend select noninteractive'
apt purge mailutils
apt purge certbot

apt autoremove
echo 'debconf debconf/frontend select interactive'

echo "SMTP server is removed"