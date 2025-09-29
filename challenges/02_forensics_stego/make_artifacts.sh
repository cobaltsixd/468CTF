#!/usr/bin/env bash
set -euo pipefail
OUTDIR="/opt/ctf/challenges/02_forensics_stego/artifacts"
mkdir -p "$OUTDIR"
# tiny placeholder PNG (1x1 transparent)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc``\x00\x00\x00\x02\x00\x01\xe2!\xbc3\x00\x00\x00\x00IEND\xaeB`\x82' > "$OUTDIR/cover.png"
echo "This is a hidden treasure." > "$OUTDIR/readme.txt"
zip -qj "$OUTDIR/hidden.zip" "$OUTDIR/readme.txt" /opt/ctf/flags/flag_forensics.txt
cat "$OUTDIR/hidden.zip" >> "$OUTDIR/cover.png"
rm "$OUTDIR/readme.txt" "$OUTDIR/hidden.zip"
echo "Created: $OUTDIR/cover.png"
