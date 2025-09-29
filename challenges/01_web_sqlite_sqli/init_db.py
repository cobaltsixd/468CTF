#!/usr/bin/env python3
import sqlite3, os
DB="/opt/ctf/challenges/01_web_sqlite_sqli/users.db"
os.makedirs(os.path.dirname(DB), exist_ok=True)
conn = sqlite3.connect(DB)
c = conn.cursor()
c.execute("create table if not exists users (user text, pass text, role text)")
c.execute("delete from users")
c.execute("insert into users values ('admin','changeme','admin')")
c.execute("insert into users values ('student','password','user')")
conn.commit(); conn.close()
print("DB initialized at", DB)
