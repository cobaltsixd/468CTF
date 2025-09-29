#!/usr/bin/env python3
import requests, smtplib, os, sys
from email.message import EmailMessage

# === CONFIG: edit before use or pass via env vars ===
SMTP_HOST = os.environ.get("SMTP_HOST","")
SMTP_PORT = int(os.environ.get("SMTP_PORT","587"))
SMTP_USER = os.environ.get("SMTP_USER","")
SMTP_PASS = os.environ.get("SMTP_PASS","")
FROM_ADDR = SMTP_USER or os.environ.get("FROM_ADDR","student@example.edu")
TO_ADDR = os.environ.get("TO_ADDR","mb00300@mix.wvu.edu")
STUDENT_NAME = os.environ.get("CTF_STUDENT", os.environ.get("USER","student"))
TEAM = os.environ.get("CTF_TEAM","TeamA")
EVIDENCE_DIR = os.environ.get("EVIDENCE_DIR","/home/ctf/evidence")

def fetch_export():
    r = requests.get("http://127.0.0.1:1337/export", timeout=10)
    r.raise_for_status()
    return r.content

def main():
    try:
        data = fetch_export()
    except Exception as e:
        print("Failed to fetch scoreboard export:", e); sys.exit(1)

    msg = EmailMessage()
    msg['From'] = FROM_ADDR
    msg['To'] = TO_ADDR
    msg['Subject'] = f"CTF Submit - {STUDENT_NAME} - {TEAM}"
    msg.set_content(f"Attached is scoreboard export for {STUDENT_NAME} (team {TEAM}).\n")

    msg.add_attachment(data, maintype="application", subtype="json", filename="scoreboard.json")

    if os.path.isdir(EVIDENCE_DIR):
        for fn in sorted(os.listdir(EVIDENCE_DIR)):
            path = os.path.join(EVIDENCE_DIR, fn)
            if os.path.isfile(path):
                with open(path, "rb") as fh:
                    b = fh.read()
                msg.add_attachment(b, maintype="application", subtype="octet-stream", filename=fn)

    try:
        s = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20)
        s.starttls()
        if SMTP_USER:
            s.login(SMTP_USER, SMTP_PASS)
        s.send_message(msg)
        s.quit()
        print("Email sent to", TO_ADDR)
    except Exception as e:
        print("Failed to send email:", e); sys.exit(2)

if __name__ == "__main__":
    main()
