#!/bin/bash
# [11] cloudflare-domain
# Phases:
#   A) Save API token securely
#   B) Test Cloudflare API connectivity
#   C) Create Cloudflare Tunnel + DNS for r-u.live & subdomains
#   D) Issue wildcard SSL cert (Let's Encrypt via Cloudflare DNS challenge)
#   E) Configure Nginx HTTPS virtual hosts for all subdomains
#   F) Install tunnel as systemd service
#
# Usage:
#   CLOUDFLARE_API_TOKEN=<token> bash 11-cloudflare-domain.sh
#   bash 11-cloudflare-domain.sh    # prompts for token, saves to ~/.cloudflared/.env

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[11/12] cloudflare-domain"

DOMAIN="r-u.live"
TUNNEL_NAME="r-u-live"
CF_DIR="$HOME/.cloudflared"
CF_ENV="$CF_DIR/.env"
CONFIG_FILE="$CF_DIR/config.yml"

SUBDOMAINS=("supabase" "api" "coolify" "mail")
ALL_HOSTS=("$DOMAIN")
for sub in "${SUBDOMAINS[@]}"; do
  ALL_HOSTS+=("$sub.$DOMAIN")
done

mkdir -p "$CF_DIR"
chmod 700 "$CF_DIR"

# =============================================================
# PHASE A — Token
# =============================================================
echo ""
echo "══════════════════════════════════════════════"
echo " PHASE A — Cloudflare API Token"
echo "══════════════════════════════════════════════"

if [[ -f "$CF_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$CF_ENV"
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "Enter your Cloudflare API token (input hidden):"
  read -rsp "  Token: " CLOUDFLARE_API_TOKEN
  echo ""
  { echo "CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN"; } > "$CF_ENV"
  chmod 600 "$CF_ENV"
  echo "Token saved to $CF_ENV (mode 600)"
else
  echo "Token loaded from $CF_ENV"
fi

export CLOUDFLARE_API_TOKEN

# =============================================================
# PHASE B — Test API connectivity
# =============================================================
echo ""
echo "══════════════════════════════════════════════"
echo " PHASE B — Testing Cloudflare API"
echo "══════════════════════════════════════════════"

CF_VERIFY=$(curl -sf "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")

if echo "$CF_VERIFY" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)"; then
  echo "API token is valid"
else
  echo "$CF_VERIFY"
  echo "[ERROR] Token verification failed. Revoke it and generate a new one." >&2
  exit 1
fi

if [[ -z "${CF_ZONE_ID:-}" ]]; then
  CF_ZONE_ID=$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
    python3 -c "import sys,json; z=json.load(sys.stdin)['result']; print(z[0]['id']) if z else sys.exit(1)")
  # Persist Zone ID to .env
  if grep -q "^CF_ZONE_ID=" "$CF_ENV" 2>/dev/null; then
    sed -i "s|^CF_ZONE_ID=.*|CF_ZONE_ID=$CF_ZONE_ID|" "$CF_ENV"
  else
    echo "CF_ZONE_ID=$CF_ZONE_ID" >> "$CF_ENV"
  fi
  echo "Zone ID saved to $CF_ENV"
else
  echo "Zone ID loaded from $CF_ENV: $CF_ZONE_ID"
fi
export CF_ZONE_ID
echo "Zone ID for $DOMAIN: $CF_ZONE_ID"

# =============================================================
# PHASE C — Cloudflare Tunnel + DNS
# =============================================================
echo ""
echo "══════════════════════════════════════════════"
echo " PHASE C — Cloudflare Tunnel"
echo "══════════════════════════════════════════════"

if ! command -v cloudflared &>/dev/null; then
  echo "[ERROR] cloudflared not installed. Run 04-ide-dev.sh first." >&2
  exit 1
fi
echo "cloudflared $(cloudflared --version 2>&1 | head -1)"

echo "Authenticating..."
cloudflared tunnel login

echo "Creating tunnel: $TUNNEL_NAME"
if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
  echo "Tunnel '$TUNNEL_NAME' already exists."
else
  cloudflared tunnel create "$TUNNEL_NAME"
fi

