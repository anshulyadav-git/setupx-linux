#!/bin/bash
# [12] test-and-dns
# Tests every service component and updates Cloudflare DNS A records
# to the current server public IP.
#
# Usage:
#   bash 12-test-and-dns.sh           # test + update DNS
#   bash 12-test-and-dns.sh --test    # test only, skip DNS update
#   bash 12-test-and-dns.sh --dns     # DNS update only, skip tests

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[12/12] test-and-dns"

DOMAIN="r-u.live"
CF_ENV="$HOME/.cloudflared/.env"
SECRETS_FILE="$HOME/dev/.secrets.env"
REPORT_FILE="$HOME/dev/test-report-$(date +%Y%m%d-%H%M%S).txt"

MODE_TEST=true
MODE_DNS=true
[[ "${1:-}" == "--test" ]] && MODE_DNS=false
[[ "${1:-}" == "--dns"  ]] && MODE_TEST=false

# Load saved credentials
[[ -f "$CF_ENV"      ]] && source "$CF_ENV"
[[ -f "$SECRETS_FILE" ]] && source "$SECRETS_FILE"

# ── Helpers ────────────────────────────────────────────────
PASS=0; FAIL=0; WARN_COUNT=0
RESULTS=()

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

pass()  { echo -e "  ${GREEN}[PASS]${RESET} $*"; RESULTS+=("PASS  | $*"); ((PASS++))  || true; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $*"; RESULTS+=("FAIL  | $*"); ((FAIL++))  || true; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $*"; RESULTS+=("WARN  | $*"); ((WARN_COUNT++)) || true; }
header(){ echo -e "\n${BOLD}── $* ──────────────────────────────────${RESET}"; }

check_port() {
  local label=$1 host=$2 port=$3
  if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
    pass "$label  ($host:$port open)"
  else
    fail "$label  ($host:$port unreachable)"
  fi
}

check_http() {
  local label=$1 url=$2 expect_code=${3:-200}
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if [[ "$code" == "$expect_code" || "$code" =~ ^[23] ]]; then
    pass "$label  (HTTP $code)"
  else
    fail "$label  (HTTP $code, expected ~$expect_code) — $url"
  fi
}

check_service() {
  local label=$1 unit=$2
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    pass "$label  (systemd: $unit active)"
  else
    fail "$label  (systemd: $unit NOT active)"
  fi
}

check_docker() {
  local label=$1 name_pattern=$2
  local status
  status=$(docker ps --filter "name=$name_pattern" --format "{{.Status}}" 2>/dev/null | head -1)
  if [[ "$status" == Up* || "$status" == *healthy* ]]; then
    pass "$label  (docker: $status)"
  elif [[ -n "$status" ]]; then
    warn "$label  (docker: $status)"
  else
    fail "$label  (no container matching '$name_pattern')"
  fi
}

# ══════════════════════════════════════════════════════════════
if $MODE_TEST; then
echo -e "\n${BOLD}════════════════════════════════════════════"
echo "  COMPONENT TESTS"
echo -e "════════════════════════════════════════════${RESET}"

# ── 1. System ─────────────────────────────────────────────
header "System"
check_service  "UFW firewall"      "ufw"
check_service  "Nginx"             "nginx"
check_service  "BIND9 DNS"         "named"

# ── 2. PostgreSQL ─────────────────────────────────────────
header "PostgreSQL"
check_service  "PostgreSQL"        "postgresql"
check_port     "PostgreSQL port"   "127.0.0.1"  "5432"
if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
  if PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U postgres -c "SELECT version();" \
       -t --no-password 2>/dev/null | grep -q "PostgreSQL"; then
    PG_VER=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U postgres -t -c "SELECT version();" 2>/dev/null | head -1 | xargs)
    pass "PostgreSQL login  ($PG_VER)"
  else
    fail "PostgreSQL login  (auth failed — check POSTGRES_PASSWORD in $SECRETS_FILE)"
  fi
else
  warn "PostgreSQL login  (skipped — POSTGRES_PASSWORD not in $SECRETS_FILE)"
fi

# ── 3. Docker ─────────────────────────────────────────────
header "Docker"
check_service  "Docker daemon"     "docker"
if docker info &>/dev/null; then
  RUNNING=$(docker ps -q | wc -l)
  pass "Docker socket  ($RUNNING containers running)"
else
  fail "Docker socket  (permission denied?)"
fi

# ── 4. Supabase ───────────────────────────────────────────
header "Supabase"
check_docker   "Supabase Studio"   "supabase-studio"
check_docker   "Supabase Kong"     "supabase-kong"
check_docker   "Supabase DB"       "supabase-db"
check_port     "Studio port"       "127.0.0.1"  "3000"
check_port     "Kong API port"     "127.0.0.1"  "8000"
check_http     "Studio UI"         "http://localhost:3000"
check_http     "Supabase API"      "http://localhost:8000/rest/v1/" "200"

# ── 5. Coolify ────────────────────────────────────────────
header "Coolify"
check_docker   "Coolify main"      "coolify"
check_port     "Coolify port"      "127.0.0.1"  "8080"
check_http     "Coolify UI"        "http://localhost:8080"

# ── 6. Mail server ────────────────────────────────────────
header "Mail Server"
check_docker   "docker-mailserver" "mailserver"
check_port     "SMTP 25"           "127.0.0.1"  "25"
check_port     "SMTPS 465"         "127.0.0.1"  "465"
check_port     "Submission 587"    "127.0.0.1"  "587"
check_port     "IMAP 143"          "127.0.0.1"  "143"
check_port     "IMAPS 993"         "127.0.0.1"  "993"

