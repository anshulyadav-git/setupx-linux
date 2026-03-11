#!/bin/bash
# [05] ufw-ports

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[05/10] ufw-ports"

echo "Resetting UFW to defaults..."
sudo ufw --force reset

echo "Setting default policies..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# --- Core ---
echo "Allowing SSH (22)..."
sudo ufw allow 22/tcp comment 'SSH'

echo "Allowing HTTP/HTTPS..."
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# --- Supabase ---
echo "Allowing Supabase ports..."
sudo ufw allow 3000/tcp comment 'Supabase Studio'
sudo ufw allow 8000/tcp comment 'Supabase API (Kong)'
sudo ufw allow 8443/tcp comment 'Supabase API HTTPS (Kong)'
sudo ufw allow 5432/tcp comment 'Supabase Postgres / Pooler'
sudo ufw allow 6543/tcp comment 'Supabase PgBouncer'

# --- Coolify ---
echo "Allowing Coolify ports..."
sudo ufw allow 6001/tcp comment 'Coolify Realtime (Soketi)'
sudo ufw allow 6002/tcp comment 'Coolify Realtime SSL (Soketi)'

# --- PostgreSQL (standalone) ---
echo "Allowing standalone PostgreSQL (5432)..."
# Already covered above by Supabase rule, but explicitly noted here

# --- Mail server ---
echo "Allowing mail ports..."
sudo ufw allow 25/tcp  comment 'SMTP'
sudo ufw allow 465/tcp comment 'SMTPS'
sudo ufw allow 587/tcp comment 'SMTP Submission'
sudo ufw allow 110/tcp comment 'POP3'
sudo ufw allow 995/tcp comment 'POP3S'
sudo ufw allow 143/tcp comment 'IMAP'
sudo ufw allow 993/tcp comment 'IMAPS'

# --- ngrok (outbound only, no inbound needed) ---
# ngrok creates outbound tunnels, no UFW rule required

echo "Enabling UFW..."
sudo ufw --force enable

echo ""
echo "UFW status:"
sudo ufw status verbose
