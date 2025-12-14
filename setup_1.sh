#!/bin/bash
# ==========================================
# PART 1: OSTree Repository & GPG Setup
# ==========================================
set -e

REPO_DIR="/srv/flatpak-repo"
GPG_NAME="PENS AGL Store Research"
GPG_EMAIL="m3g3nz2@gmail.com"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root (sudo)"
  exit 1
fi

echo ">>> [1/4] Installing OSTree + GPG..."
apt update
apt install -y ostree libostree-dev gnupg

echo ">>> [2/4] Generating GPG key (if needed)..."
if ! gpg --list-keys "$GPG_EMAIL" &>/dev/null; then
cat > /tmp/gpg_batch <<EOF
%echo Generating OpenPGP key
Key-Type: RSA
Key-Length: 4096
Name-Real: $GPG_NAME
Name-Email: $GPG_EMAIL
Expire-Date: 0
%no-protection
%commit
EOF
  gpg --batch --generate-key /tmp/gpg_batch
  rm -f /tmp/gpg_batch
else
  echo "   GPG key already exists."
fi

GPG_KEY_ID=$(gpg --list-keys --keyid-format LONG "$GPG_EMAIL" \
  | awk '/^pub/{print $2}' | cut -d'/' -f2 | head -n1)

echo "   GPG Key ID: $GPG_KEY_ID"

echo ">>> [3/4] Initializing OSTree repo..."
mkdir -p "$REPO_DIR"
if [ ! -d "$REPO_DIR/objects" ]; then
  ostree init --repo="$REPO_DIR" --mode=archive-z2
fi

mkdir -p "$REPO_DIR/build-repo"

# Permissions (safe default)
chown -R root:root "$REPO_DIR"
chmod -R 775 "$REPO_DIR"

echo ">>> [4/4] Exporting public GPG key..."
gpg --export --armor "$GPG_KEY_ID" > "$REPO_DIR/public.gpg"

echo ""
echo "✅ PART 1 COMPLETE"
echo "Repo        : $REPO_DIR"
echo "Build repo  : $REPO_DIR/build-repo"
echo "GPG Key ID  : $GPG_KEY_ID"
