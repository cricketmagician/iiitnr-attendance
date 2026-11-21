"""Scholar side: phone registration, today's sessions, marking, monthly view, reasons."""
from __future__ import annotations

import datetime as dt
import json
from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..clock import Clock, get_clock, holidays_between, is_working_day, last_window_end, open_window, windows
from ..config import get_settings
from ..daybook import MIN_SESSIONS, month_grid
from ..db import get_db
from ..face_service import generate_face_embedding, parse_and_validate_face_image, verify_face
from ..qr_service import generate_guard_qr, verify_guard_qr
from ..models import Attempt, DayReview, Device, Mark, Person
from ..rules import covered_by_leave
from ..security import (Actor, actor, api_error, audit, check_signature, client_ip, current_person, on_campus,
                        require_scholar)

router = APIRouter(prefix="/att", tags=["attendance"])


# ---------------------------------------------------------------- who am I

@router.get("/me")
def me(a: Actor = Depends(actor)):
    p = a.person
    return {
        "email": p.email, "name": p.name, "roll_no": p.roll_no, "programme": p.programme,
        "department": p.department, "funding": p.funding,
        "joining_date": p.joining_date.isoformat() if p.joining_date else None,
        "roles": [r.strip() for r in p.roles.split(",") if r.strip()],
        "is_scholar": p.is_scholar,
        "device": {"device_id": a.device.device_id, "status": a.device.status} if a.device else None,
    }


# ---------------------------------------------------------------- device lock

class DeviceIn(BaseModel):
    device_id: str = Field(min_length=8, max_length=64)
    hardware_id: str = Field(min_length=4, max_length=128)
    public_key: str = Field(min_length=40, max_length=200)  # base64 of the 65-byte uncompressed P-256 point
    platform: str = Field(default="", max_length=20)
    model: str = Field(default="", max_length=80)
    reason: str = Field(default="", max_length=300)  # for a phone change: lost, damaged, replaced...


@router.get("/device/status")
def device_status(request: Request, person: Person = Depends(current_person), db: Session = Depends(get_db)):
    """Unsigned: lets the app find out whether this phone is registered, pending or blocked."""
    did = request.headers.get("X-Device-Id", "")
    dev = db.scalar(select(Device).where(Device.device_id == did)) if did else None
    has_active = db.scalar(select(Device.id).where(Device.person_id == person.id, Device.status == "active"))
    if dev is None or dev.person_id != person.id:
        return {"status": "unregistered", "account_has_active_phone": bool(has_active)}
    return {"status": dev.status, "account_has_active_phone": bool(has_active)}


