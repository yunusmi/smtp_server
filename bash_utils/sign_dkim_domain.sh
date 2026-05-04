#!/bin/bash
set -e

# shellcheck disable=SC1091
source /etc/environment

if [ -z "$SMTP_HOST" ] || [ -z "$DOMAIN_NAME" ]; then
  echo "SMTP_HOST and DOMAIN_NAME must be set in /etc/environment. Run setup_smtp_server.sh first."
  exit 1
fi

echo "Start signing DKIM for $SMTP_HOST"

apt-get update
apt-get install -y opendkim opendkim-tools

if [ ! -d "/etc/opendkim" ]; then
  mkdir -p /etc/opendkim
fi

opendkim-genkey -D /etc/opendkim/ -d "$(hostname -d)" -s "$(hostname)"

chgrp opendkim /etc/opendkim/*
chmod g+r /etc/opendkim/*
gpasswd -a postfix opendkim

if ! grep -q '^Canonicalization' /etc/opendkim.conf; then
  tee -a /etc/opendkim.conf > /dev/null <<EOF
Canonicalization relaxed/relaxed
SyslogSuccess yes
KeyTable file:/etc/opendkim/keytable
SigningTable file:/etc/opendkim/signingtable
X-Header yes
LogWhy yes
#ExternalIgnoreList file:/etc/opendkim/trusted
#InternalHosts file:/etc/opendkim/internal
EOF
fi

echo "$(hostname -f | sed 's/\./._domainkey./') $(hostname -d):$(hostname):$(ls /etc/opendkim/*.private)" | tee -a /etc/opendkim/keytable

echo "$(hostname -d) $(hostname -f | sed 's/\./._domainkey./')" | tee -a /etc/opendkim/signingtable

postconf -e milter_default_action=accept
postconf -e milter_protocol=2
postconf -e smtpd_milters=unix:/var/run/opendkim/opendkim.sock
postconf -e non_smtpd_milters=unix:/var/run/opendkim/opendkim.sock

if ! grep -q '^SOCKET=' /etc/default/opendkim; then
  echo 'SOCKET="local:/var/spool/postfix/var/run/opendkim/opendkim.sock"' | tee -a /etc/default/opendkim
fi

mkdir -p /var/spool/postfix/var/run/opendkim
chown opendkim:opendkim /var/spool/postfix/var/run/opendkim

systemctl restart opendkim
systemctl enable opendkim
systemctl restart postfix

echo "DKIM signed and saved on directory /etc/opendkim/$(hostname).txt"
echo "Add the following TXT record to your DNS:"
echo "------------------------------------------"
cat /etc/opendkim/$(hostname).txt
echo "------------------------------------------"
