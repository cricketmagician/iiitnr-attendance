"""Day rule: a working day is present when at least 2 of the 3 sessions are marked.
Days with fewer, not covered by confirmed leave, go to the central admin for review."""
from __future__ import annotations

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from .clock import holidays_between, is_working_day, last_window_end
from .config import get_settings
from .models import DayReview, LeaveApplication, Mark, Person

MIN_SESSIONS = 2


def scholars(db: Session) -> list[Person]:
    rows = db.scalars(select(Person).where(Person.active).order_by(Person.name)).all()
    return [p for p in rows if p.is_scholar]


def marks_by_day(db: Session, person_ids: list[int], a: dt.date, b: dt.date) -> dict[tuple[int, dt.date], dict]:
    out: dict[tuple[int, dt.date], dict] = {}
    if not person_ids:
        return out
    for m in db.scalars(select(Mark).where(Mark.person_id.in_(person_ids), Mark.date >= a, Mark.date <= b,
                                           Mark.flagged_at.is_(None))).all():
        out.setdefault((m.person_id, m.date), {})[m.session] = m.marked_at.strftime("%H:%M")
    return out


def leaves_in(db: Session, person_ids: list[int], a: dt.date, b: dt.date) -> list[LeaveApplication]:
    if not person_ids:
        return []
    return db.scalars(select(LeaveApplication).where(
        LeaveApplication.person_id.in_(person_ids), LeaveApplication.status == "confirmed",
        LeaveApplication.from_date <= b, LeaveApplication.to_date >= a)).all()


def reviews_in(db: Session, person_ids: list[int], a: dt.date, b: dt.date) -> dict[tuple[int, dt.date], DayReview]:
    if not person_ids:
        return {}
    rows = db.scalars(select(DayReview).where(
        DayReview.person_id.in_(person_ids), DayReview.date >= a, DayReview.date <= b)).all()
    return {(r.person_id, r.date): r for r in rows}


def day_code(*, d: dt.date, today: dt.date, day_closed: bool, joining: dt.date | None, holidays: dict,
             sessions: dict, on_leave: bool, review: DayReview | None) -> str:
    """Register codes: P, P*, L, A, R (awaiting admin review), H, W, '-' (today, in progress), '' (no record)."""
    if d.weekday() >= 5:
        return "W"
    if d in holidays:
        return "H"
    if (joining and d < joining) or d > today:
        return ""
    if on_leave:
        return "L"
    if len(sessions) >= MIN_SESSIONS:
        return "P"
    if d == today and not day_closed:
        return "-"
    if review is None or review.status == "pending":
        return "R"
    return {"present": "P*", "absent": "A", "leave": "L"}[review.status]


def go_live() -> dt.date | None:
    v = get_settings().go_live_date
    return dt.date.fromisoformat(v) if v else None


def _start(joining: dt.date | None) -> dt.date | None:
    gl = go_live()
    if gl and joining:
        return max(gl, joining)
    return gl or joining


def evaluate_day(db: Session, d: dt.date, now: dt.datetime) -> list[DayReview]:
    """Run after the evening window closes (and safe to re-run). Creates pending reviews."""
    if go_live() and d < go_live():
        return []
    if d == now.date() and now.time() < last_window_end(db):
        return []
    if not is_working_day(d, holidays_between(db, d, d)):
        return []
    people = [p for p in scholars(db) if not p.joining_date or p.joining_date <= d]
    ids = [p.id for p in people]
    marks = marks_by_day(db, ids, d, d)
    on_leave = {lv.person_id for lv in leaves_in(db, ids, d, d)}
    existing = reviews_in(db, ids, d, d)
    created = []
    for p in people:
        sessions = marks.get((p.id, d), {})
        if p.id in on_leave or len(sessions) >= MIN_SESSIONS or (p.id, d) in existing:
            continue
        r = DayReview(person_id=p.id, date=d, sessions_marked="".join(sorted(sessions, key="MAE".index)),
                      status="pending", created_at=now)
        db.add(r)
        created.append(r)
    db.commit()
    return created


def month_grid(db: Session, people: list[Person], month: str, now: dt.datetime) -> list[dict]:
    y, m = map(int, month.split("-"))
    first = dt.date(y, m, 1)
    last = (dt.date(y + (m == 12), m % 12 + 1, 1) - dt.timedelta(days=1))
    ids = [p.id for p in people]
    hol = holidays_between(db, first, last)
    marks = marks_by_day(db, ids, first, last)
    leaves = leaves_in(db, ids, first, last)
    revs = reviews_in(db, ids, first, last)
    today = now.date()
    closed = now.time() >= last_window_end(db)
    rows = []
    for p in people:
        my_leaves = [lv for lv in leaves if lv.person_id == p.id]
        days, totals = [], {"P": 0, "P*": 0, "L": 0, "A": 0, "R": 0}
        d = first
        while d <= last:
            s = marks.get((p.id, d), {})
            lv = next((x for x in my_leaves if x.from_date <= d <= x.to_date), None)
            code = day_code(d=d, today=today, day_closed=closed, joining=_start(p.joining_date), holidays=hol,
                            sessions=s, on_leave=lv is not None and is_working_day(d, hol), review=revs.get((p.id, d)))
            if code in totals:
                totals[code] += 1
            r = revs.get((p.id, d))
            days.append({"date": d.isoformat(), "code": code, "sessions": s,
                         "holiday": hol.get(d), "leave_type": lv.leave_type if lv else None,
                         "remark": r.remark if r and r.status == "present" else ""})
            d += dt.timedelta(days=1)
        rows.append({"person_id": p.id, "name": p.name, "roll_no": p.roll_no, "programme": p.programme,
                     "department": p.department, "days": days, "totals": totals})
    return rows
