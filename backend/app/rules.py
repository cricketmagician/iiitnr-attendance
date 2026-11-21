"""Leave rules (same for PhD and MTech) and balance calculation.

Institute rules as given:
- Ordinary leave: 30 days per leave year, counted from the date of joining; up to 15 of them medical.
- At most 15 days of ordinary + medical leave in a semester.
- Institute scholars: at most 5 days at a stretch (ordinary + medical).
- Maternity 180 days and paternity 15 days, once each.
- Academic duty: 30 days a year, up to 60 with the Dean (R&I).
- 5-day week: Saturdays, Sundays and holidays inside a leave are not counted.
- No carry-forward; the admin may add days by hand (LeaveAdjustment).
All numbers are admin settings (att_setting), so a rule change needs no code change.
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .clock import holidays_between, is_working_day, working_days
from .models import ACTIVE_LEAVE, LeaveAdjustment, LeaveApplication, Person, Setting

DEFAULTS: dict = {
    "ordinary_days_per_year": 30,
    "medical_max_per_year": 15,
    "semester_cap_days": 15,
    "institute_max_stretch_days": 5,
    "maternity_days": 180,
    "paternity_days": 15,
    "maternity_paternity_count_calendar_days": True,
    "academic_days_per_year": 30,
    "academic_max_with_dean": 60,
    "medical_backdate_days": 3,
    "medical_certificate_after_days": 2,
    # Semesters as MM-DD ranges (Jul–Dec, Jan–Jun)
    "semesters": [["07-01", "12-31"], ["01-01", "06-30"]],
}

LEAVE_TYPES = {
    "CASUAL": "Casual / ordinary leave",
    "MEDICAL": "Medical leave",
    "ACADEMIC": "Academic duty (conference, field work, course)",
    "MATERNITY": "Maternity leave",
    "PATERNITY": "Paternity leave",
}
ORDINARY_POOL = ("CASUAL", "MEDICAL")


def settings(db: Session) -> dict:
    out = dict(DEFAULTS)
    for row in db.scalars(select(Setting)).all():
        out[row.key] = row.value
    return out


# ---------------------------------------------------------------- leave year and semester

def leave_year(joining: dt.date, d: dt.date) -> tuple[dt.date, dt.date]:
    """The leave year that contains d, running from the joining date's anniversary."""
    def anniv(year: int) -> dt.date:
        try:
            return joining.replace(year=year)
        except ValueError:  # joined 29 Feb
            return dt.date(year, 3, 1)
    start = anniv(d.year)
    if start > d:
        start = anniv(d.year - 1)
    nxt = anniv(start.year + 1)
    return start, nxt - dt.timedelta(days=1)


def semester(cfg: dict, d: dt.date) -> tuple[dt.date, dt.date]:
    for a, b in cfg["semesters"]:
        am, ad = map(int, a.split("-"))
        bm, bd = map(int, b.split("-"))
        start = dt.date(d.year, am, ad)
        end = dt.date(d.year, bm, bd)
        if end < start:  # range crossing new year
            if d >= start:
                end = dt.date(d.year + 1, bm, bd)
            else:
                start = dt.date(d.year - 1, am, ad)
        if start <= d <= end:
            return start, end
    return dt.date(d.year, 1, 1), dt.date(d.year, 12, 31)


# ---------------------------------------------------------------- counting

def charged_days(db: Session, cfg: dict, leave_type: str, a: dt.date, b: dt.date) -> int:
    if leave_type in ("MATERNITY", "PATERNITY") and cfg["maternity_paternity_count_calendar_days"]:
        return (b - a).days + 1
    return len(working_days(db, a, b))


def _active(db: Session, person_id: int, types: tuple[str, ...], exclude_id: int | None = None):
    q = select(LeaveApplication).where(
        LeaveApplication.person_id == person_id,
        LeaveApplication.leave_type.in_(types),
        LeaveApplication.status.in_(ACTIVE_LEAVE),
    )
    if exclude_id:
        q = q.where(LeaveApplication.id != exclude_id)
    return db.scalars(q).all()


def used_in_range(db: Session, cfg: dict, person_id: int, types: tuple[str, ...], a: dt.date, b: dt.date,
                  exclude_id: int | None = None) -> int:
    """Working days of active leave of these types that fall inside [a, b]."""
    total = 0
    for lv in _active(db, person_id, types, exclude_id):
        lo, hi = max(lv.from_date, a), min(lv.to_date, b)
        if lo <= hi:
            total += charged_days(db, cfg, lv.leave_type, lo, hi)
    return total


