echo "Start updating SSL for SMTP server domain"

certbot certonly -d $SMTP_HOST

if [ ! -d "/etc/ssl/postfix" ]; then
  mkdir /etc/ssl/postfix
fi

cp /etc/letsencrypt/live/$SMTP_HOST/fullchain.pem $HOSTNAME_SSL_PATH
cp /etc/letsencrypt/live/$SMTP_HOST/privkey.pem $HOSTNAME_PRIVKEY_PATH