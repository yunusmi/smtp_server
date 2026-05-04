#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "Start uninstalling SMTP server"

systemctl stop postfix 2>/dev/null || true
systemctl stop opendkim 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

apt-get purge -y postfix mailutils certbot opendkim opendkim-tools nginx python3-certbot-nginx || true
apt-get autoremove -y

rm -f /etc/nginx/sites-available/api-gateway /etc/nginx/sites-enabled/api-gateway

if [ -d "/etc/ssl/postfix" ]; then
  rm -rf /etc/ssl/postfix
fi

if [ -d "/etc/letsencrypt" ]; then
  rm -rf /etc/letsencrypt
fi

if [ -d "/etc/opendkim" ]; then
  rm -rf /etc/opendkim
fi

if [ -d "/etc/postfix" ]; then
  rm -rf /etc/postfix
fi

rm -f /etc/opendkim.conf

sed -i '/^DOMAIN_NAME=/d' /etc/environment
sed -i '/^SMTP_HOST=/d' /etc/environment
sed -i '/^HOSTNAME_SSL_PATH=/d' /etc/environment
sed -i '/^HOSTNAME_PRIVKEY_PATH=/d' /etc/environment
sed -i '/^API_HOST=/d' /etc/environment

echo "SMTP server is removed"
