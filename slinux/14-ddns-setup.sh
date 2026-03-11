#!/usr/bin/env bash
# 14-ddns-setup.sh — Deploy ddns-updater (Cloudflare auto-update) at dns.r-u.live
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

SECRETS_FILE="${HOME}/dev/.secrets.env"
DDNS_DIR="${HOME}/dev/server/ddns"
DOMAIN="r-u.live"
SERVER_IP="$(curl -fsSL https://api4.my-ip.io/v2/ip.json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['ip'])" 2>/dev/null || echo "20.244.41.88")"

[[ -f "$SECRETS_FILE" ]] && source "$SECRETS_FILE"

[[ -z "${CLOUDFLARE_API_TOKEN:-}" ]] && { echo "ERROR: CLOUDFLARE_API_TOKEN not set in $SECRETS_FILE"; exit 1; }

echo "==> [1/5] Getting Cloudflare Zone ID for $DOMAIN…"
ZONE_ID=$(curl -fsSL "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])")
echo "    Zone ID: $ZONE_ID"

echo "==> [2/5] Creating dns. subdomain A record in Cloudflare…"
EXISTING=$(curl -fsSL "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=dns.${DOMAIN}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id'] if r else '')" 2>/dev/null || true)

if [[ -n "$EXISTING" ]]; then
  curl -fsSL -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${EXISTING}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"A\",\"name\":\"dns\",\"content\":\"${SERVER_IP}\",\"ttl\":600,\"proxied\":false}" > /dev/null
  echo "    Updated existing record → $SERVER_IP"
else
  curl -fsSL -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"A\",\"name\":\"dns\",\"content\":\"${SERVER_IP}\",\"ttl\":600,\"proxied\":false}" > /dev/null
  echo "    Created dns.${DOMAIN} → $SERVER_IP"
fi

echo "==> [3/5] Generating ddns-updater config.json…"
mkdir -p "${DDNS_DIR}/data"

python3 - <<PYEOF
import json, subprocess, urllib.request, urllib.error

CF_TOKEN = "${CLOUDFLARE_API_TOKEN}"
ZONE_ID  = "${ZONE_ID}"
DOMAIN   = "${DOMAIN}"

# Fetch all existing A records from Cloudflare
req = urllib.request.Request(
    f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records?type=A&per_page=100",
    headers={"Authorization": f"Bearer {CF_TOKEN}", "Content-Type": "application/json"}
)
with urllib.request.urlopen(req) as resp:
    recs = json.loads(resp.read())["result"]

settings = []
seen = set()
for r in recs:
    # Extract host from full name
    host = r["name"].replace(f".{DOMAIN}", "").replace(DOMAIN, "@")
    if host in seen:
        continue
    seen.add(host)
    settings.append({
        "provider": "cloudflare",
        "zone_identifier": ZONE_ID,
        "domain": DOMAIN,
        "host": host,
        "proxied": r.get("proxied", False),
        "ttl": r.get("ttl", 600),
        "token": CF_TOKEN,
        "ip_version": "ipv4"
    })

config = {"settings": settings}
with open("${DDNS_DIR}/data/config.json", "w") as f:
    json.dump(config, f, indent=2)
print(f"    Written {len(settings)} records to config.json")
PYEOF

echo "==> [4/5] Starting ddns-updater container…"
docker compose -f "${DDNS_DIR}/docker-compose.yml" up -d --pull always

echo "==> [5/5] Configuring nginx for dns.${DOMAIN}…"
# Ensure htpasswd exists
if [[ ! -f /etc/nginx/.htpasswd ]]; then
  sudo htpasswd -bc /etc/nginx/.htpasswd admin "Admin1234"
fi
# Reload nginx
sudo nginx -t && sudo systemctl reload nginx

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ddns-updater deployed!"
echo "  URL      : https://dns.${DOMAIN}"
echo "  Login    : admin / Admin1234"
echo "  Records  : $(python3 -c "import json; c=json.load(open('${DDNS_DIR}/data/config.json')); print(len(c['settings']))")"
echo "  Interval : every 5 minutes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
