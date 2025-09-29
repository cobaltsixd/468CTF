#!/usr/bin/env bash
# setup.sh — run as root to create all CTF services, flags, challenges, and CLI
# Works on Kali/Debian/Ubuntu. Binds everything to 127.0.0.1.
set -euo pipefail

# --- safety: root check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CTF_BASE="/opt/ctf"

echo "[*] Preparing directories at $CTF_BASE"
mkdir -p "$CTF_BASE"
chown root:root "$CTF_BASE"
chmod 755 "$CTF_BASE"

# --- deps ---
echo "[*] Installing apt dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  git curl rsync zip sqlite3 gcc \
  python3 python3-pip python3-flask

# --- ctf user ---
if ! id -u ctf >/dev/null 2>&1; then
  echo "[*] Creating user 'ctf'"
  useradd -m -s /bin/bash ctf
fi

# --- copy repo into /opt/ctf/src ---
echo "[*] Copying repo content into $CTF_BASE/src"
mkdir -p "$CTF_BASE/src"
rsync -a --delete "$REPO_ROOT"/ "$CTF_BASE/src/"

# --- standard layout ---
echo "[*] Creating standard layout"
mkdir -p "$CTF_BASE/flags" "$CTF_BASE/scoreboard" "$CTF_BASE/challenges" "$CTF_BASE/state" "$CTF_BASE/tools"
chown -R ctf:ctf "$CTF_BASE"

# --- copy scoreboard + challenges + tools from src ---
echo "[*] Installing scoreboard, challenges, tools"
cp -a "$CTF_BASE/src/scoreboard/"* "$CTF_BASE/scoreboard/" 2>/dev/null || true
cp -a "$CTF_BASE/src/challenges/"* "$CTF_BASE/challenges/" 2>/dev/null || true
cp -a "$CTF_BASE/src/tools/"* "$CTF_BASE/tools/" 2>/dev/null || true
chown -R ctf:ctf "$CTF_BASE/scoreboard" "$CTF_BASE/challenges" "$CTF_BASE/tools"

# --- writable group for state + forensics artifacts ---
echo "[*] Setting writable group for state and forensics artifacts"
groupadd -f ctfrw
usermod -aG ctfrw ctf || true
usermod -aG ctfrw vagrant || true
# ensure dirs exist
mkdir -p "$CTF_BASE/state" "$CTF_BASE/challenges/02_forensics_stego/artifacts"
# grant group write + setgid so new files inherit group
chgrp -R ctfrw "$CTF_BASE/state" "$CTF_BASE/challenges/02_forensics_stego"
find "$CTF_BASE/state" "$CTF_BASE/challenges/02_forensics_stego" -type d -exec chmod 2775 {} \;
find "$CTF_BASE/state" "$CTF_BASE/challenges/02_forensics_stego" -type f -exec chmod 664 {} \; 2>/dev/null || true

# --- seed flags (unique per VM) ---
STUDENT_ID="${CTF_STUDENT:-${SUDO_USER:-$(logname 2>/dev/null || echo student)}}"
SALT="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c8 || echo RANDOM99)"
echo "[*] Seeding flags for $STUDENT_ID (salt $SALT)"
echo "WVUCTF{web_${STUDENT_ID}_${SALT}}"       > "$CTF_BASE/flags/flag_web.txt"
echo "WVUCTF{forensics_${STUDENT_ID}_${SALT}}" > "$CTF_BASE/flags/flag_forensics.txt"
echo "WVUCTF{re_${STUDENT_ID}_${SALT}}"        > "$CTF_BASE/flags/flag_re.txt"
echo "WVUCTF{crypto_${STUDENT_ID}_${SALT}}"    > "$CTF_BASE/flags/flag_crypto.txt"
echo "WVUCTF{privesc_${STUDENT_ID}_${SALT}}"   > "$CTF_BASE/flags/flag_privesc.txt"
chown root:ctfrw "$CTF_BASE/flags/"flag_*.txt
chmod 640 "$CTF_BASE/flags/"flag_*.txt

