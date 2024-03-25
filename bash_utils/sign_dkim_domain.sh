apt-get install opendkim opendkim-tools

if [ ! -d "/etc/opendkim" ]; then
  mkdir /etc/opendkim/
fi

opendkim-genkey -D /etc/opendkim/ -d $(hostname -d) -s $(hostname)

chgrp opendkim /etc/opendkim/*
chmod g+r /etc/opendkim/*
gpasswd -a postfix opendkim

tee -a /etc/opendkim.conf  <<EOF
Canonicalization relaxed/relaxed
SyslogSuccess yes
KeyTable file:/etc/opendkim/keytable
SigningTable file:/etc/opendkim/signingtable
X-Header yes
LogWhy yes
#ExternalIgnoreList file:/etc/opendkim/trusted
#InternalHosts file:/etc/opendkim/internal
EOF

echo $(hostname -f | sed s/\\./._domainkey./) $(hostname -d):$(hostname):$(ls /etc/opendkim/*.private) | tee -a /etc/opendkim/keytable

echo $(hostname -d) $(hostname -f | sed s/\\./._domainkey./) | tee -a /etc/opendkim/signingtable

postconf -e milter_default_action=accept
postconf -e milter_protocol=2
postconf -e smtpd_milters=unix:/var/run/opendkim/opendkim.sock
postconf -e non_smtpd_milters=unix:/var/run/opendkim/opendkim.sock

echo 'SOCKET="local:/var/spool/postfix/var/run/opendkim/opendkim.sock"' | tee -a /etc/default/opendkim
mkdir -p /var/spool/postfix/var/run/opendkim
chown opendkim:opendkim /var/spool/postfix/var/run/opendkim

systemctl restart opendkim
systemctl restart postfix

echo "DKIM signed and saved on directory /etc/opendkim/$SMTP_HOST.txt"

cat /etc/opendkim/$SMTP_HOST.txt
