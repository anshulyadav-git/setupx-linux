#!/bin/bash
# [09] coolify

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[09/10] coolify"

echo "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
  echo "Docker is required. Run docker.sh first."
  exit 1
fi

echo "Installing Coolify..."
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash

echo ""
echo "Coolify is running!"
echo "  Dashboard: http://$(hostname -I | awk '{print $1}'):8000"
echo "  Or:        http://localhost:8000"
echo ""
echo "Open the dashboard to complete setup and create your admin account."