# --- scoreboard DB init ---
if [ ! -f "$CTF_BASE/scoreboard/scores.db" ]; then
  echo "[*] Initializing scoreboard DB"
  sqlite3 "$CTF_BASE/scoreboard/scores.db" < "$CTF_BASE/scoreboard/schema.sql"
  chown ctf:ctf "$CTF_BASE/scoreboard/scores.db"
fi

# --- systemd: scoreboard service ---
echo "[*] Installing systemd services"
cat > /etc/systemd/system/468ctf-scoreboard.service <<'SERVICE'
[Unit]
Description=468CTF Local Scoreboard
After=network.target

[Service]
WorkingDirectory=/opt/ctf/scoreboard
ExecStart=/usr/bin/python3 /opt/ctf/scoreboard/app.py
Restart=on-failure
User=ctf

[Install]
WantedBy=multi-user.target
SERVICE

# --- systemd: vulnerable web app service (starts when Door 1 is begun) ---
cat > /etc/systemd/system/468ctf-vulnapp.service <<'SERVICE'
[Unit]
Description=468CTF Vulnerable Web App (Door 1)
After=468ctf-scoreboard.service

[Service]
WorkingDirectory=/opt/ctf/challenges/01_web_sqlite_sqli
ExecStart=/usr/bin/python3 /opt/ctf/challenges/01_web_sqlite_sqli/app_vuln.py
Restart=on-failure
User=ctf

[Install]
WantedBy=multi-user.target
SERVICE

chown root:root /etc/systemd/system/468ctf-*.service
chmod 644 /etc/systemd/system/468ctf-*.service

# --- prepare web app DB (Door 1) ---
echo "[*] Preparing WEB challenge DB"
python3 "$CTF_BASE/challenges/01_web_sqlite_sqli/init_db.py" || true
chown -R ctf:ctf "$CTF_BASE/challenges/01_web_sqlite_sqli"

# --- build Reverse Engineering gate (Door 3) ---
echo "[*] Building RE gate binary"
bash "$CTF_BASE/challenges/03_reverse_engineering/build.sh" || true

# --- generate Crypto cipher (Door 4) ---
echo "[*] Generating Crypto XOR cipher"
mkdir -p "$CTF_BASE/challenges/04_crypto_xor"
KEY="$(tr -dc 'A-Za-z0-9@!#%&' < /dev/urandom | head -c12 || echo 'MORG@ntown!')"
echo "$KEY" > "$CTF_BASE/challenges/04_crypto_xor/key.txt"
python3 "$CTF_BASE/challenges/04_crypto_xor/make_cipher.py" || true
chown -R ctf:ctf "$CTF_BASE/challenges/04_crypto_xor"

# --- seed Priv-Esc helper (Door 5) ---
echo "[*] Seeding Priv-Esc helper"
bash "$CTF_BASE/challenges/05_priv_esc_path_hijack/seed_notes.sh" || true

# --- Forensics artifacts (Door 2): build once as 'ctf' and set perms ---
echo "[*] Preparing FORENSICS artifacts"
chmod +x "$CTF_BASE/challenges/02_forensics_stego/make_artifact.sh" 2>/dev/null || true
sudo -u ctf bash "$CTF_BASE/challenges/02_forensics_stego/make_artifact.sh" || true
chown -R ctf:ctfrw "$CTF_BASE/challenges/02_forensics_stego"

# --- Cruise Ship event: fixed door codes from repo + 'ctf' CLI install ---
echo "[*] Installing Cruise Ship door codes + CLI"
META_DIR="$CTF_BASE/challenges"
META_ENV="$META_DIR/meta.env"
DOOR_CODES="$CTF_BASE/door-codes.txt"

mkdir -p "$META_DIR"
if [ ! -f "$META_ENV" ]; then
  if [ -f "$CTF_BASE/src/challenges/meta.env" ]; then
    cp "$CTF_BASE/src/challenges/meta.env" "$META_ENV"
  else
    # fallback defaults if repo file missing
    cat > "$META_ENV" <<'EOF'
