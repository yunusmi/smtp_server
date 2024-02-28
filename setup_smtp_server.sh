apt-get update
echo "Start installing SMTP server"
echo 'debconf debconf/frontend select noninteractive' | sudo tee /etc/apt/apt.conf.d/99debconf-noninteractive

apt-get install -y mailutils
echo "Введите хост почтового сервера (прим. smtp.example.com):"
read smtp_host
echo "Введите домен почтового сервера (прим. example.com):"
read domain
echo "Saving up system settings"
systemctl restart postfix
echo "Enabling SMTP server on system restart"
systemctl enable postfix