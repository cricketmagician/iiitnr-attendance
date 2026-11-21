"""Load or update scholars and staff from a CSV file (safe to re-run; matches on email).

Columns:
  email,name,roll_no,programme,funding,joining_date,department,supervisor_email,roles
  - programme: PhD | MTech | (blank for staff)
  - funding: institute | external
  - joining_date: YYYY-MM-DD (starts each scholar's leave year)
  - roles: any of scholar;supervisor;hod;dean_ri;admin  (separate with ;)

Usage:  python -m scripts.import_people people.csv
"""
import csv
import datetime as dt
import sys

from sqlalchemy import select

from app.config import get_settings
from app.db import Base, SessionLocal, engine
from app.models import Person


def main(path: str) -> None:
    Base.metadata.create_all(engine)
    domain = "@" + get_settings().institute_domain
    added = updated = 0
    with SessionLocal() as db, open(path, newline="", encoding="utf-8-sig") as fh:
        for i, row in enumerate(csv.DictReader(fh), start=2):
            email = row["email"].strip().lower()
            if not email.endswith(domain):
                print(f"line {i}: skipped {email} (not an institute email)")
                continue
            programme = (row.get("programme") or "").strip() or None
            if programme not in (None, "PhD", "MTech"):
                print(f"line {i}: skipped {email} (programme must be PhD, MTech or blank)")
                continue
            p = db.scalar(select(Person).where(Person.email == email))
            if p is None:
                p = Person(email=email)
                db.add(p)
                added += 1
            else:
                updated += 1
            p.name = row["name"].strip()
            p.roll_no = (row.get("roll_no") or "").strip()
            p.programme = programme
            p.funding = (row.get("funding") or "institute").strip().lower()
            jd = (row.get("joining_date") or "").strip()
            p.joining_date = dt.date.fromisoformat(jd) if jd else None
            p.department = (row.get("department") or "").strip()
            p.supervisor_email = (row.get("supervisor_email") or "").strip().lower()
            p.roles = ",".join(r.strip() for r in (row.get("roles") or "scholar").split(";") if r.strip())
            p.active = True
        db.commit()
    print(f"Added {added}, updated {updated}.")


if __name__ == "__main__":
    main(sys.argv[1])
