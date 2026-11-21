#!/usr/bin/env python3
"""Helper script to check or reset face enrollment and attendance marks."""
import sqlite3
import sys
from pathlib import Path

DB_PATH = Path(__file__).parent / "att_dev.db"

def status():
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    person = cur.execute("SELECT id, email, (face_embedding IS NOT NULL), face_enrolled_at FROM att_person WHERE id = 1").fetchone()
    marks = cur.execute("SELECT id, date, session, marked_at FROM att_mark").fetchall()
    print("--- SCHOLAR 1 STATUS ---")
    print(f"Email: {person[1]}")
    print(f"Face Enrolled: {'YES ✅' if person[2] else 'NO (Ready for Fresh Enrollment) 📸'}")
    print(f"Enrolled At: {person[3]}")
    print(f"Total Marks Today: {len(marks)}")
    for m in marks:
        print(f"  - Mark ID {m[0]}: {m[1]} {m[2]} at {m[3]}")
    con.close()

def reset_face():
    con = sqlite3.connect(DB_PATH)
    con.execute("UPDATE att_person SET face_embedding = NULL, face_enrolled_at = NULL WHERE id = 1")
    con.commit()
    con.close()
    print("✅ Scholar 1 face template has been RESET to NULL. Ready for fresh live face registration!")

def clear_marks():
    con = sqlite3.connect(DB_PATH)
    con.execute("DELETE FROM att_mark")
    con.commit()
    con.close()
    print("✅ Today's attendance marks CLEARED. Ready to mark again!")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "reset":
        reset_face()
    elif cmd == "clear-marks":
        clear_marks()
    elif cmd == "reset-all":
        reset_face()
        clear_marks()
    else:
        status()
