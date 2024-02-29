echo "Start setting up SSL for SMTP server domain"
echo "Type your SMTP hostname (ex. smtp.example.com):"
read smtp_host

apt-get install -y certbot

certbot certonly --standalone -d $smtp_host

hostname_ssl_path = /etc/ssl/postfix/fullchain.crt
hostname_privkey_path = /etc/ssl/postfix/privkey.pem

if [ ! -d /etc/ssl/postfix ]; then
  mkdir /etc/ssl/postfix
fi

cp /etc/letsencrypt/live/$smtp_host/fullchain.pem $hostname_ssl_path
cp /etc/letsencrypt/live/$smtp_host/privkey.pem $hostname_privkey_path