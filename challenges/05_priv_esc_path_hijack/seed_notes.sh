#!/usr/bin/env bash
set -euo pipefail
mkdir -p /usr/local/lib
cp /opt/ctf/src/challenges/05_priv_esc_path_hijack/notes.sh /usr/local/lib/ctf-notes.sh
chmod 755 /usr/local/lib/ctf-notes.sh
cat >/usr/local/bin/ctf-notes.c <<'EOF'
#include <unistd.h>
int main(){ setuid(0); execl("/usr/local/lib/ctf-notes.sh","ctf-notes.sh",NULL); return 0; }
EOF
gcc -O2 -s /usr/local/bin/ctf-notes.c -o /usr/local/bin/ctf-notes
chown root:root /usr/local/bin/ctf-notes
chmod 4755 /usr/local/bin/ctf-notes
echo "Installed SUID helper /usr/local/bin/ctf-notes"
