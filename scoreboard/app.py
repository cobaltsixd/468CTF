#!/usr/bin/env python3
from flask import Flask, request, render_template_string, redirect, send_file
import sqlite3, time, os, json

APP_DIR = os.path.dirname(__file__)
DB = os.path.join(APP_DIR, "scores.db")
FLAGS = {
    "WEB":        "/opt/ctf/flags/flag_web.txt",
    "FORENSICS":  "/opt/ctf/flags/flag_forensics.txt",
    "RE":         "/opt/ctf/flags/flag_re.txt",
    "CRYPTO":     "/opt/ctf/flags/flag_crypto.txt",
    "PRIVESC":    "/opt/ctf/flags/flag_privesc.txt",
}
POINTS = {"WEB": 100, "FORENSICS": 100, "RE": 125, "CRYPTO": 125, "PRIVESC": 150}

app = Flask(__name__)

TEMPLATE = """
<!doctype html><title>468CTF Scoreboard</title>
<h1>468CTF — Local Scoreboard</h1>
<form method="post" action="/submit">
  <label>Student (your id):</label> <input name="student" required>
  <label>Team (TeamA/TeamB):</label> <input name="team" required>
  <label>Challenge (WEB/FORENSICS/RE/CRYPTO/PRIVESC):</label> <input name="challenge" required>
  <label>Flag:</label> <input name="flag" required>
  <button type="submit">Submit</button>
</form>
<hr>
<h2>Scores</h2>
<table border="1" cellpadding="6">
<tr><th>Team</th><th>Points</th><th>Last Submit</th></tr>
{% for row in scores %}
<tr><td>{{row[0]}}</td><td>{{row[1]}}</td><td>{{row[2]}}</td></tr>
{% endfor %}
</table>
<p><a href="/export">Export JSON</a></p>
"""

def q(conn, sql, args=()):
    cur = conn.execute(sql, args); rows = cur.fetchall(); cur.close(); return rows

def init_db():
    if not os.path.exists(DB):
        with sqlite3.connect(DB) as conn:
            conn.executescript(open(os.path.join(APP_DIR,"schema.sql")).read())

@app.route("/")
def index():
    with sqlite3.connect(DB) as conn:
        rows = q(conn, """
        select team, coalesce(sum(points),0) as pts,
               max(strftime('%Y-%m-%d %H:%M:%S', ts, 'unixepoch')) as last
        from submissions
        group by team order by pts desc
        """)
    return render_template_string(TEMPLATE, scores=rows)

@app.route("/submit", methods=["POST"])
def submit():
    student = request.form.get("student","").strip()
    team = request.form.get("team","").strip()
    chal = request.form.get("challenge","").strip().upper()
    flag = request.form.get("flag","").strip()
    if chal not in FLAGS or not team or not student:
        return redirect("/")
    try:
        with open(FLAGS[chal],"r") as f:
            correct = f.read().strip()
    except:
        correct = "MISSING"
    ok = (flag == correct)
    ts = int(time.time())
    with sqlite3.connect(DB) as conn:
        if ok:
            # award only once per student per challenge
            conn.execute("insert or ignore into solves(student, challenge) values(?,?)", (student, chal))
            already = q(conn, "select 1 from solves where student=? and challenge=?", (student, chal))
            if already:
                conn.execute("insert into submissions(student, team, challenge, flag, correct, points, ts) values(?,?,?,?,?,?,?)",
                             (student, team, chal, "REDACTED", 1, POINTS[chal], ts))
        else:
            conn.execute("insert into submissions(student, team, challenge, flag, correct, points, ts) values(?,?,?,?,?,?,?)",
                         (student, team, chal, flag, 0, 0, ts))
        conn.commit()
    # on success, show the minecraft command
    if ok:
        mc_cmd = f"/trigger {chal.lower()} set 1"
        return f"<p>Correct! Paste this in Minecraft to open your door: <b>{mc_cmd}</b></p><p><a href='/'>Back</a></p>"
    return redirect("/")

@app.route("/export")
def export():
    with sqlite3.connect(DB) as conn:
        rows = q(conn, "select student, team, challenge, correct, points, ts from submissions order by ts desc")
    data = [{"student":r[0],"team":r[1],"challenge":r[2],"correct":int(r[3]),"points":int(r[4]),"ts":int(r[5])} for r in rows]
    return app.response_class(response=json.dumps(data, indent=2), mimetype="application/json")

if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=1337)