# ── 7. Nginx HTTPS ────────────────────────────────────────
header "Nginx / SSL"
check_port     "HTTP 80"           "127.0.0.1"  "80"
check_port     "HTTPS 443"         "127.0.0.1"  "443"
SSL_EXPIRY=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
if [[ -n "$SSL_EXPIRY" ]]; then
  pass "SSL cert valid until $SSL_EXPIRY"
else
  warn "SSL cert check skipped (domain may not resolve to this server yet)"
fi

# ── 8. Cloudflare Tunnel ──────────────────────────────────
header "Cloudflare Tunnel"
check_service  "cloudflared"       "cloudflared"
if cloudflared tunnel list 2>/dev/null | grep -q "r-u-live"; then
  pass "Tunnel r-u-live  exists"
else
  fail "Tunnel r-u-live  not found"
fi

fi  # end MODE_TEST

# ══════════════════════════════════════════════════════════════
if $MODE_DNS; then
echo -e "\n${BOLD}════════════════════════════════════════════"
echo "  DNS UPDATE"
echo -e "════════════════════════════════════════════${RESET}"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  fail "DNS update skipped — CLOUDFLARE_API_TOKEN not set (run 11-cloudflare-domain.sh first)"
else
  # Get current public IP
  PUBLIC_IP=$(curl -sf "https://api64.ipify.org" || curl -sf "https://ifconfig.me" || true)
  if [[ -z "$PUBLIC_IP" ]]; then
    fail "DNS update — could not determine public IP"
  else
    echo "  Public IP: $PUBLIC_IP"

    # Get Zone ID (from env or API)
    if [[ -z "${CF_ZONE_ID:-}" ]]; then
      CF_ZONE_ID=$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
        python3 -c "import sys,json; z=json.load(sys.stdin)['result']; print(z[0]['id']) if z else sys.exit(1)")
    fi

    update_dns_record() {
      local hostname=$1
      local rec_type=${2:-A}

      # Check if record exists
      EXISTING=$(curl -sf \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=$rec_type&name=$hostname" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
        python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id']+'|'+r[0]['content']) if r else print('')")

      if [[ -z "$EXISTING" ]]; then
        # Create
        RESULT=$(curl -sf -X POST \
          "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"$rec_type\",\"name\":\"$hostname\",\"content\":\"$PUBLIC_IP\",\"proxied\":true,\"ttl\":1}" | \
          python3 -c "import sys,json; d=json.load(sys.stdin); print('created' if d.get('success') else d)")
        pass "DNS $rec_type $hostname → $PUBLIC_IP  ($RESULT)"
      else
        REC_ID="${EXISTING%%|*}"
        OLD_IP="${EXISTING##*|}"
        if [[ "$OLD_IP" == "$PUBLIC_IP" ]]; then
          pass "DNS $rec_type $hostname → $PUBLIC_IP  (already current)"
        else
          # Update
          RESULT=$(curl -sf -X PUT \
            "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$REC_ID" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$rec_type\",\"name\":\"$hostname\",\"content\":\"$PUBLIC_IP\",\"proxied\":true,\"ttl\":1}" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print('updated' if d.get('success') else d)")
          pass "DNS $rec_type $hostname  $OLD_IP → $PUBLIC_IP  ($RESULT)"
        fi
      fi
    }

    update_dns_record "$DOMAIN"
    update_dns_record "supabase.$DOMAIN"
    update_dns_record "api.$DOMAIN"
    update_dns_record "coolify.$DOMAIN"
    update_dns_record "mail.$DOMAIN"

    # Save public IP to secrets
    touch "$SECRETS_FILE" && chmod 600 "$SECRETS_FILE"
    grep -v '^SERVER_PUBLIC_IP=' "$SECRETS_FILE" > "${SECRETS_FILE}.tmp" 2>/dev/null || true
    mv "${SECRETS_FILE}.tmp" "$SECRETS_FILE"
    echo "SERVER_PUBLIC_IP=$PUBLIC_IP" >> "$SECRETS_FILE"
    echo "  Server IP saved to $SECRETS_FILE"
  fi
fi

fi  # end MODE_DNS

# ══════════════════════════════════════════════════════════════
# Report
# ══════════════════════════════════════════════════════════════
echo -e "\n${BOLD}════════════════════════════════════════════"
echo "  SUMMARY"
echo -e "════════════════════════════════════════════${RESET}"

printf "  %-8s %s\n" "PASS"  "$PASS"
printf "  %-8s %s\n" "WARN"  "$WARN_COUNT"
printf "  %-8s %s\n" "FAIL"  "$FAIL"

# Write full report
{
  echo "Test Report — $(date)"
  echo "Server: $(hostname) / ${PUBLIC_IP:-unknown}"
  echo "Domain: $DOMAIN"
  echo "────────────────────────────────────────────"
  printf "%-6s | %s\n" "STATUS" "CHECK"
  echo "────────────────────────────────────────────"
  for r in "${RESULTS[@]}"; do echo "$r"; done
  echo "────────────────────────────────────────────"
  echo "PASS=$PASS  WARN=$WARN_COUNT  FAIL=$FAIL"
} > "$REPORT_FILE"
echo "  Report: $REPORT_FILE"

if [[ $FAIL -gt 0 ]]; then
  echo -e "\n  ${RED}${FAIL} check(s) failed — review above.${RESET}"
  exit 1
else
  echo -e "\n  ${GREEN}All checks passed!${RESET}"
fi
