#!/bin/bash
# ==========================================
# PART 1: OSTree Repository & GPG Setup
# ==========================================
set -e

# --- CONFIGURATION ---
REPO_DIR="/srv/flatpak-repo"
GPG_NAME="My Flatpak Repo"
GPG_EMAIL="admin@localhost"

if [ "$EUID" -ne 0 ]; then echo "Run as root (sudo)"; exit; fi

echo ">>> [1/4] Installing OSTree dependencies..."
apt update && apt install -y ostree libostree-dev gnupg

echo ">>> [2/4] Generating GPG Key..."
# Only generate if it doesn't exist
if ! gpg --list-keys "$GPG_EMAIL" &> /dev/null; then
    cat >gpg_gen_batch <<EOF
     %echo Generating OpenPGP key
     Key-Type: RSA
     Key-Length: 4096
     Name-Real: $GPG_NAME
     Name-Email: $GPG_EMAIL
     Expire-Date: 0
     %no-protection
     %commit
EOF
    gpg --batch --generate-key gpg_gen_batch
    rm gpg_gen_batch
else
    echo "   Key already exists."
fi

# Capture Key ID for later use
GPG_KEY_ID=$(gpg --list-keys --keyid-format LONG "$GPG_EMAIL" | grep "pub" | awk '{print $2}' | cut -d'/' -f2 | head -n 1)
echo "   Key ID: $GPG_KEY_ID"

echo ">>> [3/4] Initializing OSTree Repository..."
mkdir -p "$REPO_DIR"
if [ ! -d "$REPO_DIR/objects" ]; then
    ostree init --mode=archive-z2 --repo="$REPO_DIR"
    echo "   Repo initialized at $REPO_DIR"
else
    echo "   Repo already exists at $REPO_DIR"
fi

# Set permissions so the future flat-manager user can write to it
chown -R root:root "$REPO_DIR"
chmod -R 755 "$REPO_DIR"

echo ">>> [4/4] Exporting Public Key..."
gpg --export --armor "$GPG_KEY_ID" > "$REPO_DIR/public.gpg"

echo ""
echo "=== PART 1 COMPLETE ==="
echo "Repo Path: $REPO_DIR"
echo "GPG Key ID: $GPG_KEY_ID"
echo "(Save this Key ID, you will need it for Part 2!)"