#!/usr/bin/env bash
# 13-deploy-website.sh — Deploy r_u.live React app to Coolify via API
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

SECRETS_FILE="$HOME/dev/.secrets.env"
COOLIFY_URL="${COOLIFY_URL:-https://localhost:8443}"
APP_DIR="$HOME/dev/server/r_u.live"
GITHUB_REPO="anshulyadav-git/setupx-linux"
APP_SUBDIRECTORY="server/r_u.live"
DOMAIN="r-u.live"

# ── Load or prompt for Coolify API token ─────────────────────────────────────
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi

if [[ -z "${COOLIFY_API_TOKEN:-}" ]]; then
  echo "Coolify API token not found in $SECRETS_FILE"
  echo "Generate one at: $COOLIFY_URL/profile  →  API Tokens"
  read -rsp "Paste your Coolify API token: " COOLIFY_API_TOKEN
  echo
  echo "COOLIFY_API_TOKEN=$COOLIFY_API_TOKEN" >> "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  echo "Token saved to $SECRETS_FILE"
fi

API="$COOLIFY_URL/api/v1"
AUTH="Authorization: Bearer $COOLIFY_API_TOKEN"

# ── Helper ────────────────────────────────────────────────────────────────────
api_get()  { curl -fsSLk -H "$AUTH" -H "Accept: application/json" "$API/$1"; }
api_post() { curl -fsSLk -X POST -H "$AUTH" -H "Content-Type: application/json" -d "$2" "$API/$1"; }

echo "==> [1/5] Verifying Coolify connection…"
api_get "health" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'message' in d or d" 2>/dev/null \
  || { echo "ERROR: Cannot reach Coolify API at $COOLIFY_URL"; exit 1; }
echo "    OK"

# ── Get first server UUID ─────────────────────────────────────────────────────
echo "==> [2/5] Fetching server UUID…"
SERVER_UUID=$(api_get "servers" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['uuid'])")
echo "    Server UUID: $SERVER_UUID"

# ── Create project (idempotent: reuse if exists) ──────────────────────────────
echo "==> [3/5] Ensuring project 'r_u_live' exists…"
EXISTING=$(api_get "projects" | python3 -c "
import sys, json
projects = json.load(sys.stdin)
for p in projects:
    if p.get('name') == 'r_u_live':
        print(p['uuid'])
        break
")

if [[ -n "$EXISTING" ]]; then
  PROJECT_UUID="$EXISTING"
  echo "    Reusing existing project: $PROJECT_UUID"
else
  PROJECT_UUID=$(api_post "projects" '{"name":"r_u_live","description":"Landing page for r-u.live"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
  echo "    Created project: $PROJECT_UUID"
fi

# ── Get environment UUID ('production' default) ───────────────────────────────
ENV_UUID=$(api_get "projects/$PROJECT_UUID/environments" \
  | python3 -c "import sys,json; envs=json.load(sys.stdin); print(envs[0]['uuid'])")
echo "    Environment UUID: $ENV_UUID"

# ── Create application ─────────────────────────────────────────────────────────
echo "==> [4/5] Creating / updating application…"

APP_PAYLOAD=$(python3 - <<PYEOF
import json
payload = {
  "type": "github",
  "name": "r_u_live",
  "description": "r-u.live landing page",
  "project_uuid": "$PROJECT_UUID",
  "environment_uuid": "$ENV_UUID",
  "server_uuid": "$SERVER_UUID",
  "github_app": None,
  "git_repository": "https://github.com/$GITHUB_REPO.git",
  "git_branch": "main",
  "git_commit_sha": "HEAD",
  "build_pack": "dockerfile",
  "dockerfile_location": "$APP_SUBDIRECTORY/Dockerfile",
  "base_directory": "/$APP_SUBDIRECTORY",
  "publish_directory": None,
  "ports_exposes": "80",
  "fqdn": "https://$DOMAIN",
  "instant_deploy": False
}
print(json.dumps(payload))
PYEOF
)

APP_RESPONSE=$(api_post "applications" "$APP_PAYLOAD" 2>&1 || true)

# Try to extract UUID whether it's a new create or already exists
APP_UUID=$(echo "$APP_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Could be {uuid:...} on create or {message:..., application:{uuid:...}} on duplicate
    if 'uuid' in d:
        print(d['uuid'])
    elif 'application' in d and 'uuid' in d['application']:
        print(d['application']['uuid'])
    else:
        print('')
except Exception:
    print('')
" 2>/dev/null)

if [[ -z "$APP_UUID" ]]; then
  echo "    Application may already exist or creation failed. Looking up by name…"
  APP_UUID=$(api_get "projects/$PROJECT_UUID/environments/$ENV_UUID/applications" 2>/dev/null | python3 -c "
import sys, json
try:
    apps = json.load(sys.stdin)
    for a in apps:
        if a.get('name') == 'r_u_live':
            print(a['uuid'])
            break
except Exception: pass
" 2>/dev/null || true)
fi

if [[ -z "$APP_UUID" ]]; then
  echo "ERROR: Could not get application UUID. Check Coolify UI manually."
  echo "API response was: $APP_RESPONSE"
  exit 1
fi

echo "    Application UUID: $APP_UUID"
# Save for future scripts
grep -q "^COOLIFY_APP_UUID=" "$SECRETS_FILE" 2>/dev/null \
  && sed -i "s|^COOLIFY_APP_UUID=.*|COOLIFY_APP_UUID=$APP_UUID|" "$SECRETS_FILE" \
  || echo "COOLIFY_APP_UUID=$APP_UUID" >> "$SECRETS_FILE"

# ── Trigger deployment ────────────────────────────────────────────────────────
echo "==> [5/5] Triggering deployment…"
DEPLOY_RESPONSE=$(api_post "applications/$APP_UUID/start" '{"force_rebuild":false}')
DEPLOY_UUID=$(echo "$DEPLOY_RESPONSE" | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('deployment_uuid','?'))
except: print('?')
")
echo "    Deployment triggered: $DEPLOY_UUID"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Coolify deploy triggered!"
echo "  App UUID   : $APP_UUID"
echo "  Deploy ID  : $DEPLOY_UUID"
echo "  Domain     : https://$DOMAIN"
echo "  Coolify UI : $COOLIFY_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Watch logs: $COOLIFY_URL/project/$PROJECT_UUID/environment/$ENV_UUID/application/$APP_UUID/deployment/$DEPLOY_UUID"
