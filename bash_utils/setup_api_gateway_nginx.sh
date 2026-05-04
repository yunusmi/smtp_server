#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
source /etc/environment

echo "Type your API gateway hostname (ex. api.example.com):"
read API_HOST

if [ -z "$API_HOST" ]; then
  echo "API_HOST is required"
  exit 1
fi

APP_PORT="${API_PORT:-3001}"

sed -i '/^API_HOST=/d' /etc/environment
echo "API_HOST=$API_HOST" >> /etc/environment

echo "Installing nginx and certbot nginx plugin"

apt-get update
apt-get install -y nginx python3-certbot-nginx

echo "Writing nginx server block for $API_HOST -> 127.0.0.1:$APP_PORT"

cat > /etc/nginx/sites-available/api-gateway <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $API_HOST;

    location / {
        proxy_pass         http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/api-gateway /etc/nginx/sites-enabled/api-gateway
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

echo "Opening HTTP and HTTPS ports in iptables"

iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 443 -j ACCEPT

if command -v iptables-save >/dev/null 2>&1 && [ -d /etc/iptables ]; then
  iptables-save > /etc/iptables/rules.v4
fi

echo "Issuing Let's Encrypt certificate for $API_HOST"

certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email --redirect -d "$API_HOST"

systemctl enable nginx
systemctl enable certbot.timer 2>/dev/null || true

echo "API gateway is now reachable at https://$API_HOST"
echo "Certificate auto-renewal is handled by the certbot.timer systemd unit"
