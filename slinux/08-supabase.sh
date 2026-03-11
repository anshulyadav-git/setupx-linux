#!/bin/bash
# [08] supabase

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[08/10] supabase"

SUPABASE_DIR="$HOME/supabase"

echo "Cloning Supabase self-hosting files..."
if [ -d "$SUPABASE_DIR" ]; then
  echo "Directory $SUPABASE_DIR already exists, pulling latest..."
  git -C "$SUPABASE_DIR" pull
else
  git clone --depth 1 https://github.com/supabase/supabase "$SUPABASE_DIR"
fi

echo "Setting up environment..."
cd "$SUPABASE_DIR/docker"
cp .env.example .env

echo "Generating secrets..."
JWT_SECRET=$(openssl rand -base64 32)
ANON_KEY=$(openssl rand -base64 32)
SERVICE_ROLE_KEY=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 24)
DASHBOARD_PASSWORD=$(openssl rand -base64 16)

# Inject generated secrets into .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|" .env

echo "Pulling Docker images..."
docker compose pull

echo "Starting Supabase..."
docker compose up -d

# Save credentials to central secrets file
SECRETS_FILE="$HOME/dev/.secrets.env"
touch "$SECRETS_FILE" && chmod 600 "$SECRETS_FILE"
grep -v '^SUPABASE_' "$SECRETS_FILE" > "${SECRETS_FILE}.tmp" 2>/dev/null || true
mv "${SECRETS_FILE}.tmp" "$SECRETS_FILE"
cat >> "$SECRETS_FILE" << CREDS

# Supabase
SUPABASE_STUDIO_URL=http://localhost:3000
SUPABASE_API_URL=http://localhost:8000
SUPABASE_DB_URL=postgresql://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres
SUPABASE_DASHBOARD_USER=supabase
SUPABASE_DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SUPABASE_POSTGRES_PASSWORD=$POSTGRES_PASSWORD
SUPABASE_JWT_SECRET=$JWT_SECRET
SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
CREDS
echo "Credentials saved to $SECRETS_FILE"

echo ""
echo "Supabase is running!"
echo "  Studio:        http://localhost:3000"
echo "  API:           http://localhost:8000"
echo "  DB (Postgres): localhost:5432"
echo ""
echo "Credentials (save these):"
echo "  Dashboard password: $DASHBOARD_PASSWORD"
echo "  Postgres password:  $POSTGRES_PASSWORD"
echo "  JWT secret:         $JWT_SECRET"
echo "  Anon key:           $ANON_KEY"
echo "  Service role key:   $SERVICE_ROLE_KEY"
echo ""
echo "To stop: docker compose -f $SUPABASE_DIR/docker/docker-compose.yml down"
