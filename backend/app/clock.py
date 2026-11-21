"""Server time and the working-day calendar. The phone's clock is never used."""
from __future__ import annotations

import datetime as dt
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import get_settings
from .models import Holiday, SessionWindow

DEFAULT_WINDOWS = [
    ("M", "Morning", dt.time(9, 30), dt.time(10, 0)),
    ("A", "Afternoon", dt.time(12, 45), dt.time(13, 30)),
    ("E", "Evening", dt.time(17, 45), dt.time(18, 30)),
]


class Clock:
    """Wrapped so tests can freeze time. Returns naive local (IST) datetimes."""

    def now(self) -> dt.datetime:
        tz = ZoneInfo(get_settings().timezone)
        return dt.datetime.now(tz).replace(tzinfo=None)


clock = Clock()


def get_clock() -> Clock:
    return clock


def ensure_windows(db: Session) -> None:
    if db.scalar(select(SessionWindow).limit(1)) is None:
        for s, label, a, b in DEFAULT_WINDOWS:
            db.add(SessionWindow(session=s, label=label, start_time=a, end_time=b, active=True))
        db.commit()


def windows(db: Session) -> list[SessionWindow]:
    ensure_windows(db)
    order = {"M": 0, "A": 1, "E": 2}
    rows = db.scalars(select(SessionWindow).where(SessionWindow.active)).all()
    return sorted(rows, key=lambda w: order[w.session])


def holidays_between(db: Session, a: dt.date, b: dt.date) -> dict[dt.date, str]:
    rows = db.scalars(select(Holiday).where(Holiday.date >= a, Holiday.date <= b)).all()
    return {h.date: h.name for h in rows}


def is_working_day(d: dt.date, holidays: dict[dt.date, str]) -> bool:
    """5-day week: Monday to Friday, except holidays."""
    return d.weekday() < 5 and d not in holidays


def working_days(db: Session, a: dt.date, b: dt.date) -> list[dt.date]:
    if b < a:
        return []
    hol = holidays_between(db, a, b)
    out, d = [], a
    while d <= b:
        if is_working_day(d, hol):
            out.append(d)
        d += dt.timedelta(days=1)
    return out


def open_window(db: Session, now: dt.datetime) -> SessionWindow | None:
    t = now.time()
    for w in windows(db):
        if w.start_time <= t <= w.end_time:
            return w
    return None


def last_window_end(db: Session) -> dt.time:
    return max(w.end_time for w in windows(db))