@router.post("/device/register")
async def register_device(body: DeviceIn, request: Request, person: Person = Depends(current_person),
                          db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """First phone: active at once. Any later phone: a change request the central admin approves.
    The request must be signed with the key being registered (proof the phone holds it)."""
    now = clk.now()
    if request.headers.get("X-Device-Id", "") != body.device_id:
        raise api_error(400, "DEVICE_MISMATCH", "Device header does not match.")
    await check_signature(request, db, now, body.public_key, body.device_id)

    same = db.scalar(select(Device).where(Device.device_id == body.device_id))
    if same is not None:
        if same.person_id != person.id:
            raise api_error(409, "DEVICE_TAKEN", "This phone is registered to another scholar.")
        return {"status": same.status}
    other_owner = db.scalar(select(Device).where(
        Device.hardware_id == body.hardware_id, Device.person_id != person.id,
        Device.status.in_(("active", "pending"))))
    if other_owner is not None:
        audit(db, now, person.email, "device.refused_shared", body.hardware_id, f"owner={other_owner.person_id}")
        db.commit()
        raise api_error(409, "DEVICE_TAKEN", "This phone is registered to another scholar. One phone serves one scholar.")

    has_active = db.scalar(select(Device).where(Device.person_id == person.id, Device.status == "active"))
    # Re-install on the same phone (same hardware id) still needs approval: the key changed.
    status = "active" if has_active is None else "pending"
    # Only one pending request at a time
    for old in db.scalars(select(Device).where(Device.person_id == person.id, Device.status == "pending")).all():
        old.status, old.decided_at, old.decided_by = "rejected", now, "superseded"
    dev = Device(person_id=person.id, device_id=body.device_id, hardware_id=body.hardware_id,
                 public_key=body.public_key, platform=body.platform, model=body.model, status=status,
                 reason=body.reason, created_at=now,
                 decided_at=now if status == "active" else None, decided_by="auto" if status == "active" else "")
    db.add(dev)
    audit(db, now, person.email, "device.register", body.device_id, status)
    db.commit()
    return {"status": status}


# ---------------------------------------------------------------- today and schedule

def _today_payload(db: Session, person: Person, now: dt.datetime) -> dict:
    today = now.date()
    hol = holidays_between(db, today, today)
    working = is_working_day(today, hol) or (get_settings().dev_mode and today == dt.date(2026, 11, 21))
    marks = {m.session: m.marked_at.strftime("%H:%M") for m in db.scalars(
        select(Mark).where(Mark.person_id == person.id, Mark.date == today)).all()}
    leave = covered_by_leave(db, person.id, today)
    sessions = []
    for w in windows(db):
        if not working:
            state = "no_session"
        elif w.session in marks:
            state = "marked"
        elif now.time() < w.start_time:
            state = "upcoming"
        elif now.time() <= w.end_time:
            state = "open"
        else:
            state = "missed"
        sessions.append({"session": w.session, "label": w.label, "start": w.start_time.strftime("%H:%M"),
                         "end": w.end_time.strftime("%H:%M"), "state": state, "marked_at": marks.get(w.session)})
    return {
        "date": today.isoformat(), "server_time": now.strftime("%H:%M:%S"), "working_day": working,
        "holiday": hol.get(today), "on_leave": leave.leave_type if leave else None,
        "sessions": sessions, "marked_count": len(marks), "required": MIN_SESSIONS,
        "day_complete": len(marks) >= MIN_SESSIONS or leave is not None,
    }


@router.get("/today")
def today(a: Actor = Depends(require_scholar), db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    return _today_payload(db, a.person, clk.now())


@router.get("/schedule")
def schedule(days: int = 14, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
             clk: Clock = Depends(get_clock)):
    """Working days and windows for the next `days` days, so the app can schedule reminders.
    Days on confirmed leave are left out."""
    now = clk.now()
    start = now.date()
    end = start + dt.timedelta(days=min(max(days, 1), 31))
    hol = holidays_between(db, start, end)
    ws = [{"session": w.session, "label": w.label, "start": w.start_time.strftime("%H:%M"),
           "end": w.end_time.strftime("%H:%M")} for w in windows(db)]
    marked_today = {m.session for m in db.scalars(
        select(Mark).where(Mark.person_id == a.person.id, Mark.date == start)).all()}
    out, d = [], start
    while d <= end:
        is_work = is_working_day(d, hol) or (get_settings().dev_mode and d == dt.date(2026, 11, 21))
        if is_work and covered_by_leave(db, a.person.id, d) is None:
            out.append({"date": d.isoformat(),
                        "marked": sorted(marked_today) if d == start else []})
        d += dt.timedelta(days=1)
    return {"windows": ws, "days": out}


# ---------------------------------------------------------------- marking

def _refuse(db: Session, person: Person, now: dt.datetime, session: str, reason: str, ip: str, device_id: str,
            status: int, message: str):
    db.add(Attempt(person_id=person.id, at=now, session=session, reason=reason, client_ip=ip, device_id=device_id))
    db.commit()
    raise api_error(status, reason, message)


class MarkIn(BaseModel):
    face_image: Optional[str] = None
    qr_token: Optional[str] = None


@router.get("/guard/qr")
def guard_qr(db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """Provides current dynamic 3-second rotating QR token for Guard / Kiosk screen."""
    now = clk.now()
    w = open_window(db, now)
    session_name = w.session if w else "morning"
    data = generate_guard_qr(session_name)
    data["session_label"] = w.label if w else "Morning"
    data["window_open"] = w is not None
    return data


class EnrolFaceIn(BaseModel):
    image: str


@router.post("/face/enrol")
def enrol_face(body: EnrolFaceIn, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
               clk: Clock = Depends(get_clock)):
    """Supervised face enrolment: generates and stores the reference face embedding."""
    try:
        raw = parse_and_validate_face_image(body.image)
        vec = generate_face_embedding(raw)
    except ValueError as e:
        raise api_error(400, "INVALID_FACE_IMAGE", str(e))

    p = a.person
    p.face_embedding = json.dumps(vec)
    p.face_enrolled_at = clk.now()
    audit(db, clk.now(), p.email, "FACE_ENROLLED", subject=p.email, detail="Enrolled reference face template")
    db.commit()
    return {"ok": True, "message": "Reference face template enrolled successfully."}


class TestVerifyIn(BaseModel):
    email: str = "scholar1@iiitnr.edu.in"
    face_image: str
    qr_token: Optional[str] = None
    device_id: Optional[str] = None
    platform: Optional[str] = "iOS"
    model: Optional[str] = "iPhone"


@router.post("/face/test-verify")
def test_verify_face(body: TestVerifyIn, db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """Open test verification endpoint for web/iOS testers to test Device Lock + Guard QR + AI Face match."""
    p = db.scalar(select(Person).where(Person.email == body.email.lower()))
    if p is None:
        raise api_error(404, "PERSON_NOT_FOUND", f"Scholar {body.email} not found.")

    # 1. Device Lock Verification & Auto-Registration
    dev_status = "Unregistered"
    active_dev = db.scalar(select(Device).where(Device.person_id == p.id, Device.status == "active"))
    device_locked_to_other = False
    if active_dev:
        if body.device_id and active_dev.device_id != body.device_id:
            device_locked_to_other = True
            dev_status = f"Locked to {active_dev.model or active_dev.platform} ({active_dev.device_id[:8]}...)"
        else:
            dev_status = f"Verified {active_dev.model or active_dev.platform}"
    else:
        # First device for this scholar: Auto-register and lock!
        did = body.device_id or f"web-ios-{p.id}"
        new_dev = Device(person_id=p.id, device_id=did, hardware_id=did,
                         public_key="p256_ios_key", platform=body.platform or "iOS",
                         model=body.model or "Apple iPhone", status="active",
                         reason="Initial phone registration", created_at=clk.now(),
                         decided_at=clk.now(), decided_by="auto")
        db.add(new_dev)
        audit(db, clk.now(), p.email, "device.register", did, "active")
        db.commit()
        dev_status = f"Registered & Locked ({body.model or 'Apple iPhone'})"

    # 2. Guard 3-second Rotating Dynamic QR Verification
    qr_status = "Skipped"
    if body.qr_token:
        w = open_window(db, clk.now())
        session = w.session if w else "morning"
        ok, reason = verify_guard_qr(body.qr_token, session)
        if not ok:
            return {
                "ok": False,
                "action": "INVALID_QR",
                "device_status": dev_status,
                "match_pct": 0,
                "message": f"❌ Guard QR Verification Failed: {reason}"
            }
        qr_status = "Verified"
    else:
        return {
            "ok": False,
            "action": "QR_REQUIRED",
            "device_status": dev_status,
            "match_pct": 0,
            "message": "❌ Guard QR Required: Please scan the live 3-second Guard QR code on the screen."
        }

    # 3. AI Face Biometrics
    try:
        raw = parse_and_validate_face_image(body.face_image)
        vec = generate_face_embedding(raw)
    except ValueError as e:
        raise api_error(400, "INVALID_FACE_IMAGE", str(e))

    if p.face_embedding is None:
        # Enrol this face for scholar
        p.face_embedding = json.dumps(vec)
        p.face_enrolled_at = clk.now()
        audit(db, clk.now(), p.email, "FACE_ENROLLED", subject=p.email, detail="Enrolled reference face via Web Portal")
        db.commit()
        return {"ok": True, "action": "ENROLLED", "match_pct": 100, "device_status": dev_status,
                "message": f"📸 New Phone Registered ({dev_status}) + Face Enrolled (100%) + Guard QR Verified for {p.name or p.email}!"}
    else:
        # Verify face against enrolled reference
        is_match, score, reason = verify_face(p.face_embedding, body.face_image)
        pct = int(score * 100)
        
        # If device is locked to another phone, flag it clearly
        if device_locked_to_other:
            msg = f"❌ PROXY DETECTED: Phone is NOT authorized ({dev_status})"
            if not is_match:
                msg += f" + Face Mismatch ({pct}% match)!"
            return {
                "ok": False,
                "action": "DEVICE_MISMATCH",
                "device_status": dev_status,
                "match_pct": pct,
                "message": msg
            }

        return {
            "ok": is_match,
            "action": "VERIFIED" if is_match else "MISMATCH",
            "device_status": dev_status,
            "match_pct": pct,
            "message": f"✅ Phone Verified + AI Face Verified ({pct}% Match) + Guard QR Verified!" if is_match else f"❌ Face Mismatch ({pct}% Match): Face does not match registered scholar."
        }



@router.post("/mark")
def mark(request: Request, body: Optional[MarkIn] = None, a: Actor = Depends(require_scholar),
         db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """Authoritative server-side attendance marking.
    Checks: ECDSA device key signature, campus network, session time window,
    working day, not already marked, and AI face verification if enrolled."""
    now = clk.now()
    p, dev = a.person, a.device
    ip = client_ip(request)
    today = now.date()
    if not (is_working_day(today, holidays_between(db, today, today)) or (get_settings().dev_mode and today == dt.date(2026, 11, 21))):
        _refuse(db, p, now, "", "NOT_WORKING_DAY", ip, dev.device_id, 409, "There is no attendance today.")
    w = open_window(db, now)
    if w is None:
        _refuse(db, p, now, "", "OUTSIDE_WINDOW", ip, dev.device_id, 409,
                "Attendance is not open now. Windows: " +
                ", ".join(f"{x.start_time:%I:%M %p}–{x.end_time:%I:%M %p}" for x in windows(db)) + ".")
    if not on_campus(db, ip):
        _refuse(db, p, now, w.session, "NOT_ON_CAMPUS", ip, dev.device_id, 403,
                "Connect to the campus Wi-Fi to mark attendance.")

    # Guard 3-second Rotating Dynamic QR Verification Check
    qr_status = "Skipped"
    if body and body.qr_token:
        ok, reason = verify_guard_qr(body.qr_token, w.session)
        if not ok:
            _refuse(db, p, now, w.session, "INVALID_GUARD_QR", ip, dev.device_id, 403, reason)
        qr_status = "Verified"

    # AI Face Verification Check
    face_status = "Skipped"
    match_pct = 0
    if body and body.face_image:
        try:
            raw = parse_and_validate_face_image(body.face_image)
            vec = generate_face_embedding(raw)
            if p.face_embedding is None:
                # First time: Enrol this selfie as scholar's registered reference face template!
                p.face_embedding = json.dumps(vec)
                p.face_enrolled_at = now
                audit(db, now, p.email, "FACE_AUTO_ENROLLED", subject=p.email,
                      detail="Enrolled reference face template from initial selfie")
                face_status = "Enrolled"
                match_pct = 100
            else:
                # Subsequent times: Verify face against enrolled reference template!
                is_match, score, reason = verify_face(p.face_embedding, body.face_image)
                if not is_match:
                    _refuse(db, p, now, w.session, "FACE_MISMATCH", ip, dev.device_id, 403,
                            f"Face Mismatch ({int(score * 100)}% match): Face does not match registered scholar.")
                face_status = "Verified"
                match_pct = int(score * 100)
        except ValueError as e:
            _refuse(db, p, now, w.session, "INVALID_FACE_IMAGE", ip, dev.device_id, 400, str(e))
    elif p.face_embedding is not None:
        _refuse(db, p, now, w.session, "FACE_REQUIRED", ip, dev.device_id, 400,
                "Live face capture is required for attendance.")

    if db.scalar(select(Mark.id).where(Mark.person_id == p.id, Mark.date == today, Mark.session == w.session)):
        _refuse(db, p, now, w.session, "ALREADY_MARKED", ip, dev.device_id, 409,
                f"{w.label} attendance is already marked.")
    db.add(Mark(person_id=p.id, date=today, session=w.session, marked_at=now, device_id=dev.device_id, client_ip=ip))
    db.commit()

    qr_note = " & Guard QR Verified" if qr_status == "Verified" else ""
    if face_status == "Enrolled":
        msg = f"📸 Face Enrolled{qr_note}! {w.label}: marked present at {now:%I:%M %p}."
    elif face_status == "Verified":
        msg = f"✅ AI Face Verified ({match_pct}% Match){qr_note}! {w.label}: marked present at {now:%I:%M %p}."
    else:
        msg = f"{w.label}: marked present at {now:%I:%M %p}."

    return {"ok": True, "session": w.session, "label": w.label, "marked_at": now.strftime("%H:%M"),
            "face_status": face_status, "match_pct": match_pct, "qr_status": qr_status,
            "message": msg,
            "today": _today_payload(db, p, now)}


# ---------------------------------------------------------------- month view and reasons

@router.get("/month")
def month(m: str, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
          clk: Clock = Depends(get_clock)):
    try:
        dt.date.fromisoformat(m + "-01")
    except ValueError:
        raise api_error(400, "BAD_MONTH", "Use YYYY-MM.")
    return month_grid(db, [a.person], m, clk.now())[0]


@router.get("/reviews")
def my_reviews(a: Actor = Depends(require_scholar), db: Session = Depends(get_db)):
    rows = db.scalars(select(DayReview).where(DayReview.person_id == a.person.id)
                      .order_by(DayReview.date.desc()).limit(60)).all()
    return [{"id": r.id, "date": r.date.isoformat(), "sessions_marked": r.sessions_marked, "status": r.status,
             "scholar_reason": r.scholar_reason, "remark": r.remark} for r in rows]


class ReasonIn(BaseModel):
    reason: str = Field(min_length=3, max_length=1000)


@router.post("/reviews/{review_id}/reason")
def add_reason(review_id: int, body: ReasonIn, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
               clk: Clock = Depends(get_clock)):
    r = db.get(DayReview, review_id)
    if r is None or r.person_id != a.person.id:
        raise api_error(404, "NOT_FOUND", "Not found.")
    if r.status != "pending":
        raise api_error(409, "DECIDED", "The admin has already decided this day.")
    r.scholar_reason = body.reason.strip()
    audit(db, clk.now(), a.person.email, "review.reason", str(r.id))
    db.commit()
    return {"ok": True}


@router.get("/day-closes")
def day_closes(db: Session = Depends(get_db)):
    return {"last_window_end": last_window_end(db).strftime("%H:%M")}
