#!/usr/bin/env bash
# install.sh — convenience installer (students)
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/cobaltsixd/468CTF.git}"
BRANCH="${BRANCH:-main}"
DEST="/opt/468ctf-src"

echo "[*] Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git python3 python3-pip sqlite3 gcc zip curl

echo "[*] Cloning repo..."
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch --all -p
  git -C "$DEST" checkout "$BRANCH"
  git -C "$DEST" pull --ff-only
else
  rm -rf "$DEST"
  git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

echo "[*] Running setup.sh..."
bash "$DEST/setup.sh"

echo ""
echo "✅ Install complete."
echo "Scoreboard:   http://127.0.0.1:1337"
echo "Web challenge: http://127.0.0.1:5001"
echo "Tip: export CTF_STUDENT='your-wvu-id' before install to stamp your flags."
