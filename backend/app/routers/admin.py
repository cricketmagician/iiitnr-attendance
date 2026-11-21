"""Central admin: day reviews, phone changes, leave adjustments, settings, register and exports.
Supervisors and HoDs can read the register for their own scholars / department."""
from __future__ import annotations

import csv
import datetime as dt
import io
import ipaddress

from fastapi import APIRouter, Depends
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ..clock import Clock, get_clock, windows
from ..daybook import evaluate_day, month_grid, scholars
from ..db import get_db
from ..models import (Attempt, CampusNetwork, DayReview, Device, Holiday, LeaveAdjustment, Person, SessionWindow,
                      Setting)
from ..rules import DEFAULTS, leave_year, settings
from ..security import Actor, actor, api_error, audit, require_role

router = APIRouter(prefix="/admin", tags=["admin"])
admin_only = require_role("admin")


# ---------------------------------------------------------------- day reviews

def review_json(r: DayReview, db: Session) -> dict:
    p = r.person
    tries = db.scalars(select(Attempt).where(
        Attempt.person_id == p.id, Attempt.at >= dt.datetime.combine(r.date, dt.time.min),
        Attempt.at < dt.datetime.combine(r.date + dt.timedelta(days=1), dt.time.min))
        .order_by(Attempt.at)).all()
    return {
        "id": r.id, "date": r.date.isoformat(), "status": r.status, "sessions_marked": r.sessions_marked,
        "scholar_reason": r.scholar_reason, "remark": r.remark, "decided_by": r.decided_by,
        "scholar": {"name": p.name, "email": p.email, "roll_no": p.roll_no, "programme": p.programme,
                    "department": p.department},
        "refused_attempts": [{"at": t.at.strftime("%H:%M"), "reason": t.reason} for t in tries],
    }


@router.get("/reviews")
def reviews(status: str = "pending", date: dt.date | None = None, a: Actor = Depends(admin_only),
            db: Session = Depends(get_db)):
    q = select(DayReview).where(DayReview.status == status)
    if date:
        q = q.where(DayReview.date == date)
    rows = db.scalars(q.order_by(DayReview.date.desc(), DayReview.person_id).limit(500)).all()
    return [review_json(r, db) for r in rows]


class ReviewDecision(BaseModel):
    decision: str  # present | absent
    remark: str = Field(default="", max_length=1000)


