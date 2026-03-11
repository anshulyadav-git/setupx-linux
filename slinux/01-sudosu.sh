#!/bin/bash
# [01] sudosu

set -euo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO. Exit code: $?" >&2' ERR

echo "[01/10] sudosu"
echo "Switching to root user..."
sudo su