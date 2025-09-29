#!/usr/bin/env bash
# setup.sh — run as root to create all CTF services and artifacts
set -euo pipefail

# must run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)."; exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CTF_BASE="/opt/ctf"
mkdir -p "$CTF_BASE"
chown root:root "$CTF_BASE"
chmod 755 "$CTF_BASE"

echo "[*] Installing apt deps..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip sqlite3 gcc zip curl git

# create ctf user
id -u ctf &>/dev/null || useradd -m -s /bin/bash ctf

echo "[*] Copying repo content into $CTF_BASE..."
rsync -a --delete "$REPO_ROOT/" "$CTF_BASE/src/"

# Create standard layout
mkdir -p "$CTF_BASE/flags" "$CTF_BASE/scoreboard" "$CTF_BASE/challenges" "$CTF_BASE/state"
chown -R ctf:ctf "$CTF_BASE"

# copy scoreboard files
cp -a "$CTF_BASE/src/scoreboard/"* "$CTF_BASE/scoreboard/"
chown -R ctf:ctf "$CTF_BASE/scoreboard"

# copy challenges directory
cp -a "$CTF_BASE/src/challenges/"* "$CTF_BASE/challenges/"
chown -R ctf:ctf "$CTF_BASE/challenges"

# copy tools
mkdir -p "$CTF_BASE/tools"
cp -a "$CTF_BASE/src/tools/"* "$CTF_BASE/tools/"
chown -R ctf:ctf "$CTF_BASE/tools"

# seed flags (unique per-VM). Students can set CTF_STUDENT env before running installer.
STUDENT_ID="${CTF_STUDENT:-$(logname 2>/dev/null || echo student)}"
SALT=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c8 || echo "RANDOM99")
echo "[*] Seeding flags for $STUDENT_ID (salt $SALT)"
echo "WVUCTF{web_${STUDENT_ID}_${SALT}}" > "$CTF_BASE/flags/flag_web.txt"
echo "WVUCTF{forensics_${STUDENT_ID}_${SALT}}" > "$CTF_BASE/flags/flag_forensics.txt"
echo "WVUCTF{re_${STUDENT_ID}_${SALT}}" > "$CTF_BASE/flags/flag_re.txt"
echo "WVUCTF{crypto_${STUDENT_ID}_${SALT}}" > "$CTF_BASE/flags/flag_crypto.txt"
echo "WVUCTF{privesc_${STUDENT_ID}_${SALT}}" > "$CTF_BASE/flags/flag_privesc.txt"
chmod 640 "$CTF_BASE/flags/"*

# init scoreboard DB file
if [ ! -f "$CTF_BASE/scoreboard/scores.db" ]; then
  sqlite3 "$CTF_BASE/scoreboard/scores.db" < "$CTF_BASE/scoreboard/schema.sql"
  chown ctf:ctf "$CTF_BASE/scoreboard/scores.db"
fi

# install scoreboard as systemd service
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

# web vuln app as service (will be enabled only when started from ctf CLI)
cat > /etc/systemd/system/468ctf-vulnapp.service <<'SERVICE'
[Unit]
Description=468CTF Vulnerable Web App
After=468ctf-scoreboard.service

[Service]
WorkingDirectory=/opt/ctf/challenges/01_web_sqlite_sqli
ExecStart=/usr/bin/python3 /opt/ctf/challenges/01_web_sqlite_sqli/app_vuln.py
Restart=on-failure
User=ctf

[Install]
WantedBy=multi-user.target
SERVICE

# permissions
chown root:root /etc/systemd/system/468ctf-scoreboard.service /etc/systemd/system/468ctf-vulnapp.service
chmod 644 /etc/systemd/system/468ctf-scoreboard.service /etc/systemd/system/468ctf-vulnapp.service

# prepare webapp DB
python3 "$CTF_BASE/challenges/01_web_sqlite_sqli/init_db.py" || true
chown -R ctf:ctf "$CTF_BASE/challenges/01_web_sqlite_sqli"

# build RE gate binary
bash "$CTF_BASE/challenges/03_reverse_engineering/build.sh" || true

# generate crypto key and cipher
mkdir -p "$CTF_BASE/challenges/04_crypto_xor"
KEY=$(tr -dc 'A-Za-z0-9@!#%&' < /dev/urandom | head -c12 || echo 'MORG@ntown!')
echo "$KEY" > "$CTF_BASE/challenges/04_crypto_xor/key.txt"
python3 "$CTF_BASE/challenges/04_crypto_xor/make_cipher.py"

# seed SUID notes helper
bash "$CTF_BASE/challenges/05_priv_esc_path_hijack/seed_notes.sh" || true

# create per-VM codenames and install ctf CLI
wordlist=(Anvil Raven Forge Lantern Obsidian Ember Granite Cipher Aegis Nova Titan Marble Quartz Shadow Falcon Iron Torch Atlas Comet Helix Summit Vortex Echo Glyph Sable Prism Relic Aspen Nightfall)
mkcode() { echo "${wordlist[$((RANDOM%${#wordlist[@]}))]}${wordlist[$((RANDOM%${#wordlist[@]}))]}$((RANDOM%90+10))"; }

META_DIR="$CTF_BASE/challenges"
META_ENV="$META_DIR/meta.env"
DOOR_CODES="$CTF_BASE/door-codes.txt"

