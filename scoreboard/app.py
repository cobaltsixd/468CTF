#!/usr/bin/env python3
from flask import Flask, request, render_template_string, redirect
import sqlite3, time, os, json

APP_DIR = os.path.dirname(__file__)
DB = os.path.join(APP_DIR, "scores.db")

# Flag file locations (created by setup.sh)
FLAGS = {
    "WEB":        "/opt/ctf/flags/flag_web.txt",
    "FORENSICS":  "/opt/ctf/flags/flag_forensics.txt",
    "RE":         "/opt/ctf/flags/flag_re.txt",
    "CRYPTO":     "/opt/ctf/flags/flag_crypto.txt",
    "PRIVESC":    "/opt/ctf/flags/flag_privesc.txt",
}

# Points per challenge
POINTS = {"WEB": 100, "FORENSICS": 100, "RE": 125, "CRYPTO": 125, "PRIVESC": 150}

# Cruise Ship "next stop" messages (shown after a correct submit)
NEXT_LOC = {
    "WEB":       "Next: I’m at the pool! Look for a 2 on the wall.",
    "FORENSICS": "Next: 16 117 -762",
    "RE":        "Next: -3 107 -762",
    "CRYPTO":    "Next: 181 72 -762",
    "PRIVESC":   "Next: -22 146 -767 (Finish!)",
}

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
    cur = conn.execute(sql, args)
    rows = cur.fetchall()
    cur.close()
    return rows

def init_db():
    if not os.path.exists(DB):
        with sqlite3.connect(DB) as conn:
            schema = open(os.path.join(APP_DIR, "schema.sql")).read()
            conn.executescript(schema)

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
    team    = request.form.get("team","").strip()
    chal    = request.form.get("challenge","").strip().upper()
    flag    = request.form.get("flag","").strip()

    if chal not in FLAGS or not team or not student:
        return redirect("/")

    # Load correct flag from disk
    try:
        with open(FLAGS[chal], "r") as f:
            correct = f.read().strip()
    except Exception:
        correct = "MISSING"

    ok = (flag == correct)
    ts = int(time.time())

    with sqlite3.connect(DB) as conn:
        if ok:
            # Award points ONCE per student per challenge:
            before = conn.total_changes
            conn.execute("insert or ignore into solves(student, challenge) values(?,?)", (student, chal))
            # If the solves row was newly inserted, award points; otherwise 0
            awarded = (conn.total_changes > before)
            pts = POINTS[chal] if awarded else 0
            conn.execute(
                "insert into submissions(student, team, challenge, flag, correct, points, ts) "
                "values(?,?,?,?,?,?,?)",
                (student, team, chal, "REDACTED", 1, pts, ts)
            )
        else:
            conn.execute(
                "insert into submissions(student, team, challenge, flag, correct, points, ts) "
                "values(?,?,?,?,?,?,?)",
                (student, team, chal, flag, 0, 0, ts)
            )
        conn.commit()

    if ok:
        # Show both Java and Bedrock commands + the next location hint
        java_cmd = f"/trigger {chal.lower()} set 1"
        bedrock_cmd = f"/scoreboard players set @p {chal.lower()} 1"
        nxt = NEXT_LOC.get(chal, "Next: ask your instructor.")
        html = f"""
          <h2>✔ Correct!</h2>
          <p>Use one of these in Minecraft to open your door:</p>
          <ul>
            <li><b>Java:</b> {java_cmd}</li>
            <li><b>Bedrock/Xbox:</b> {bedrock_cmd}</li>
          </ul>
          <h3>{nxt}</h3>
          <p><a href='/'>Back to scoreboard</a></p>
        """
        return html

    return redirect("/")

@app.route("/export")
def export():
    with sqlite3.connect(DB) as conn:
        rows = q(conn, """
            select student, team, challenge, correct, points, ts
            from submissions order by ts desc
        """)
    data = [
        {
            "student":  r[0],
            "team":     r[1],
            "challenge":r[2],
            "correct":  int(r[3]),
            "points":   int(r[4]),
            "ts":       int(r[5]),
        } for r in rows
    ]
    return app.response_class(
        response=json.dumps(data, indent=2),
        mimetype="application/json"
    )

if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=1337)
