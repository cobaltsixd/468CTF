#!/usr/bin/env python3
import base64, os
KEY_PATH="/opt/ctf/challenges/04_crypto_xor/key.txt"
FLAG_PATH="/opt/ctf/flags/flag_crypto.txt"
OUT="/opt/ctf/challenges/04_crypto_xor/cipher.txt"

key = open(KEY_PATH,"rb").read().strip()
pt  = open(FLAG_PATH,"rb").read().strip()
ct  = bytes([pt[i] ^ key[i % len(key)] for i in range(len(pt))])
open(OUT,"w").write(base64.b64encode(ct).decode())
print("Wrote", OUT)
