#!/bin/bash
# [02] install_tools

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[02/10] install_tools"

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "Installing Git..."
sudo apt install -y git

echo "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh -y

echo "Installing Python latest..."
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install python3.12 python3.12-venv python3.12-pip -y

echo "Installation complete!"