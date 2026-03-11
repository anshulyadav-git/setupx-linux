#!/bin/bash
# [10] mailserver

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[10/10] mailserver"

MAIL_DIR="$HOME/mailserver"
DOMAIN="${MAIL_DOMAIN:-example.com}"
HOSTNAME="${MAIL_HOSTNAME:-mail}"

echo "Setting up docker-mailserver for domain: $DOMAIN"

mkdir -p "$MAIL_DIR"
cd "$MAIL_DIR"

echo "Downloading docker-compose and config files..."
curl -fsSL https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master/compose.yaml -o compose.yaml
curl -fsSL https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master/mailserver.env -o mailserver.env

echo "Configuring environment..."
sed -i "s|^OVERRIDE_HOSTNAME=.*|OVERRIDE_HOSTNAME=$HOSTNAME.$DOMAIN|" mailserver.env
sed -i "s|^DOMAINNAME=.*|DOMAINNAME=$DOMAIN|" mailserver.env
sed -i "s|^POSTMASTER_ADDRESS=.*|POSTMASTER_ADDRESS=postmaster@$DOMAIN|" mailserver.env
sed -i "s|^NETWORK_INTERFACE=.*|NETWORK_INTERFACE=eth0|" mailserver.env

# Enable spam filtering (ClamAV disabled by default - enable after SSL is configured)
sed -i "s|^ENABLE_SPAMASSASSIN=.*|ENABLE_SPAMASSASSIN=1|" mailserver.env
sed -i "s|^ENABLE_CLAMAV=.*|ENABLE_CLAMAV=0|" mailserver.env
sed -i "s|^ENABLE_FAIL2BAN=.*|ENABLE_FAIL2BAN=1|" mailserver.env
sed -i "s|^ENABLE_POSTGREY=.*|ENABLE_POSTGREY=1|" mailserver.env

# Use host networking to avoid Docker pool conflicts
cat > compose.override.yaml << 'YAML'
services:
  mailserver:
    network_mode: "host"
    networks: {}
networks: {}
YAML

echo "Opening mail ports in UFW..."
sudo ufw allow 25/tcp   comment 'SMTP'
sudo ufw allow 465/tcp  comment 'SMTPS'
sudo ufw allow 587/tcp  comment 'SMTP Submission'
sudo ufw allow 110/tcp  comment 'POP3'
sudo ufw allow 995/tcp  comment 'POP3S'
sudo ufw allow 143/tcp  comment 'IMAP'
sudo ufw allow 993/tcp  comment 'IMAPS'

echo "Starting mail server containers..."
docker compose up -d

echo "Waiting for container to be ready..."
sleep 20

echo "Setting up DKIM keys..."
docker exec mailserver setup config dkim domain "$DOMAIN"

# Save credentials to central secrets file
SECRETS_FILE="$HOME/dev/.secrets.env"
touch "$SECRETS_FILE" && chmod 600 "$SECRETS_FILE"
grep -v '^MAIL_' "$SECRETS_FILE" > "${SECRETS_FILE}.tmp" 2>/dev/null || true
mv "${SECRETS_FILE}.tmp" "$SECRETS_FILE"
cat >> "$SECRETS_FILE" << CREDS

# Mail Server
MAIL_DOMAIN=$DOMAIN
MAIL_HOSTNAME=$HOSTNAME.$DOMAIN
MAIL_SMTP_HOST=$HOSTNAME.$DOMAIN
MAIL_SMTP_PORT=587
MAIL_IMAP_HOST=$HOSTNAME.$DOMAIN
MAIL_IMAP_PORT=993
MAIL_POP3_HOST=$HOSTNAME.$DOMAIN
MAIL_POP3_PORT=995
MAIL_ADMIN=postmaster@$DOMAIN
CREDS
echo "Mail details saved to $SECRETS_FILE"

echo ""
echo "Mail server is running!"
echo "  SMTP:        $HOSTNAME.$DOMAIN:25"
echo "  SMTP Submit: $HOSTNAME.$DOMAIN:587"
echo "  IMAPS:       $HOSTNAME.$DOMAIN:993"
echo "  POP3S:       $HOSTNAME.$DOMAIN:995"
echo ""
echo "To add a mail account:"
echo "  docker exec mailserver setup email add user@$DOMAIN"
echo ""
echo "DKIM key (add as DNS TXT record: mail._domainkey.$DOMAIN):"
cat "$MAIL_DIR/docker-data/dms/config/opendkim/keys/$DOMAIN/mail.txt" 2>/dev/null \
  || echo "  (check $MAIL_DIR/docker-data/dms/config/opendkim/keys/$DOMAIN/mail.txt after startup)"
echo ""
echo "To stop:    docker compose -f $MAIL_DIR/compose.yaml down"
echo "To restart: docker compose -f $MAIL_DIR/compose.yaml restart"
echo ""
echo "Run with custom domain: MAIL_DOMAIN=yourdomain.com bash mailserver.sh"
