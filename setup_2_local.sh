#!/bin/bash
# ==========================================
# PART 2 (CUSTOM CODE INJECTION): Flat-manager Setup
# Base: LATEST Version (Agar tidak error TimeDelta)
# Mod: Inject Custom src/lib.rs (Agar Config terbaca + Debug)
# ==========================================
set -e

# --- CONFIGURATION ---
REPO_DIR="/srv/flatpak-repo"
DB_NAME="flatpak_repo"
DB_USER="flatmanager"
PORT=8080

# Cek config
EXISTING_DB_PASS=$(grep -oP 'postgres://[^:]+:\K[^@]+' /etc/flat-manager/config.json)
if [ -f "/etc/flat-manager/config.json" ]; then
    DB_PASS=$EXISTING_DB_PASS
else
    DB_PASS=$(openssl rand -base64 12)
fi

GPG_KEY_ID="C7FC00963A8E95A5"
if [ -z "$GPG_KEY_ID" ]; then
    read -p "Masukan GPG Key ID: " GPG_KEY_ID
fi
if [ -z "$GPG_KEY_ID" ]; then echo "❌ GPG Key ID kosong."; exit 1; fi
if [ "$EUID" -ne 0 ]; then echo "❌ Run as SUDO!"; exit 1; fi

# --- 1. INSTALL DEPENDENCIES ---
echo ">>> [1/7] Installing Dependencies..."
apt update
apt install -y postgresql libpq-dev build-essential curl pkg-config git \
    ostree libostree-dev gir1.2-ostree-1.0 \
    python3-aiohttp python3-tenacity 

# Install Rust
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    source "$HOME/.cargo/env"
fi

# --- 2. DATABASE ---
echo ">>> [2/7] Setting up Database..."
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true

# --- 3. CLONE SOURCE ---
echo ">>> [3/7] Cloning Source Code (Latest)..."
rm -rf /tmp/fm-build
# git clone https://github.com/flatpak/flat-manager.git /tmp/fm-build
LOCAL_SOURCE_DIR="/home/zoanter/flat-manager"
rsync -a --exclude 'target' --exclude '.git' "$LOCAL_SOURCE_DIR/" /tmp/fm-build/
cd /tmp/fm-build

# --- 4. COMPILING ---
echo ">>> [4/7] Compiling (With Custom Code)..."
# Compile versi terbaru (yang sudah dipatch)
cargo install --path . --bin flat-manager --bin gentoken --root /usr/local --force

echo ">>> [5/7] Installing Client..."
cp flat-manager-client /usr/local/bin/flat-manager-client
chmod +x /usr/local/bin/flat-manager-client

cd /
rm -rf /tmp/fm-build

# --- 6. CONFIG FILE ---
echo ">>> [6/7] Creating Configuration..."
mkdir -p /etc/flat-manager
if [ ! -f "/etc/flat-manager/config.json" ]; then
cat <<EOF > /etc/flat-manager/config.json
{
  "host": "0.0.0.0",
  "port": $PORT,
  "gpg-homedir": "/root/.gnupg",
  "database-url": "postgres://$DB_USER:$DB_PASS@localhost/$DB_NAME",
  "repos": {
    "stable": {
      "path": "$REPO_DIR",
      "suggested-repo-name": "my-repo",
      "gpg-key": "$GPG_KEY_ID",
      "subsets": {}
    }
  },
  "secret": "QmNqM0F0WkE2a2N3RmZ3QnVhTnJYZWlURm5wK2c9"
}
EOF
fi
chown root:root /etc/flat-manager/config.json
chmod 644 /etc/flat-manager/config.json

# --- 7. SYSTEMD ---
echo ">>> [7/7] Configuring Systemd..."
# Kita tetap gunakan Env Var untuk keamanan ganda
cat <<EOF > /etc/systemd/system/flat-manager.service
[Unit]
Description=Flat-manager Server
After=network.target postgresql.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/flat-manager

# Dengan custom code Anda, variabel ini akan dibaca secara eksplisit
Environment="RUST_LOG=debug,error"
Environment="REPO_CONFIG=/etc/flat-manager/config.json"
Environment="HOME=/root"

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flat-manager
systemctl restart flat-manager

echo ">>> Generating Admin Token..."
sleep 5
ADMIN_TOKEN=$(/usr/local/bin/gentoken \
  --secret "QmNqM0F0WkE2a2N3RmZ3QnVhTnJYZWlURm5wK2c9" \
  --name "admin" \
  --repo "stable" \
  --scope "build" \
  --scope "publish" \
  --prefix "*")

echo ""
echo "========================================="
echo "✅ SETUP CUSTOM SELESAI"
echo "========================================="
echo "Server URL : http://$(hostname -I | cut -d' ' -f1):$PORT"
echo "Admin Token: $ADMIN_TOKEN"
echo "========================================="