def adjustment(db: Session, person_id: int, pool: str, year_start: dt.date) -> float:
    v = db.scalar(select(func.coalesce(func.sum(LeaveAdjustment.days), 0)).where(
        LeaveAdjustment.person_id == person_id, LeaveAdjustment.pool == pool,
        LeaveAdjustment.leave_year_start == year_start))
    return float(v or 0)


@dataclass
class Balance:
    pool: str
    label: str
    entitled: float
    used: float

    @property
    def left(self) -> float:
        return self.entitled - self.used


def balances(db: Session, person: Person, on: dt.date) -> dict:
    cfg = settings(db)
    joining = person.joining_date or on
    ys, ye = leave_year(joining, on)
    ordinary_used = used_in_range(db, cfg, person.id, ORDINARY_POOL, ys, ye)
    medical_used = used_in_range(db, cfg, person.id, ("MEDICAL",), ys, ye)
    academic_used = used_in_range(db, cfg, person.id, ("ACADEMIC",), ys, ye)
    ss, se = semester(cfg, on)
    sem_used = used_in_range(db, cfg, person.id, ORDINARY_POOL, ss, se)
    once = {t: bool(_active(db, person.id, (t,))) for t in ("MATERNITY", "PATERNITY")}

    def pool(code: str, label: str, entitled: float, used: float) -> dict:
        b = Balance(code, label, entitled, used)
        return {"pool": b.pool, "label": b.label, "entitled": b.entitled, "used": b.used, "left": b.left}

    adj = lambda p: adjustment(db, person.id, p, ys)  # noqa: E731
    return {
        "leave_year": [ys.isoformat(), ye.isoformat()],
        "semester": [ss.isoformat(), se.isoformat()],
        "pools": [
            pool("ORDINARY", "Ordinary leave (incl. medical)", cfg["ordinary_days_per_year"] + adj("ORDINARY"),
                 ordinary_used),
            pool("MEDICAL", "of which medical", cfg["medical_max_per_year"] + adj("MEDICAL"), medical_used),
            pool("SEMESTER", "Ordinary leave this semester", cfg["semester_cap_days"], sem_used),
            pool("ACADEMIC", "Academic duty (beyond this needs the Dean, R&I)",
                 cfg["academic_days_per_year"] + adj("ACADEMIC"), academic_used),
        ],
        "maternity_used": once["MATERNITY"],
        "paternity_used": once["PATERNITY"],
    }


# ---------------------------------------------------------------- validation

class RuleError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code, self.message = code, message


def _stretch_days(db: Session, cfg: dict, person_id: int, a: dt.date, b: dt.date, exclude_id: int | None) -> int:
    """Working days in the continuous stretch of ordinary/medical leave that includes [a, b].
    Leaves separated only by weekends or holidays count as one stretch."""
    others = sorted(_active(db, person_id, ORDINARY_POOL, exclude_id), key=lambda x: x.from_date)
    lo, hi = a, b
    changed = True
    while changed:
        changed = False
        for lv in others:
            gap_before = working_days(db, lv.to_date + dt.timedelta(days=1), lo - dt.timedelta(days=1))
            gap_after = working_days(db, hi + dt.timedelta(days=1), lv.from_date - dt.timedelta(days=1))
            touches_before = lv.to_date < lo and not gap_before
            touches_after = lv.from_date > hi and not gap_after
            overlaps = lv.from_date <= hi and lv.to_date >= lo
            if (touches_before or touches_after or overlaps) and (lv.from_date < lo or lv.to_date > hi):
                lo, hi = min(lo, lv.from_date), max(hi, lv.to_date)
                changed = True
    return len(working_days(db, lo, hi))


