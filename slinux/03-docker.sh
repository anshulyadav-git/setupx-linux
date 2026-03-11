#!/bin/bash
# [03] docker

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[03/10] docker"

echo "Updating system..."
sudo apt update

echo "Installing prerequisites..."
sudo apt install -y ca-certificates curl gnupg lsb-release

echo "Adding Docker's official GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "Setting up Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Installing Docker Engine..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

echo "Adding user to docker group (requires logout/login to take effect)..."
sudo usermod -aG docker $USER

echo "Docker installation complete!"
echo "Note: You may need to log out and log back in for the docker group changes to take effect."