@router.post("/reviews/{review_id}")
def decide_review(review_id: int, body: ReviewDecision, a: Actor = Depends(admin_only),
                  db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    now = clk.now()
    r = db.get(DayReview, review_id)
    if r is None:
        raise api_error(404, "NOT_FOUND", "Not found.")
    if body.decision not in ("present", "absent"):
        raise api_error(400, "BAD_DECISION", "Decision must be present or absent.")
    if body.decision == "present" and len(body.remark.strip()) < 3:
        raise api_error(400, "REMARK_REQUIRED", "A remark is required to mark a day present.")
    if r.status == "leave":
        raise api_error(409, "ON_LEAVE", "This day is covered by confirmed leave.")
    r.status, r.remark, r.decided_by, r.decided_at = body.decision, body.remark.strip(), a.person.email, now
    audit(db, now, a.person.email, "review.decide", str(r.id), f"{body.decision}: {body.remark}")
    db.commit()
    return review_json(r, db)


@router.post("/run-day-close")
def run_day_close(date: dt.date, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                  clk: Clock = Depends(get_clock)):
    created = evaluate_day(db, date, clk.now())
    return {"date": date.isoformat(), "new_reviews": len(created)}


@router.get("/attempts")
def attempts(date: dt.date, a: Actor = Depends(admin_only), db: Session = Depends(get_db)):
    rows = db.scalars(select(Attempt).where(
        Attempt.at >= dt.datetime.combine(date, dt.time.min),
        Attempt.at < dt.datetime.combine(date + dt.timedelta(days=1), dt.time.min)).order_by(Attempt.at)).all()
    names = {p.id: p.name for p in db.scalars(select(Person)).all()}
    return [{"at": t.at.strftime("%H:%M:%S"), "name": names.get(t.person_id, ""), "session": t.session,
             "reason": t.reason, "ip": t.client_ip} for t in rows]


# ---------------------------------------------------------------- phones

def device_json(d: Device) -> dict:
    return {"id": d.id, "device_id": d.device_id, "scholar": d.person.name, "email": d.person.email, "roll_no": d.person.roll_no,
            "platform": d.platform, "model": d.model, "status": d.status, "reason": d.reason,
            "created_at": d.created_at.isoformat(timespec="minutes")}


@router.get("/devices")
def devices(status: str = "pending", a: Actor = Depends(admin_only), db: Session = Depends(get_db)):
    rows = db.scalars(select(Device).where(Device.status == status).order_by(Device.created_at)).all()
    return [device_json(d) for d in rows]


class DeviceDecision(BaseModel):
    approve: bool
    note: str = Field(default="", max_length=300)


@router.post("/devices/{device_pk}")
def decide_device(device_pk: int, body: DeviceDecision, a: Actor = Depends(admin_only),
                  db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    now = clk.now()
    d = db.get(Device, device_pk)
    if d is None or d.status != "pending":
        raise api_error(409, "DEVICE_STATE", "This phone is not waiting for approval.")
    if body.approve:
        for old in db.scalars(select(Device).where(Device.person_id == d.person_id, Device.status == "active")).all():
            old.status, old.decided_at, old.decided_by = "revoked", now, a.person.email
        d.status = "active"
    else:
        d.status = "rejected"
    d.decided_at, d.decided_by = now, a.person.email
    audit(db, now, a.person.email, "device.decide", d.device_id, f"{d.status} {body.note}")
    db.commit()
    return device_json(d)


@router.post("/devices/{device_pk}/revoke")
def revoke_device(device_pk: int, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                  clk: Clock = Depends(get_clock)):
    now = clk.now()
    d = db.get(Device, device_pk)
    if d is None or d.status != "active":
        raise api_error(409, "DEVICE_STATE", "This phone is not active.")
    d.status, d.decided_at, d.decided_by = "revoked", now, a.person.email
    audit(db, now, a.person.email, "device.revoke", d.device_id)
    db.commit()
    return device_json(d)


# ---------------------------------------------------------------- leave balance adjustments

class AdjustIn(BaseModel):
    email: str
    pool: str  # ORDINARY | MEDICAL | ACADEMIC
    days: float = Field(ge=-60, le=60)
    remark: str = Field(min_length=3, max_length=1000)
    on_date: dt.date | None = None  # any date inside the leave year to adjust; default today


@router.post("/leave-adjustments")
def adjust(body: AdjustIn, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
           clk: Clock = Depends(get_clock)):
    now = clk.now()
    p = db.scalar(select(Person).where(Person.email == body.email.lower().strip()))
    if p is None or not p.is_scholar:
        raise api_error(404, "NOT_FOUND", "Scholar not found.")
    if body.pool not in ("ORDINARY", "MEDICAL", "ACADEMIC"):
        raise api_error(400, "BAD_POOL", "Pool must be ORDINARY, MEDICAL or ACADEMIC.")
    ys, _ = leave_year(p.joining_date or now.date(), body.on_date or now.date())
    adj = LeaveAdjustment(person_id=p.id, pool=body.pool, leave_year_start=ys, days=body.days,
                          remark=body.remark.strip(), by=a.person.email, at=now)
    db.add(adj)
    audit(db, now, a.person.email, "leave.adjust", p.email, f"{body.pool} {body.days:+g} ({ys}) {body.remark}")
    db.commit()
    return {"ok": True, "leave_year_start": ys.isoformat()}


@router.get("/leave-adjustments")
def adjustments(email: str, a: Actor = Depends(admin_only), db: Session = Depends(get_db)):
    p = db.scalar(select(Person).where(Person.email == email.lower().strip()))
    if p is None:
        raise api_error(404, "NOT_FOUND", "Scholar not found.")
    rows = db.scalars(select(LeaveAdjustment).where(LeaveAdjustment.person_id == p.id)
                      .order_by(LeaveAdjustment.at.desc())).all()
    return [{"pool": r.pool, "leave_year_start": r.leave_year_start.isoformat(), "days": r.days,
             "remark": r.remark, "by": r.by, "at": r.at.isoformat(timespec="minutes")} for r in rows]


# ---------------------------------------------------------------- settings

@router.get("/settings")
def get_settings_(a: Actor = Depends(admin_only), db: Session = Depends(get_db)):
    return {
        "rules": settings(db),
        "windows": [{"session": w.session, "label": w.label, "start": w.start_time.strftime("%H:%M"),
                     "end": w.end_time.strftime("%H:%M")} for w in windows(db)],
        "campus_networks": [{"id": n.id, "cidr": n.cidr, "label": n.label}
                            for n in db.scalars(select(CampusNetwork)).all()],
    }


@router.put("/settings/rules")
def put_rules(body: dict, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
              clk: Clock = Depends(get_clock)):
    unknown = set(body) - set(DEFAULTS)
    if unknown:
        raise api_error(400, "UNKNOWN_SETTING", f"Unknown settings: {', '.join(sorted(unknown))}")
    for k, v in body.items():
        if type(v) is not type(DEFAULTS[k]) and not (isinstance(DEFAULTS[k], (int, float)) and isinstance(v, (int, float))):
            raise api_error(400, "BAD_SETTING", f"{k} has the wrong type.")
        row = db.get(Setting, k)
        if row is None:
            db.add(Setting(key=k, value=v))
        else:
            row.value = v
    audit(db, clk.now(), a.person.email, "settings.rules", "", str(body))
    db.commit()
    return settings(db)


class WindowIn(BaseModel):
    session: str
    start: dt.time
    end: dt.time


@router.put("/settings/windows")
def put_windows(body: list[WindowIn], a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                clk: Clock = Depends(get_clock)):
    windows(db)  # make sure defaults exist
    for w in body:
        row = db.get(SessionWindow, w.session)
        if row is None or w.end <= w.start:
            raise api_error(400, "BAD_WINDOW", f"Check the times for session {w.session}.")
        row.start_time, row.end_time = w.start, w.end
    audit(db, clk.now(), a.person.email, "settings.windows", "", str([w.model_dump(mode='json') for w in body]))
    db.commit()
    return [{"session": w.session, "start": w.start_time.strftime("%H:%M"), "end": w.end_time.strftime("%H:%M")}
            for w in windows(db)]


class NetworkIn(BaseModel):
    cidr: str
    label: str = ""


@router.post("/settings/campus-networks")
def add_network(body: NetworkIn, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                clk: Clock = Depends(get_clock)):
    try:
        net = str(ipaddress.ip_network(body.cidr.strip(), strict=False))
    except ValueError:
        raise api_error(400, "BAD_CIDR", "Give a network like 10.20.0.0/16.")
    if db.scalar(select(CampusNetwork).where(CampusNetwork.cidr == net)) is None:
        db.add(CampusNetwork(cidr=net, label=body.label))
        audit(db, clk.now(), a.person.email, "settings.network.add", net, body.label)
        db.commit()
    return {"cidr": net}


@router.delete("/settings/campus-networks/{net_id}")
def del_network(net_id: int, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                clk: Clock = Depends(get_clock)):
    db.execute(delete(CampusNetwork).where(CampusNetwork.id == net_id))
    audit(db, clk.now(), a.person.email, "settings.network.delete", str(net_id))
    db.commit()
    return {"ok": True}


class HolidayIn(BaseModel):
    date: dt.date
    name: str = Field(min_length=2, max_length=120)


@router.get("/holidays")
def holidays(year: int, a: Actor = Depends(actor), db: Session = Depends(get_db)):
    rows = db.scalars(select(Holiday).where(Holiday.date >= dt.date(year, 1, 1),
                                            Holiday.date <= dt.date(year, 12, 31)).order_by(Holiday.date)).all()
    return [{"date": h.date.isoformat(), "name": h.name} for h in rows]


@router.post("/holidays")
def add_holiday(body: HolidayIn, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                clk: Clock = Depends(get_clock)):
    row = db.get(Holiday, body.date)
    if row:
        row.name = body.name
    else:
        db.add(Holiday(date=body.date, name=body.name))
    audit(db, clk.now(), a.person.email, "holiday.set", body.date.isoformat(), body.name)
    db.commit()
    return {"ok": True}


@router.delete("/holidays/{day}")
def del_holiday(day: dt.date, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                clk: Clock = Depends(get_clock)):
    db.execute(delete(Holiday).where(Holiday.date == day))
    audit(db, clk.now(), a.person.email, "holiday.delete", day.isoformat())
    db.commit()
    return {"ok": True}


# ---------------------------------------------------------------- register (admin, HoD, supervisor)

def visible_scholars(db: Session, p: Person, department: str | None) -> list[Person]:
    rows = scholars(db)
    if p.has("admin"):
        pass
    elif p.has("hod"):
        rows = [s for s in rows if s.department == p.department]
    elif p.has("supervisor"):
        rows = [s for s in rows if s.supervisor_email.lower() == p.email]
    else:
        raise api_error(403, "FORBIDDEN", "You do not have permission for this.")
    if department:
        rows = [s for s in rows if s.department == department]
    return rows


@router.get("/register")
def register(m: str, department: str | None = None, format: str = "json", a: Actor = Depends(actor),
             db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    try:
        dt.date.fromisoformat(m + "-01")
    except ValueError:
        raise api_error(400, "BAD_MONTH", "Use YYYY-MM.")
    rows = month_grid(db, visible_scholars(db, a.person, department), m, clk.now())
    if format != "csv":
        return rows
    buf = io.StringIO()
    w = csv.writer(buf)
    if rows:
        dates = [d["date"][-2:] for d in rows[0]["days"]]
        w.writerow(["Roll no", "Name", "Programme", "Department", *dates, "P", "P*", "L", "A", "Awaiting review"])
        for r in rows:
            t = r["totals"]
            w.writerow([r["roll_no"], r["name"], r["programme"], r["department"], *[d["code"] for d in r["days"]],
                        t["P"], t["P*"], t["L"], t["A"], t["R"]])
    return Response(buf.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": f'attachment; filename="attendance-{m}.csv"'})