if [[ -z "${TUNNEL_UUID:-}" ]]; then
  TUNNEL_UUID=$(cloudflared tunnel list --output json 2>/dev/null \
    | python3 -c "import sys,json; [print(t['id']) for t in json.load(sys.stdin) if t['name']=='$TUNNEL_NAME']")
  [[ -z "$TUNNEL_UUID" ]] && { echo "[ERROR] Could not get tunnel UUID." >&2; exit 1; }
  # Persist Tunnel UUID to .env
  if grep -q "^TUNNEL_UUID=" "$CF_ENV" 2>/dev/null; then
    sed -i "s|^TUNNEL_UUID=.*|TUNNEL_UUID=$TUNNEL_UUID|" "$CF_ENV"
  else
    echo "TUNNEL_UUID=$TUNNEL_UUID" >> "$CF_ENV"
  fi
  echo "Tunnel UUID saved to $CF_ENV"
else
  echo "Tunnel UUID loaded from $CF_ENV: $TUNNEL_UUID"
fi
export TUNNEL_UUID
echo "Tunnel UUID: $TUNNEL_UUID"

cat > "$CONFIG_FILE" << CFEOF
tunnel: $TUNNEL_UUID
credentials-file: $CF_DIR/$TUNNEL_UUID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - hostname: supabase.$DOMAIN
    service: http://localhost:3000
  - hostname: api.$DOMAIN
    service: http://localhost:8000
  - hostname: coolify.$DOMAIN
    service: http://localhost:8080
  - hostname: mail.$DOMAIN
    service: http://localhost:8025
  - service: http_status:404
CFEOF
echo "Config written: $CONFIG_FILE"

echo "Routing DNS..."
for host in "${ALL_HOSTS[@]}"; do
  cloudflared tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$host" && \
    echo "  [OK] $host" || \
    echo "  [WARN] Could not route $host"
done

# =============================================================
# PHASE D — Wildcard SSL via Let's Encrypt + Cloudflare DNS
# =============================================================
echo ""
echo "══════════════════════════════════════════════"
echo " PHASE D — Wildcard SSL Certificate"
echo "══════════════════════════════════════════════"

sudo apt-get install -y python3-certbot-dns-cloudflare

CERTBOT_CF_INI="/etc/letsencrypt/cloudflare.ini"
sudo mkdir -p /etc/letsencrypt
sudo bash -c "echo 'dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN' > $CERTBOT_CF_INI"
sudo chmod 600 "$CERTBOT_CF_INI"
echo "Certbot credentials: $CERTBOT_CF_INI"

echo "Requesting wildcard certificate for $DOMAIN and *.$DOMAIN ..."
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$CERTBOT_CF_INI" \
  --dns-cloudflare-propagation-seconds 30 \
  -d "$DOMAIN" \
  -d "*.$DOMAIN" \
  --email "admin@$DOMAIN" \
  --agree-tos \
  --non-interactive \
  --expand

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
[[ ! -f "$CERT_PATH" ]] && { echo "[ERROR] Certificate not found at $CERT_PATH" >&2; exit 1; }
echo "Certificate issued: $CERT_PATH"

# =============================================================
# PHASE E — Nginx HTTPS vhosts
# =============================================================
echo ""
echo "══════════════════════════════════════════════"
echo " PHASE E — Nginx HTTPS Virtual Hosts"
echo "══════════════════════════════════════════════"

write_nginx_vhost() {
  local hostname=$1
  local port=$2
  local conffile="/etc/nginx/sites-available/$hostname"
  sudo bash -c "cat > $conffile" << NGEOF
server {
    listen 80;
    server_name $hostname;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $hostname;

    ssl_certificate     $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600;
    }
}
NGEOF
  sudo ln -sf "$conffile" "/etc/nginx/sites-enabled/$hostname"
  echo "  [OK] $hostname -> :$port"
}

write_nginx_vhost "$DOMAIN"           80
write_nginx_vhost "supabase.$DOMAIN"  3000
write_nginx_vhost "api.$DOMAIN"       8000
write_nginx_vhost "coolify.$DOMAIN"   8080
write_nginx_vhost "mail.$DOMAIN"      8025