WEB_CODE="MickeyRocks468"
FORENSICS_CODE="PumpkinDrop25"
RE_CODE="DOOR CODE"
CRYPTO_CODE="OpenSesame"
PRIVESC_CODE="I WANT TO WIN"
EOF
  fi
fi
chown ctf:ctf "$META_ENV"
chmod 644 "$META_ENV"

# Build instructor cheat-sheet from meta.env
# shellcheck disable=SC1090
. "$META_ENV"
cat > "$DOOR_CODES" <<EOF
Cruise Ship CTF — Door Codes
Door 1 (WEB)        : $WEB_CODE
Door 2 (FORENSICS)  : $FORENSICS_CODE
Door 3 (RE)         : $RE_CODE
Door 4 (CRYPTO)     : $CRYPTO_CODE
Door 5 (PRIVESC)    : $PRIVESC_CODE
EOF
chmod 640 "$DOOR_CODES"

# Install the 'ctf' CLI (case/space tolerant code check)
install -m 0755 /dev/stdin /usr/local/bin/ctf <<'CTFEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 0002   # ensure files we create are group-writable

META_ENV="/opt/ctf/challenges/meta.env"
STATE_DIR="/opt/ctf/state"
[ -f "$META_ENV" ] || { echo "Missing $META_ENV. Re-run setup."; exit 1; }
# shellcheck disable=SC1090
source "$META_ENV"

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
ok(){ printf "[✓] %s\n" "$*"; }
err(){ printf "[✗] %s\n" "$*" >&2; }
normalize(){ tr '[:upper:]' '[:lower:]' | tr -d ' '; }  # lower + strip spaces

usage(){
  cat <<USAGE
ctf — WVU Midterm CTF helper

Commands:
  ctf menu          Interactive picker (enter codename from the Minecraft door)
  ctf start <door>  Start door 1..5 or name (web|forensics|re|crypto|privesc)
  ctf status        Show started doors on this VM
  ctf codes         Print this VM's codenames (for instructor)
USAGE
}

door_name(){
  case "${1,,}" in
    1|web) echo "WEB";;
    2|forensics) echo "FORENSICS";;
    3|re|rev|reverse) echo "RE";;
    4|crypto) echo "CRYPTO";;
    5|privesc|priv|pe) echo "PRIVESC";;
    *) echo ""; return 1;;
  esac
}

verify_codename(){
  local door="$1" entered="$2" needed
  case "$door" in
    WEB)       needed="$WEB_CODE";;
    FORENSICS) needed="$FORENSICS_CODE";;
    RE)        needed="$RE_CODE";;
    CRYPTO)    needed="$CRYPTO_CODE";;
    PRIVESC)   needed="$PRIVESC_CODE";;
    *) return 1;;
  esac
  [[ "$(printf '%s' "$entered" | normalize)" == "$(printf '%s' "$needed" | normalize)" ]]
}

STATE_DIR="/opt/ctf/state"
USER_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ctf"
# ...
stamp_started(){
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if : > "$STATE_DIR/started_$1" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$USER_STATE" 2>/dev/null || true
  : > "$USER_STATE/started_$1"
}
is_started(){
  [[ -f "$STATE_DIR/started_$1" || -f "$USER_STATE/started_$1" ]]
}


start_door(){
  local door="$1"
  case "$door" in
    WEB)
      # Start the Door 1 service without prompting (sudoers grants this)
      sudo -n /bin/systemctl start 468ctf-vulnapp.service >/dev/null 2>&1 || true
      bold "Door 1 (WEB) — SQLi"
      echo "Open:  http://127.0.0.1:5001"
      echo "Score: http://127.0.0.1:1337"
      ;;
    FORENSICS)
      bold "Door 2 (FORENSICS) — PNG/ZIP polyglot"
      echo "Artifact: /opt/ctf/challenges/02_forensics_stego/artifacts/cover.png"
      ;;
    RE)
      bold "Door 3 (RE) — Tiny ELF gate"
      echo "Run: /opt/ctf/challenges/03_reverse_engineering/gate"
      ;;
    CRYPTO)
      bold "Door 4 (CRYPTO) — XOR + Base64"
      echo "Cipher: /opt/ctf/challenges/04_crypto_xor/cipher.txt"
      ;;
    PRIVESC)
      bold "Door 5 (PRIVESC) — PATH hijack"
      echo "SUID: /usr/local/bin/ctf-notes"
      ;;
  esac
  stamp_started "$door"
  ok "Started $door on this VM."
}

