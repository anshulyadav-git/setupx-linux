#!/bin/bash
# [06] webserver

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[06/10] webserver"

echo "Updating package lists..."
sudo apt-get update

# --- Nginx ---
echo "Installing Nginx..."
sudo apt-get install -y nginx

echo "Starting and enabling Nginx..."
sudo systemctl start nginx
sudo systemctl enable nginx

echo "Allowing Nginx through UFW..."
sudo ufw allow 'Nginx Full' comment 'Nginx HTTP+HTTPS'

# --- BIND9 ---
echo "Installing BIND9 DNS server..."
sudo apt-get install -y bind9 bind9utils bind9-doc dnsutils

echo "Starting and enabling BIND9..."
sudo systemctl start named
sudo systemctl enable named

echo "Allowing DNS through UFW..."
sudo ufw allow 53/tcp comment 'DNS TCP'
sudo ufw allow 53/udp comment 'DNS UDP'

# --- Verify ---
echo ""
echo "Nginx status:"
sudo systemctl is-active nginx

echo "BIND9 status:"
sudo systemctl is-active named

echo ""
echo "Installation complete!"
echo "  Nginx:  http://$(hostname -I | awk '{print $1}')"
echo "  BIND9:  DNS listening on port 53"
echo ""
echo "Nginx config:  /etc/nginx/nginx.conf"
echo "BIND9 config:  /etc/bind/named.conf"
echo "BIND9 zones:   /etc/bind/named.conf.local"
