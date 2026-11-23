"""Scholar side: phone registration, today's sessions, marking, monthly view, reasons."""
from __future__ import annotations

import datetime as dt
import hmac
import json
import os
import secrets
import time
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..clock import Clock, get_clock, holidays_between, is_working_day, last_window_end, open_window, windows
from ..config import get_settings
from ..daybook import MIN_SESSIONS, month_grid
from ..db import get_db
from ..face_service import generate_face_embedding, liveness_score, parse_and_validate_face_image, verify_face
from ..qr_service import ble_beacon, generate_guard_qr, verify_ble, verify_guard_qr
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
        "roles": p.role_list,
        "is_scholar": p.is_scholar,
        "supervisor_email": p.supervisor_email, "phone": p.phone or "",
        # none | pending | approved | rejected. A scholar who is not approved sees the registration screens.
        "registration": {"status": p.registration_status or "approved", "note": p.registration_note or "",
                         "needed": p.needs_registration},
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
    if not get_settings().enforce_device_lock:
        return {"status": "active", "account_has_active_phone": False}
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
    s = get_settings()

    # When device lock is not enforced, auto-activate any device registration immediately
    if not s.enforce_device_lock:
        dev = db.scalar(select(Device).where(Device.device_id == body.device_id))
        if dev is None:
            dev = Device(person_id=person.id, device_id=body.device_id, hardware_id=body.hardware_id,
                         public_key=body.public_key, platform=body.platform, model=body.model, status="active",
                         reason=body.reason or "Auto-registered for testing", created_at=now,
                         decided_at=now, decided_by="auto")
            db.add(dev)
        else:
            dev.person_id = person.id
            dev.status = "active"
        db.commit()
        return {"status": "active"}

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
    working = is_working_day(today, hol) or get_settings().dev_mode
    marks = {m.session: m.marked_at.strftime("%H:%M") for m in db.scalars(
        select(Mark).where(Mark.person_id == person.id, Mark.date == today)).all()}
    leave = covered_by_leave(db, person.id, today)
    active_win = open_window(db, now)
    found_dev_open = False
    sessions = []
    for w in windows(db):
        if not working:
            state = "no_session"
        elif w.session in marks:
            state = "marked"
        elif get_settings().dev_mode and not found_dev_open:
            state = "open"
            found_dev_open = True
        elif active_win and active_win.session == w.session:
            state = "open"
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
        is_work = is_working_day(d, hol)
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
    # Bluetooth beacon the phone heard from the guard desk, and its signal strength
    ble_uuid: Optional[str] = Field(default=None, max_length=40)
    ble_rssi: Optional[int] = Field(default=None, ge=-127, le=20)


def ble_required() -> bool:
    s = get_settings()
    return s.require_ble if s.require_ble is not None else not s.dev_mode


def _save_selfie(person_id: int, day: dt.date, session: str, raw: bytes) -> str:
    """Keep a small copy of the attendance selfie for the guard feed and the office."""
    s = get_settings()
    if not s.keep_mark_selfies:
        return ""
    data = raw
    try:
        import cv2
        import numpy as np
        img = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
        if img is not None:
            h, w = img.shape[:2]
            scale = 320 / max(h, w)
            if scale < 1:
                img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
            ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 80])
            if ok:
                data = buf.tobytes()
    except Exception:
        pass
    folder = os.path.join(s.upload_dir, "selfies", day.isoformat())
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{person_id}_{session}_{secrets.token_hex(4)}.jpg")
    with open(path, "wb") as fh:
        fh.write(data)
    return path


def _kiosk_allowed(request: Request, db: Session) -> bool:
    """The live QR is shown only on the guard kiosk (X-Kiosk-Key) or to a logged-in admin/guard.
    Scholars must never be able to fetch it, or they could mark from anywhere."""
    if get_settings().dev_mode:  # testing: any screen may act as the kiosk
        return True
    key = get_settings().kiosk_key
    sent = request.headers.get("X-Kiosk-Key", "")
    if key and sent and hmac.compare_digest(sent.encode(), key.encode()):
        return True
    if request.headers.get("Authorization", "").startswith("Bearer "):
        try:
            p = current_person(request, db)
        except HTTPException:
            return False
        return p.has("admin") or p.has("guard")
    return False


