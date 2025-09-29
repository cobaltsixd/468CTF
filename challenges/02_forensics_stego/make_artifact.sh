#!/usr/bin/env bash
# Build the Forensics PNG/ZIP polyglot at artifacts/cover.png
set -euo pipefail
umask 0002

OUTDIR="/opt/ctf/challenges/02_forensics_stego/artifacts"
FLAG="/opt/ctf/flags/flag_forensics.txt"

# Ensure artifacts dir exists with correct owner/group/perms (setgid so group sticks)
install -d -m 2775 -o ctf -g ctfrw "$OUTDIR"

# 1x1 transparent PNG (valid header + chunks)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc``\x00\x00\x00\x02\x00\x01\xe2!\xbc3\x00\x00\x00\x00IEND\xaeB`\x82' > "$OUTDIR/cover.png"

# Build a small ZIP containing a note and the real flag
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "This is a hidden treasure." > "$tmp/readme.txt"
cp -a "$FLAG" "$tmp/flag_forensics.txt"
( cd "$tmp" && zip -q -9 payload.zip readme.txt flag_forensics.txt )

# PNG/ZIP polyglot: append ZIP after PNG (PNG ignores trailing bytes)
cat "$tmp/payload.zip" >> "$OUTDIR/cover.png"

# Ensure readable/writable by ctf + ctfrw
chown ctf:ctfrw "$OUTDIR/cover.png"
chmod 664 "$OUTDIR/cover.png"

echo "Created: $OUTDIR/cover.png"
