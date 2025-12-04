#!/bin/bash
# ==========================================
# PART 2: Flat-manager Service Setup
# ==========================================
set -e

# --- CONFIGURATION ---
# PASTE YOUR KEY ID FROM PART 1 BELOW!
GPG_KEY_ID="REPLACE_WITH_YOUR_KEY_ID" 

REPO_DIR="/srv/flatpak-repo"
DB_NAME="flatpak_repo"
DB_USER="flatmanager"
DB_PASS=$(openssl rand -base64 12)
SECRET_KEY=$(openssl rand -base64 24)
PORT=8080

if [ "$EUID" -ne 0 ]; then echo "Run as root (sudo)"; exit; fi

if [ "$GPG_KEY_ID" == "REPLACE_WITH_YOUR_KEY_ID" ]; then
    echo "ERROR: You must edit this script and paste your GPG_KEY_ID from Part 1."
    exit 1
fi

echo ">>> [1/5] Installing Dependencies (Postgres & Rust)..."
apt install -y postgresql libpq-dev build-essential curl pkg-config
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

echo ">>> [2/5] Setting up Database..."
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" || true

echo ">>> [3/5] Compiling Flat-manager (Takes time)..."
# Installing to /usr/local/bin for global access
source "$HOME/.cargo/env"
cargo install --git https://github.com/flatpak/flat-manager --root /usr/local

echo ">>> [4/5] Creating Configuration..."
mkdir -p /etc/flat-manager
cat <<EOF > /etc/flat-manager/config.json
{
  "host": "0.0.0.0",
  "port": $PORT,
  "database-url": "postgres://$DB_USER:$DB_PASS@localhost/$DB_NAME",
  "repos": {
    "stable": {
      "path": "$REPO_DIR",
      "suggest-remote-name": "my-repo",
      "gpg-key": "$GPG_KEY_ID",
      "gpg-homedir": "$HOME/.gnupg"
    }
  },
  "secret": "$SECRET_KEY"
}
EOF

echo ">>> [5/5] Creating Systemd Service..."
cat <<EOF > /etc/systemd/system/flat-manager.service
[Unit]
Description=Flat-manager Server
After=network.target postgresql.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/flat-manager -c /etc/flat-manager/config.json
Restart=on-failure
Environment="HOME=$HOME"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flat-manager
systemctl restart flat-manager

# Wait for startup
sleep 5
ADMIN_TOKEN=$(/usr/local/bin/flat-manager-client gentoken --secret "$SECRET_KEY" --name "admin_manual" --scope "stable" http://127.0.0.1:$PORT)

echo ""
echo "=== PART 2 COMPLETE ==="
echo "Server is running at: http://$(hostname -I | cut -d' ' -f1):$PORT"
echo "Your Admin Token: $ADMIN_TOKEN"