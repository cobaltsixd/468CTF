#!/usr/bin/env python3
from flask import Flask, request, render_template_string
import sqlite3, os

DB = "/opt/ctf/challenges/01_web_sqlite_sqli/users.db"
FLAG_PATH = "/opt/ctf/flags/flag_web.txt"

app = Flask(__name__)

TPL = """
<!doctype html><title>Retro Login</title>
<h2>Retro Login</h2>
<form method="post" action="/login">
  <input name="user" placeholder="user"><input name="pass" placeholder="pass" type="password">
  <button>Login</button>
</form>
<pre>{{msg}}</pre>
"""

def q(sql):
    with sqlite3.connect(DB) as c:
        cur = c.cursor(); cur.execute(sql); rows = cur.fetchall(); cur.close(); return rows

@app.route("/", methods=["GET"])
def index(): return render_template_string(TPL, msg="")

@app.route("/login", methods=["POST"])
def login():
    u = request.form.get("user",""); p = request.form.get("pass","")
    # intentionally vulnerable
    try:
        rows = q(f"SELECT role FROM users WHERE user='{u}' AND pass='{p}'")
    except Exception as e:
        return render_template_string(TPL, msg=f"Error: {e}")
    if rows:
        if rows[0][0] == "admin":
            try:
                return render_template_string(TPL, msg=open(FLAG_PATH).read())
            except:
                return render_template_string(TPL, msg="flag missing")
        return render_template_string(TPL, msg="Welcome!")
    return render_template_string(TPL, msg="Nope.")

if __name__ == "__main__":
    app.run("127.0.0.1", 5001)
