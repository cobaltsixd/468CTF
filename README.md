# 468CTF — WVU CYBE-468S Midterm CTF

This repository contains a self-contained midterm CTF environment for Kali VMs.
Each student runs the installer on their Kali VM and solves 5 offline CTFs.
A local scoreboard runs at http://127.0.0.1:1337.

Installation options:

1. Quick curl installer (students):
   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/cobaltsixd/468CTF/main/install.sh)"

2. .deb bootstrap (instructor builds once and uploads to Releases). Students:
   wget -O /tmp/468ctf.deb <release-url>
   sudo apt install -y ./ /tmp/468ctf.deb

After install:
- Use `ctf menu` to select and start a challenge (requires codename printed on Minecraft door).
- Scoreboard: http://127.0.0.1:1337
- Door codes (instructor): /opt/ctf/door-codes.txt