if [ ! -f "$META_ENV" ]; then
  WEB_CODE=$(mkcode)
  FORENSICS_CODE=$(mkcode)
  RE_CODE=$(mkcode)
  CRYPTO_CODE=$(mkcode)
  PRIVESC_CODE=$(mkcode)

  cat > "$META_ENV" <<EOF
# Auto-generated per-VM codenames for door verification
WEB_CODE="$WEB_CODE"
FORENSICS_CODE="$FORENSICS_CODE"
RE_CODE="$RE_CODE"
CRYPTO_CODE="$CRYPTO_CODE"
PRIVESC_CODE="$PRIVESC_CODE"
EOF

  cat > "$DOOR_CODES" <<EOF
# Door codenames for map placement (instructor reads this to label doors)
Door 1 (WEB)         codename: $WEB_CODE
Door 2 (FORENSICS)   codename: $FORENSICS_CODE
Door 3 (RE)          codename: $RE_CODE
Door 4 (CRYPTO)      codename: $CRYPTO_CODE
Door 5 (PRIVESC)     codename: $PRIVESC_CODE
EOF
  chmod 640 "$DOOR_CODES"
fi

# install 'ctf' CLI
install -m 0755 /dev/stdin /usr/local/bin/ctf <<'CTFEOF'
#!/usr/bin/env bash
set -euo pipefail

META_ENV="/opt/ctf/challenges/meta.env"
STATE_DIR="/opt/ctf/state"
[ -f "$META_ENV" ] || { echo "Missing $META_ENV. Re-run setup."; exit 1; }
# shellcheck disable=SC1090
source "$META_ENV"

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ printf "[*] %s\n" "$*"; }
ok(){ printf "[✓] %s\n" "$*"; }
err(){ printf "[✗] %s\n" "$*" >&2; }

usage(){
  cat <<USAGE
ctf — WVU Midterm CTF helper

Commands:
  ctf menu          Interactive picker (requires codename from the Minecraft door)
  ctf start <door>  Start door by number (1..5) or name (web|forensics|re|crypto|privesc)
  ctf status        Show which doors have been started on this VM
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
  local door="$1" entered="$2" var
  case "$door" in
    WEB) var="$WEB_CODE";;
    FORENSICS) var="$FORENSICS_CODE";;
    RE) var="$RE_CODE";;
    CRYPTO) var="$CRYPTO_CODE";;
    PRIVESC) var="$PRIVESC_CODE";;
    *) return 1;;
  esac
  [[ "${entered,,}" == "${var,,}" ]]
}

stamp_started(){
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/started_$1"
}

is_started(){
  [[ -f "$STATE_DIR/started_$1" ]]
}

start_door(){
  local door="$1"
  case "$door" in
    WEB)
      systemctl enable --now 468ctf-vulnapp.service >/dev/null 2>&1 || true
      bold "Door 1 (WEB) — SQLi"
      echo "Open: http://127.0.0.1:5001"
      echo "Hint: login trusts your quotes. Admin sees more."
      echo "Submit flag in scoreboard: http://127.0.0.1:1337"
      ;;
    FORENSICS)
      bold "Door 2 (FORENSICS) — PNG with extra baggage"
      echo "Artifact: /opt/ctf/challenges/02_forensics_stego/artifacts/cover.png"
      echo "Hint: Some images carry extra baggage. Try 'zipinfo', 'binwalk', or 'strings'."
      ;;
    RE)
      bold "Door 3 (RE) — Tiny ELF gate"
      echo "Run the checker: /opt/ctf/challenges/03_reverse_engineering/gate"
      echo "Hint: recover or bypass the computed key to print the flag."
      ;;
    CRYPTO)
      bold "Door 4 (CRYPTO) — XOR + Base64"
      echo "Cipher: /opt/ctf/challenges/04_crypto_xor/cipher.txt"
      echo "Hint: flags start with WVUCTF{...}. Use a crib to recover the key."
      ;;
    PRIVESC)
      bold "Door 5 (PRIVESC) — PATH hijack"
      echo "SUID helper: /usr/local/bin/ctf-notes"
      echo "Hint: a script calls 'sh' without full path. Control PATH to escalate."
      echo "Flag file: /root/flag_privesc.txt"
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
  if verify_codename "$door" "$code"; then
    ok "Codename accepted."
    start_door "$door"
  else
    err "Incorrect codename for $door. Ask your team captain to read the door again."
    exit 3
  fi
}

cmd_start(){
  local pick="$1"; shift || true
  local door; door=$(door_name "$pick") || { err "Unknown door '$pick'."; exit 2; }
  read -rp "Enter codename for $door: " code
  if verify_codename "$door" "$code"; then
    ok "Codename accepted."
    start_door "$door"
  else
    err "Incorrect codename."
    exit 3
  fi
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
  local sub="${1:-help}"
  case "$sub" in
    menu)    cmd_menu;;
    start)   shift || true; [ $# -ge 1 ] || { err "Usage: ctf start <door>"; exit 1; }; cmd_start "$1";;
    status)  cmd_status;;
    codes)   cmd_codes;;
    help|-h|--help) usage;;
    *) usage; exit 1;;
  esac
}
main "$@"
CTFEOF

chmod 755 /usr/local/bin/ctf

# enable scoreboard service
systemctl daemon-reload
systemctl enable --now 468ctf-scoreboard.service || true

echo "[*] Setup finished. Scoreboard: http://127.0.0.1:1337"
echo "Door codes are available in $DOOR_CODES (instructor view)."
