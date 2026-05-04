#!/bin/bash
set -e

# shellcheck disable=SC1091
source /etc/environment

if [ -z "$SMTP_HOST" ]; then
  echo "SMTP_HOST is not set in /etc/environment. Run setup_smtp_server.sh first."
  exit 1
fi

echo "Start updating SSL for SMTP server domain: $SMTP_HOST"

certbot renew --standalone --non-interactive

if [ ! -d "/etc/ssl/postfix" ]; then
  mkdir -p /etc/ssl/postfix
fi

cp "/etc/letsencrypt/live/$SMTP_HOST/fullchain.pem" "$HOSTNAME_SSL_PATH"
cp "/etc/letsencrypt/live/$SMTP_HOST/privkey.pem" "$HOSTNAME_PRIVKEY_PATH"

systemctl reload postfix

echo "SSL certificate successfully renewed and applied"