cmd_menu(){
  bold "Select a challenge (Door 1–5)"
  echo "1) WEB        — SQL injection"
  echo "2) FORENSICS  — PNG/ZIP polyglot"
  echo "3) RE         — reverse engineering"
  echo "4) CRYPTO     — XOR + Base64"
  echo "5) PRIVESC    — PATH hijack"
  read -rp "Enter door number: " pick
  local door; door=$(door_name "$pick") || { err "Invalid door."; exit 2; }
  read -rp "Enter codename printed on the Minecraft door: " code
  if verify_codename "$door" "$code"; then ok "Codename accepted."; start_door "$door"; else err "Incorrect codename."; exit 3; fi
}

cmd_start(){
  local pick="${1:-}"; [ -n "$pick" ] || { err "Usage: ctf start <door>"; exit 1; }
  local door; door=$(door_name "$pick") || { err "Unknown door '$pick'."; exit 2; }
  read -rp "Enter codename for $door: " code
  if verify_codename "$door" "$code"; then ok "Codename accepted."; start_door "$door"; else err "Incorrect codename."; exit 3; fi
}

cmd_status(){
  bold "Door start status (this VM):"
  for d in WEB FORENSICS RE CRYPTO PRIVESC; do
    if is_started "$d"; then echo "  $d: started"; else echo "  $d: not started"; fi
  done
}

cmd_codes(){
  echo "Door 1 (WEB)        : $WEB_CODE"
  echo "Door 2 (FORENSICS)  : $FORENSICS_CODE"
  echo "Door 3 (RE)         : $RE_CODE"
  echo "Door 4 (CRYPTO)     : $CRYPTO_CODE"
  echo "Door 5 (PRIVESC)    : $PRIVESC_CODE"
}

main(){
  case "${1:-help}" in
    menu)    cmd_menu;;
    start)   shift || true; cmd_start "${1:-}";;
    status)  cmd_status;;
    codes)   cmd_codes;;
    help|-h|--help) usage;;
    *) usage; exit 1;;
  esac
}
main "$@"
CTFEOF
chmod 755 /usr/local/bin/ctf

# --- allow non-root start/stop of Door 1 service (sudoers + group) ---
echo "[*] Configuring sudoers so vagrant/ctf can control vulnapp"
groupadd -f ctfweb
usermod -aG ctfweb ctf || true
usermod -aG ctfweb vagrant || true
install -m 0440 /dev/stdin /etc/sudoers.d/468ctf-web <<'EOF'
Cmnd_Alias CTFWEB = /bin/systemctl start 468ctf-vulnapp.service, /bin/systemctl stop 468ctf-vulnapp.service, /bin/systemctl restart 468ctf-vulnapp.service, /bin/systemctl status 468ctf-vulnapp.service
%ctfweb ALL=(root) NOPASSWD: CTFWEB
EOF
visudo -cf /etc/sudoers.d/468ctf-web >/dev/null

# --- enable scoreboard service now ---
echo "[*] Enabling scoreboard service"
systemctl daemon-reload
systemctl enable --now 468ctf-scoreboard.service || true

echo
echo "✅ Setup finished."
echo "Scoreboard:   http://127.0.0.1:1337"
echo "Door codes:   $CTF_BASE/door-codes.txt  (or: sudo ctf codes)"
echo "Door 1 app:   http://127.0.0.1:5001  (starts after 'ctf menu' → WEB)"
