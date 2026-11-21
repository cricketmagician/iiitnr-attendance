"""Day close: create pending reviews for days with fewer than two sessions, then send the
central admin one list. Run from cron after the evening window closes, e.g.

    35 18 * * 1-5  cd /srv/att/backend && .venv/bin/python -m app.jobs close-day

or set ATT_RUN_SCHEDULER=true to let the API process run it at 18:35 itself.
Safe to run more than once for the same day.
"""
from __future__ import annotations

import argparse
import datetime as dt
import logging

from sqlalchemy import select

from .clock import clock
from .config import get_settings
from .daybook import evaluate_day
from .db import SessionLocal
from .models import DayReview
from .notify import send_mail

log = logging.getLogger("att.jobs")


def close_day(day: dt.date | None = None) -> int:
    now = clock.now()
    day = day or now.date()
    with SessionLocal() as db:
        evaluate_day(db, day, now)
        pending = db.scalars(select(DayReview).where(DayReview.date == day, DayReview.status == "pending")).all()
        if pending:
            lines = [f"Days with fewer than two sessions on {day:%a %d %b %Y}: {len(pending)}", ""]
            for r in pending:
                p = r.person
                marked = r.sessions_marked or "none"
                lines.append(f"- {p.name} ({p.roll_no}, {p.programme}, {p.department}): sessions marked: {marked}")
            lines += ["", "Open the IIITNR app > Attendance admin > Day reviews to decide each one."]
            send_mail(get_settings().admin_notify_email, f"Attendance review list – {day:%d %b %Y}", "\n".join(lines))
        log.info("close-day %s: %d pending", day, len(pending))
        return len(pending)


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("close-day")
    c.add_argument("--date", type=dt.date.fromisoformat, default=None)
    args = ap.parse_args()
    if args.cmd == "close-day":
        close_day(args.date)


if __name__ == "__main__":
    main()
