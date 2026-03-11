#!/bin/bash
# [07] postgre

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[07/10] postgre"

echo "Installing dependencies..."
sudo apt-get install -y curl ca-certificates

echo "Adding PostgreSQL official apt repository..."
sudo install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | sudo gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null

echo "Installing latest PostgreSQL..."
sudo apt-get update
sudo apt-get install -y postgresql

PG_VERSION=$(psql --version | grep -oP '\d+' | head -1)
echo "Installed PostgreSQL $PG_VERSION"

echo "Starting and enabling PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

echo "Configuring PostgreSQL to listen on all interfaces..."
PG_CONF=$(sudo -u postgres psql -t -c "SHOW config_file;" | tr -d ' ')
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

PG_HBA=$(sudo -u postgres psql -t -c "SHOW hba_file;" | tr -d ' ')
echo "host  all  all  0.0.0.0/0  scram-sha-256" | sudo tee -a "$PG_HBA" > /dev/null

echo "Setting postgres user password..."
PG_PASSWORD=$(openssl rand -base64 24)
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$PG_PASSWORD';"

echo "Reloading PostgreSQL..."
sudo systemctl reload postgresql

# Save credentials to central secrets file
SECRETS_FILE="$HOME/dev/.secrets.env"
touch "$SECRETS_FILE" && chmod 600 "$SECRETS_FILE"
grep -v '^POSTGRES_' "$SECRETS_FILE" > "${SECRETS_FILE}.tmp" 2>/dev/null || true
mv "${SECRETS_FILE}.tmp" "$SECRETS_FILE"
cat >> "$SECRETS_FILE" << CREDS

# PostgreSQL
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$PG_PASSWORD
POSTGRES_URL=postgresql://postgres:$PG_PASSWORD@localhost:5432/postgres
CREDS
echo "Credentials saved to $SECRETS_FILE"

echo ""
echo "PostgreSQL is running!"
echo "  Host:     localhost"
echo "  Port:     5432"
echo "  User:     postgres"
echo "  Password: $PG_PASSWORD"
echo ""
echo "Connect: psql -h localhost -U postgres"
