echo "Start setting up SSL for SMTP server domain"

apt-get install -y certbot

certbot certonly --standalone -d $SMTP_HOST

if [ ! -d "/etc/ssl/postfix" ]; then
  mkdir /etc/ssl/postfix
fi

cp /etc/letsencrypt/live/$SMTP_HOST/fullchain.pem $HOSTNAME_SSL_PATH
cp /etc/letsencrypt/live/$SMTP_HOST/privkey.pem $HOSTNAME_PRIVKEY_PATH