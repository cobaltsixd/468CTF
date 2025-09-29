#!/usr/bin/env bash
set -euo pipefail
OUT="/opt/ctf/challenges/03_reverse_engineering/gate"
mkdir -p "$(dirname "$OUT")"
gcc -s -O2 -o "$OUT" /opt/ctf/src/challenges/03_reverse_engineering/gate.c || gcc -s -O2 -o "$OUT" "$(dirname "$0")/gate.c"
chmod 755 "$OUT"
echo "Built $OUT"