def check_application(db: Session, person: Person, leave_type: str, a: dt.date, b: dt.date, today: dt.date,
                      has_attachment: bool, exclude_id: int | None = None) -> tuple[int, bool]:
    """Returns (days charged, needs Dean approval). Raises RuleError with a plain message."""
    cfg = settings(db)
    if leave_type not in LEAVE_TYPES:
        raise RuleError("LEAVE_TYPE", "Choose a valid leave type.")
    if b < a:
        raise RuleError("LEAVE_DATES", "The end date is before the start date.")
    if person.joining_date and a < person.joining_date:
        raise RuleError("LEAVE_DATES", "Leave cannot start before your joining date.")
    if a < today:
        back = (today - a).days
        if leave_type != "MEDICAL" or back > cfg["medical_backdate_days"]:
            raise RuleError("LEAVE_BACKDATED",
                            f"Past dates are allowed only for medical leave, up to {cfg['medical_backdate_days']} days back.")

    overlap = db.scalar(select(LeaveApplication.id).where(
        LeaveApplication.person_id == person.id, LeaveApplication.status.in_(ACTIVE_LEAVE),
        LeaveApplication.from_date <= b, LeaveApplication.to_date >= a,
        *( [LeaveApplication.id != exclude_id] if exclude_id else [] )))
    if overlap:
        raise RuleError("LEAVE_OVERLAP", "You already have a leave application covering some of these dates.")

    joining = person.joining_date or a
    ys, ye = leave_year(joining, a)
    if b > ye:
        raise RuleError("LEAVE_YEAR_SPLIT",
                        f"Your leave year ends on {ye:%d %b %Y}. Apply separately for the days after it.")

    days = charged_days(db, cfg, leave_type, a, b)
    if days == 0:
        raise RuleError("LEAVE_NO_WORKING_DAYS", "These dates are all weekends or holidays; no leave is needed.")

    if leave_type in ORDINARY_POOL:
        pool_left = cfg["ordinary_days_per_year"] + adjustment(db, person.id, "ORDINARY", ys) \
            - used_in_range(db, cfg, person.id, ORDINARY_POOL, ys, ye, exclude_id)
        if days > pool_left:
            raise RuleError("LEAVE_BALANCE", f"Only {pool_left:g} days of ordinary leave are left in this leave year.")
        if leave_type == "MEDICAL":
            med_left = cfg["medical_max_per_year"] + adjustment(db, person.id, "MEDICAL", ys) \
                - used_in_range(db, cfg, person.id, ("MEDICAL",), ys, ye, exclude_id)
            if days > med_left:
                raise RuleError("LEAVE_MEDICAL_LIMIT",
                                f"Only {med_left:g} days of medical leave are left in this leave year.")
            if days > cfg["medical_certificate_after_days"] and not has_attachment:
                raise RuleError("LEAVE_CERTIFICATE",
                                f"Attach a medical certificate for medical leave over "
                                f"{cfg['medical_certificate_after_days']} days.")
        # Semester cap: count the days of this leave in each semester it touches
        d = a
        while d <= b:
            ss, se = semester(cfg, d)
            part = len(working_days(db, max(a, ss), min(b, se)))
            used = used_in_range(db, cfg, person.id, ORDINARY_POOL, ss, se, exclude_id)
            if used + part > cfg["semester_cap_days"]:
                raise RuleError("LEAVE_SEMESTER_CAP",
                                f"At most {cfg['semester_cap_days']} days of leave are allowed in a semester; "
                                f"{used} are already taken or applied for in this one.")
            d = se + dt.timedelta(days=1)
        if person.funding == "institute":
            stretch = _stretch_days(db, cfg, person.id, a, b, exclude_id)
            if stretch > cfg["institute_max_stretch_days"]:
                raise RuleError("LEAVE_STRETCH",
                                f"Institute scholars can take at most {cfg['institute_max_stretch_days']} "
                                f"days at a stretch (this would make {stretch}).")
        return days, False

    if leave_type in ("MATERNITY", "PATERNITY"):
        if _active(db, person.id, (leave_type,), exclude_id):
            raise RuleError("LEAVE_ONCE", f"{LEAVE_TYPES[leave_type]} can be taken only once.")
        limit = cfg["maternity_days" if leave_type == "MATERNITY" else "paternity_days"]
        if days > limit:
            raise RuleError("LEAVE_BALANCE", f"{LEAVE_TYPES[leave_type]} is at most {limit} days.")
        return days, False

    # ACADEMIC
    used = used_in_range(db, cfg, person.id, ("ACADEMIC",), ys, ye, exclude_id)
    base = cfg["academic_days_per_year"] + adjustment(db, person.id, "ACADEMIC", ys)
    hard = cfg["academic_max_with_dean"] + adjustment(db, person.id, "ACADEMIC", ys)
    if used + days > hard:
        raise RuleError("LEAVE_BALANCE",
                        f"Academic duty is at most {hard:g} days in a leave year; {used} are already used or applied for.")
    return days, used + days > base


def covered_by_leave(db: Session, person_id: int, d: dt.date, statuses=("confirmed",)) -> LeaveApplication | None:
    return db.scalar(select(LeaveApplication).where(
        LeaveApplication.person_id == person_id, LeaveApplication.status.in_(statuses),
        LeaveApplication.from_date <= d, LeaveApplication.to_date >= d))


__all__ = ["DEFAULTS", "LEAVE_TYPES", "settings", "leave_year", "semester", "balances", "check_application",
           "RuleError", "covered_by_leave", "holidays_between", "is_working_day"]