sudo nginx -t && sudo systemctl reload nginx
echo "Nginx reloaded."

# Auto-reload nginx on cert renewal
sudo bash -c 'cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh' << 'HOOKEOF'
#!/bin/bash
systemctl reload nginx
HOOKEOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# =============================================================
# PHASE F — Tunnel systemd service
# =============================================================
echo ""
echo "══════════════════════════════════════════════"
echo " PHASE F — Tunnel systemd Service"
echo "══════════════════════════════════════════════"

sudo cloudflared --config "$CONFIG_FILE" service install 2>/dev/null || true
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared
sudo systemctl status cloudflared --no-pager

# =============================================================
# Summary — save all URLs + print full credentials
# =============================================================
SECRETS_FILE="$HOME/dev/.secrets.env"
touch "$SECRETS_FILE" && chmod 600 "$SECRETS_FILE"

# Remove old URL block then append fresh one
grep -v '^CF_\|^PUBLIC_\|^CLOUDFLARE_URL\|^COOLIFY_URL\|^SUPABASE_PUBLIC\|^MAIL_PUBLIC' \
  "$SECRETS_FILE" > "${SECRETS_FILE}.tmp" 2>/dev/null || true
mv "${SECRETS_FILE}.tmp" "$SECRETS_FILE"

cat >> "$SECRETS_FILE" << URLS

# Cloudflare / Public URLs (set by 11-cloudflare-domain.sh)
CLOUDFLARE_TUNNEL_UUID=$TUNNEL_UUID
CLOUDFLARE_ZONE_ID=$CF_ZONE_ID
PUBLIC_URL=https://$DOMAIN
PUBLIC_SUPABASE_STUDIO_URL=https://supabase.$DOMAIN
PUBLIC_SUPABASE_API_URL=https://api.$DOMAIN
PUBLIC_COOLIFY_URL=https://coolify.$DOMAIN
PUBLIC_MAIL_URL=https://mail.$DOMAIN
URLS

echo "URLs saved to $SECRETS_FILE"

# =============================================================
# Full Credentials Summary
# =============================================================
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ALL SERVICES — CREDENTIALS SUMMARY"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  Domain        : $DOMAIN"
echo "  Wildcard SSL  : /etc/letsencrypt/live/$DOMAIN/"
echo "  Tunnel        : $TUNNEL_NAME ($TUNNEL_UUID)"
echo ""
echo "  ── Public URLs ──────────────────────────────────────────"
echo "  Website       : https://$DOMAIN"
echo "  Supabase UI   : https://supabase.$DOMAIN"
echo "  Supabase API  : https://api.$DOMAIN"
echo "  Coolify       : https://coolify.$DOMAIN"
echo "  Mail UI       : https://mail.$DOMAIN"
echo ""
echo "  ── PostgreSQL ───────────────────────────────────────────"
grep -E '^POSTGRES_(HOST|PORT|USER|PASSWORD|URL)=' "$SECRETS_FILE" 2>/dev/null \
  | sed 's/^/  /' || echo "  (run 07-postgre.sh to populate)"
echo ""
echo "  ── Supabase ─────────────────────────────────────────────"
grep -E '^SUPABASE_(DASHBOARD|POSTGRES_PASSWORD|JWT|ANON|SERVICE)' "$SECRETS_FILE" 2>/dev/null \
  | sed 's/^/  /' || echo "  (run 08-supabase.sh to populate)"
echo ""
echo "  ── Mail Server ──────────────────────────────────────────"
grep -E '^MAIL_(DOMAIN|HOSTNAME|SMTP|IMAP|POP3|ADMIN)' "$SECRETS_FILE" 2>/dev/null \
  | sed 's/^/  /' || echo "  (run 10-mailserver.sh to populate)"
echo ""
echo "  ── Coolify ──────────────────────────────────────────────"
echo "  URL           : https://coolify.$DOMAIN"
echo "  Admin setup   : first-run via browser"
echo ""
echo "  Secrets file  : $SECRETS_FILE (mode 600)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Cert auto-renewal: systemctl status certbot.timer"
echo "══════════════════════════════════════════════════════════════"