@router.get("/guard/qr")
def guard_qr(request: Request, db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """Current rotating QR token for the Guard / Kiosk screen (kiosk key or admin/guard login)."""
    if not _kiosk_allowed(request, db):
        raise api_error(403, "KIOSK_ONLY", "The guard QR is shown only on the guard desk kiosk.")
    now = clk.now()
    w = open_window(db, now)
    if get_settings().dev_mode and not w:
        wins = windows(db)
        if wins:
            w = wins[0]
    session_name = w.session if w else "morning"
    data = generate_guard_qr(session_name)
    data["session_label"] = w.label if w else "Morning"
    data["window_open"] = w is not None
    data["ble"] = ble_beacon()
    return data


# ---------------------------------------------------------------- guard live feed

SESSION_LABELS = {"M": "Morning", "A": "Afternoon", "E": "Evening"}


def _guard_or_403(request: Request, db: Session) -> str:
    """Who is acting at the guard desk: the guard/admin email, or 'kiosk' for the kiosk key."""
    if not _kiosk_allowed(request, db):
        raise api_error(403, "KIOSK_ONLY", "Only the guard desk can see this.")
    if request.headers.get("Authorization", "").startswith("Bearer "):
        try:
            return current_person(request, db).email
        except HTTPException:
            pass
    return "kiosk"


def mark_json(m: Mark) -> dict:
    p = m.person
    return {
        "id": m.id, "name": p.name, "roll_no": p.roll_no, "programme": p.programme, "department": p.department,
        "session": m.session, "session_label": SESSION_LABELS.get(m.session, m.session),
        "time": m.marked_at.strftime("%H:%M:%S"), "near_gate": m.near_gate, "rssi": m.ble_rssi,
        "proof": "bluetooth" if m.near_gate else ("qr" if m.used_qr else "none"),
        "has_selfie": bool(m.selfie_path), "flagged": m.flagged_at is not None, "flag_note": m.flag_note,
        "flagged_by": m.flagged_by, "live_score": m.live_score,
    }


@router.get("/guard/feed")
def guard_feed(request: Request, db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """Latest marks today, newest first, so the guard can see who just marked."""
    _guard_or_403(request, db)
    today = clk.now().date()
    rows = db.scalars(select(Mark).where(Mark.date == today).order_by(Mark.marked_at.desc(), Mark.id.desc())
                      .limit(40)).all()
    return {"date": today.isoformat(), "marks": [mark_json(m) for m in rows]}


@router.get("/guard/marks/{mark_id}/selfie")
def guard_selfie(mark_id: int, request: Request, db: Session = Depends(get_db)):
    _guard_or_403(request, db)
    m = db.get(Mark, mark_id)
    if m is None or not m.selfie_path or not os.path.exists(m.selfie_path):
        raise api_error(404, "NO_SELFIE", "No photo for this mark.")
    return FileResponse(m.selfie_path, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=3600"})


class FlagIn(BaseModel):
    note: str = Field(default="", max_length=300)


FLAG_PREFIX = "Guard flagged"


def _send_to_office(db: Session, person_id: int, day: dt.date, session: str, now: dt.datetime, remark: str,
                    exclude_mark: int | None = None) -> None:
    """Put the day in the office's review list with a note (or add the note to an open review)."""
    db.flush()
    r = db.scalar(select(DayReview).where(DayReview.person_id == person_id, DayReview.date == day))
    if r is None:
        q = select(Mark).where(Mark.person_id == person_id, Mark.date == day, Mark.flagged_at.is_(None))
        if exclude_mark is not None:
            q = q.where(Mark.id != exclude_mark)
        counted = "".join(sorted((x.session for x in db.scalars(q).all()), key="MAE".index))
        db.add(DayReview(person_id=person_id, date=day, sessions_marked=counted, status="pending",
                         remark=remark, created_at=now))
    else:
        r.status = "pending"
        r.remark = (r.remark + "\n" if r.remark else "") + remark


@router.post("/guard/marks/{mark_id}/flag")
def flag_mark(mark_id: int, body: FlagIn, request: Request, db: Session = Depends(get_db),
              clk: Clock = Depends(get_clock)):
    """The guard saw nobody at the desk for this mark. It stops counting and goes to the office."""
    who = _guard_or_403(request, db)
    now = clk.now()
    m = db.get(Mark, mark_id)
    if m is None:
        raise api_error(404, "NOT_FOUND", "No such mark.")
    if m.flagged_at is None:
        m.flagged_at, m.flagged_by, m.flag_note = now, who, body.note.strip()
        remark = f"{FLAG_PREFIX} {SESSION_LABELS.get(m.session, m.session)} mark at {m.marked_at:%H:%M}" + \
                 (f": {body.note.strip()}" if body.note.strip() else ".")
        _send_to_office(db, m.person_id, m.date, m.session, now, remark, exclude_mark=m.id)
        audit(db, now, who, "mark.flag", str(m.id), body.note.strip())
        db.commit()
    return mark_json(m)


@router.post("/guard/marks/{mark_id}/unflag")
def unflag_mark(mark_id: int, request: Request, db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    """Undo a flag tapped by mistake (only while the office has not decided)."""
    who = _guard_or_403(request, db)
    now = clk.now()
    m = db.get(Mark, mark_id)
    if m is None:
        raise api_error(404, "NOT_FOUND", "No such mark.")
    if m.flagged_at is not None:
        r = db.scalar(select(DayReview).where(DayReview.person_id == m.person_id, DayReview.date == m.date))
        if r is not None and r.status != "pending":
            raise api_error(409, "ALREADY_DECIDED", "The office has already decided this day.")
        m.flagged_at, m.flagged_by, m.flag_note = None, "", ""
        if r is not None and r.remark.startswith(FLAG_PREFIX) and "\n" not in r.remark:
            db.delete(r)
        audit(db, now, who, "mark.unflag", str(m.id))
        db.commit()
    return mark_json(m)


class EnrolFaceIn(BaseModel):
    image: str


@router.post("/face/enrol")
def enrol_face(body: EnrolFaceIn, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
               clk: Clock = Depends(get_clock)):
    """One-time face enrolment. Changing an enrolled face needs the admin to reset it first
    (POST /admin/face-reset), so nobody can swap in a friend's face."""
    if a.person.face_embedding is not None:
        raise api_error(409, "FACE_ALREADY_ENROLLED",
                        "Your face is already registered. Ask the attendance office to reset it.")
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
    """TESTING ONLY (ATT_DEV_MODE=true): web/iOS testers try Device Lock + Guard QR + Face match without the app.
    Unauthenticated by design, so it does not exist when dev mode is off."""
    if not get_settings().dev_mode:
        raise api_error(404, "NOT_FOUND", "Not Found")
    p = db.scalar(select(Person).where(Person.email == body.email.lower()))
    if p is None:
        raise api_error(404, "PERSON_NOT_FOUND", f"Scholar {body.email} not found.")

    # 1. Device Lock Verification & Auto-Registration
    dev_status = "Unregistered"
    active_dev = db.scalar(select(Device).where(Device.person_id == p.id, Device.status == "active"))
    device_locked_to_other = False
    if active_dev:
        if body.device_id and active_dev.device_id != body.device_id and get_settings().enforce_device_lock:
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
    dev_id = dev.device_id if dev else (request.headers.get("X-Device-Id", "") or "test-device")
    ip = client_ip(request)
    today = now.date()
    if not (is_working_day(today, holidays_between(db, today, today)) or get_settings().dev_mode):
        _refuse(db, p, now, "", "NOT_WORKING_DAY", ip, dev_id, 409, "There is no attendance today.")
    w = open_window(db, now)
    if get_settings().dev_mode:
        marked_sessions = {m.session for m in db.scalars(
            select(Mark).where(Mark.person_id == p.id, Mark.date == today)).all()}
        unmarked = [win for win in windows(db) if win.session not in marked_sessions]
        if unmarked:
            w = unmarked[0]
    if w is None:
        _refuse(db, p, now, "", "OUTSIDE_WINDOW", ip, dev_id, 409,
                "Attendance is not open now. Windows: " +
                ", ".join(f"{x.start_time:%I:%M %p}–{x.end_time:%I:%M %p}" for x in windows(db)) + ".")
    if not on_campus(db, ip) and not get_settings().dev_mode:
        _refuse(db, p, now, w.session, "NOT_ON_CAMPUS", ip, dev_id, 403,
                "Connect to the campus Wi-Fi to mark attendance.")

    # Proof of being at the guard desk: the Bluetooth beacon (normal way), or the guard QR (backup
    # for a phone that cannot find the signal). A video call can carry the QR, so QR marks are
    # labelled and the guard sees them in the live list.
    qr_status = "Skipped"
    near_gate = None
    used_qr = False
    has_ble = bool(body and body.ble_uuid)
    has_qr = bool(body and body.qr_token)
    if has_ble:
        ok, reason = verify_ble(body.ble_uuid, time.time())
        if not ok:
            _refuse(db, p, now, w.session, "BLE_INVALID", ip, dev_id, 403, reason)
        near_gate = True
    if has_qr and not has_ble:
        ok, reason = verify_guard_qr(body.qr_token, w.session)
        if not ok:
            _refuse(db, p, now, w.session, "INVALID_GUARD_QR", ip, dev_id, 403, reason)
        qr_status = "Verified"
        used_qr = True
        near_gate = False
    if not has_ble and not has_qr:
        if get_settings().require_guard_qr or ble_required():
            _refuse(db, p, now, w.session, "PROXIMITY_REQUIRED", ip, dev_id, 403,
                    "Stand near the guard desk with Bluetooth on, or scan the QR on the guard screen.")
        near_gate = False

    # AI Face Verification Check
    face_status = "Skipped"
    raw_selfie = None
    match_pct = 0
    if body and body.face_image:
        try:
            raw = parse_and_validate_face_image(body.face_image)
            raw_selfie = raw
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
                    _refuse(db, p, now, w.session, "FACE_MISMATCH", ip, dev_id, 403,
                            f"Face Mismatch ({int(score * 100)}% match): Face does not match registered scholar.")
                face_status = "Verified"
                match_pct = int(score * 100)
        except ValueError as e:
            _refuse(db, p, now, w.session, "INVALID_FACE_IMAGE", ip, dev_id, 400, str(e))
    elif p.face_embedding is not None or get_settings().require_face:
        _refuse(db, p, now, w.session, "FACE_REQUIRED", ip, dev_id, 400,
                "Live face capture is required for attendance.")

    # Photo / screen check: a printed photo or a phone screen held to the camera
    live = None
    auto_flag = ""
    s = get_settings()
    if raw_selfie and s.liveness_mode in ("review", "reject"):
        live = liveness_score(raw_selfie)
        if live is not None and live < s.liveness_threshold:
            start = dt.datetime.combine(today, dt.time.min)
            failures = db.scalar(select(func.count()).select_from(Attempt).where(
                Attempt.person_id == p.id, Attempt.at >= start, Attempt.session == w.session,
                Attempt.reason == "LIVENESS_FAILED")) or 0
            if s.liveness_mode == "reject" or failures < s.liveness_retries:
                _refuse(db, p, now, w.session, "LIVENESS_FAILED", ip, dev_id, 403,
                        "We could not confirm a live face. Face a light, hold the phone steady and try again.")
            auto_flag = f"Photo check: the selfie looked like a photo or a screen ({int(live * 100)}% live)"

    if db.scalar(select(Mark.id).where(Mark.person_id == p.id, Mark.date == today, Mark.session == w.session)):
        _refuse(db, p, now, w.session, "ALREADY_MARKED", ip, dev_id, 409,
                f"{w.label} attendance is already marked.")
    selfie = _save_selfie(p.id, today, w.session, raw_selfie) if raw_selfie else ""
    db.add(Mark(person_id=p.id, date=today, session=w.session, marked_at=now, device_id=dev_id, client_ip=ip,
                near_gate=near_gate, ble_rssi=body.ble_rssi if body and near_gate else None, used_qr=used_qr,
                selfie_path=selfie,
                live_score=live,
                flagged_at=now if auto_flag else None, flagged_by="auto" if auto_flag else "",
                flag_note=auto_flag))
    if auto_flag:
        _send_to_office(db, p.id, today, w.session, now, auto_flag)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise api_error(409, "ALREADY_MARKED", f"{w.label} attendance is already marked.")

    if auto_flag:
        return {"ok": True, "session": w.session, "label": w.label, "marked_at": now.strftime("%H:%M"),
                "face_status": face_status, "match_pct": match_pct, "qr_status": qr_status, "near_gate": near_gate,
                "sent_to_office": True,
                "message": f"{w.label}: saved, but the photo check failed, so the attendance office will check it.",
                "today": _today_payload(db, p, now)}

    qr_note = " & Guard QR Verified" if qr_status == "Verified" else ""
    if face_status == "Enrolled":
        msg = f"📸 Face Enrolled{qr_note}! {w.label}: marked present at {now:%I:%M %p}."
    elif face_status == "Verified":
        msg = f"✅ AI Face Verified ({match_pct}% Match){qr_note}! {w.label}: marked present at {now:%I:%M %p}."
    else:
        msg = f"{w.label}: marked present at {now:%I:%M %p}."

    return {"ok": True, "session": w.session, "label": w.label, "marked_at": now.strftime("%H:%M"),
            "face_status": face_status, "match_pct": match_pct, "qr_status": qr_status, "near_gate": near_gate,
            "sent_to_office": bool(auto_flag), "live_score": round(live, 3) if live is not None else None,
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
