"""Leave: scholar applies -> supervisor approves -> (Dean R&I for academic duty beyond 30 days)
-> central admin confirms. Confirmed leave marks the days as L."""
from __future__ import annotations

import base64
import binascii
import datetime as dt
import os
import secrets

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..clock import Clock, get_clock
from ..config import get_settings
from ..daybook import evaluate_day
from ..db import get_db
from ..models import DayReview, LeaveApplication, Person
from ..rules import LEAVE_TYPES, RuleError, balances, check_application
from ..security import Actor, actor, api_error, audit, require_role, require_scholar

router = APIRouter(prefix="/leave", tags=["leave"])
ALLOWED_EXT = {".pdf", ".jpg", ".jpeg", ".png"}
STATUS_TEXT = {
    "pending_supervisor": "Waiting for supervisor",
    "pending_dean": "Waiting for Dean (R&I)",
    "pending_admin": "Waiting for admin confirmation",
    "confirmed": "Confirmed",
    "declined": "Declined",
    "returned": "Returned by admin",
    "withdrawn": "Withdrawn",
    "cancelled": "Cancelled",
}


def leave_json(lv: LeaveApplication, with_person: bool = False) -> dict:
    out = {
        "id": lv.id, "leave_type": lv.leave_type, "type_label": LEAVE_TYPES[lv.leave_type],
        "from_date": lv.from_date.isoformat(), "to_date": lv.to_date.isoformat(), "days": lv.days,
        "reason": lv.reason, "address": lv.address, "contact": lv.contact,
        "has_attachment": bool(lv.attachment_path), "needs_dean": lv.needs_dean,
        "status": lv.status, "status_text": STATUS_TEXT[lv.status],
        "supervisor_note": lv.supervisor_note, "dean_note": lv.dean_note, "admin_note": lv.admin_note,
        "created_at": lv.created_at.isoformat(timespec="minutes"),
    }
    if with_person:
        p = lv.person
        out["scholar"] = {"name": p.name, "email": p.email, "roll_no": p.roll_no, "programme": p.programme,
                          "department": p.department, "funding": p.funding}
    return out


@router.get("/types")
def types():
    return [{"code": k, "label": v} for k, v in LEAVE_TYPES.items()]


@router.get("/mine")
def mine(a: Actor = Depends(require_scholar), db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    rows = db.scalars(select(LeaveApplication).where(LeaveApplication.person_id == a.person.id)
                      .order_by(LeaveApplication.from_date.desc())).all()
    return {"applications": [leave_json(x) for x in rows], "balances": balances(db, a.person, clk.now().date())}


class LeaveIn(BaseModel):
    leave_type: str
    from_date: dt.date
    to_date: dt.date
    reason: str = Field(min_length=3, max_length=2000)
    address: str = Field(default="", max_length=300)
    contact: str = Field(default="", max_length=40)
    attachment_name: str = Field(default="", max_length=120)
    attachment_base64: str = ""


def _save_attachment(person_id: int, name: str, b64: str) -> str:
    s = get_settings()
    ext = os.path.splitext(name)[1].lower()
    if ext not in ALLOWED_EXT:
        raise api_error(400, "LEAVE_ATTACHMENT", "Attach a PDF, JPG or PNG file.")
    try:
        data = base64.b64decode(b64, validate=True)
    except (binascii.Error, ValueError):
        raise api_error(400, "LEAVE_ATTACHMENT", "The attachment could not be read.")
    if len(data) > s.max_upload_mb * 1024 * 1024:
        raise api_error(400, "LEAVE_ATTACHMENT", f"Attachment must be under {s.max_upload_mb} MB.")
    folder = os.path.join(s.upload_dir, "leave")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{person_id}_{secrets.token_hex(8)}{ext}")
    with open(path, "wb") as fh:
        fh.write(data)
    return path


@router.post("")
def apply(body: LeaveIn, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
          clk: Clock = Depends(get_clock)):
    now = clk.now()
    has_att = bool(body.attachment_base64 and body.attachment_name)
    try:
        days, needs_dean = check_application(db, a.person, body.leave_type, body.from_date, body.to_date,
                                             now.date(), has_att)
    except RuleError as e:
        raise api_error(400, e.code, e.message)
    path = _save_attachment(a.person.id, body.attachment_name, body.attachment_base64) if has_att else ""
    lv = LeaveApplication(person_id=a.person.id, leave_type=body.leave_type, from_date=body.from_date,
                          to_date=body.to_date, days=days, reason=body.reason.strip(), address=body.address.strip(),
                          contact=body.contact.strip(), attachment_path=path, needs_dean=needs_dean,
                          status="pending_supervisor", created_at=now)
    db.add(lv)
    db.flush()
    audit(db, now, a.person.email, "leave.apply", str(lv.id), f"{body.leave_type} {body.from_date}..{body.to_date}")
    db.commit()
    return leave_json(lv)


@router.post("/{leave_id}/withdraw")
def withdraw(leave_id: int, a: Actor = Depends(require_scholar), db: Session = Depends(get_db),
             clk: Clock = Depends(get_clock)):
    lv = db.get(LeaveApplication, leave_id)
    if lv is None or lv.person_id != a.person.id:
        raise api_error(404, "NOT_FOUND", "Leave application not found.")
    if lv.status not in ("pending_supervisor", "pending_dean", "pending_admin"):
        raise api_error(409, "LEAVE_DECIDED", "Only applications not yet confirmed can be withdrawn.")
    lv.status = "withdrawn"
    audit(db, clk.now(), a.person.email, "leave.withdraw", str(lv.id))
    db.commit()
    return leave_json(lv)


def _can_view(p: Person, lv: LeaveApplication) -> bool:
    return (p.id == lv.person_id or p.has("admin") or p.has("dean_ri")
            or (p.has("supervisor") and lv.person.supervisor_email.lower() == p.email)
            or (p.has("hod") and lv.person.department == p.department))


@router.get("/{leave_id}/attachment")
def attachment(leave_id: int, a: Actor = Depends(actor), db: Session = Depends(get_db)):
    lv = db.get(LeaveApplication, leave_id)
    if lv is None or not _can_view(a.person, lv) or not lv.attachment_path:
        raise api_error(404, "NOT_FOUND", "Not found.")
    return FileResponse(lv.attachment_path)


# ---------------------------------------------------------------- approvers

@router.get("/queue")
def queue(role: str, a: Actor = Depends(actor), db: Session = Depends(get_db)):
    """Applications waiting for this approver. role = supervisor | dean | admin."""
    p = a.person
    q = select(LeaveApplication).join(Person, Person.id == LeaveApplication.person_id)
    if role == "supervisor" and p.has("supervisor"):
        q = q.where(LeaveApplication.status == "pending_supervisor", Person.supervisor_email == p.email)
    elif role == "dean" and p.has("dean_ri"):
        q = q.where(LeaveApplication.status == "pending_dean")
    elif role == "admin" and p.has("admin"):
        q = q.where(LeaveApplication.status == "pending_admin")
    else:
        raise api_error(403, "FORBIDDEN", "You do not have permission for this.")
    rows = db.scalars(q.order_by(LeaveApplication.from_date)).all()
    out = []
    for lv in rows:
        j = leave_json(lv, with_person=True)
        j["balances"] = balances(db, lv.person, lv.from_date)
        out.append(j)
    return out


class DecisionIn(BaseModel):
    approve: bool
    note: str = Field(default="", max_length=1000)


@router.post("/{leave_id}/approve")
def supervisor_decide(leave_id: int, body: DecisionIn, a: Actor = Depends(require_role("supervisor")),
                      db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    now = clk.now()
    lv = db.get(LeaveApplication, leave_id)
    if lv is None or lv.person.supervisor_email.lower() != a.person.email:
        raise api_error(404, "NOT_FOUND", "Leave application not found.")
    if lv.status != "pending_supervisor":
        raise api_error(409, "LEAVE_STATE", "This application is not waiting for you.")
    lv.supervisor_note, lv.approved_by, lv.approved_at = body.note.strip(), a.person.email, now
    if not body.approve:
        lv.status = "declined"
    else:
        lv.status = "pending_dean" if lv.needs_dean else "pending_admin"
    audit(db, now, a.person.email, "leave.supervisor", str(lv.id), "approve" if body.approve else "decline")
    db.commit()
    return leave_json(lv)


@router.post("/{leave_id}/dean")
def dean_decide(leave_id: int, body: DecisionIn, a: Actor = Depends(require_role("dean_ri")),
                db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    now = clk.now()
    lv = db.get(LeaveApplication, leave_id)
    if lv is None:
        raise api_error(404, "NOT_FOUND", "Leave application not found.")
    if lv.status != "pending_dean":
        raise api_error(409, "LEAVE_STATE", "This application is not waiting for the Dean (R&I).")
    lv.dean_note, lv.dean_by, lv.dean_at = body.note.strip(), a.person.email, now
    lv.status = "pending_admin" if body.approve else "declined"
    audit(db, now, a.person.email, "leave.dean", str(lv.id), "approve" if body.approve else "decline")
    db.commit()
    return leave_json(lv)


class ConfirmIn(BaseModel):
    confirm: bool
    note: str = Field(default="", max_length=1000)


@router.post("/{leave_id}/confirm")
def admin_confirm(leave_id: int, body: ConfirmIn, a: Actor = Depends(require_role("admin")),
                  db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    now = clk.now()
    lv = db.get(LeaveApplication, leave_id)
    if lv is None:
        raise api_error(404, "NOT_FOUND", "Leave application not found.")
    if lv.status != "pending_admin":
        raise api_error(409, "LEAVE_STATE", "This application is not waiting for confirmation.")
    if not body.confirm:
        if not body.note.strip():
            raise api_error(400, "NOTE_REQUIRED", "Give a note when returning an application.")
        lv.status, lv.admin_note = "returned", body.note.strip()
    else:
        # Re-check the rules: balances may have changed since the scholar applied.
        try:
            check_application(db, lv.person, lv.leave_type, lv.from_date, lv.to_date, lv.from_date,
                              bool(lv.attachment_path), exclude_id=lv.id)
        except RuleError as e:
            if e.code != "LEAVE_OVERLAP":
                raise api_error(409, e.code, "Cannot confirm: " + e.message)
        lv.status, lv.admin_note = "confirmed", body.note.strip()
        # Days already sent for review become leave
        for r in db.scalars(select(DayReview).where(
                DayReview.person_id == lv.person_id, DayReview.date >= lv.from_date,
                DayReview.date <= lv.to_date, DayReview.status.in_(("pending", "absent")))).all():
            r.status, r.decided_by, r.decided_at, r.remark = "leave", a.person.email, now, f"Leave #{lv.id}"
    lv.confirmed_by, lv.confirmed_at = a.person.email, now
    audit(db, now, a.person.email, "leave.admin", str(lv.id), "confirm" if body.confirm else "return")
    db.commit()
    return leave_json(lv)


@router.post("/{leave_id}/cancel")
def admin_cancel(leave_id: int, body: DecisionIn, a: Actor = Depends(require_role("admin")),
                 db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    now = clk.now()
    lv = db.get(LeaveApplication, leave_id)
    if lv is None or lv.status != "confirmed":
        raise api_error(409, "LEAVE_STATE", "Only confirmed leave can be cancelled.")
    lv.status, lv.admin_note = "cancelled", body.note.strip() or lv.admin_note
    for r in db.scalars(select(DayReview).where(
            DayReview.person_id == lv.person_id, DayReview.date >= lv.from_date,
            DayReview.date <= lv.to_date, DayReview.status == "leave")).all():
        r.status, r.decided_by, r.decided_at, r.remark = "pending", "", None, ""
    audit(db, now, a.person.email, "leave.cancel", str(lv.id), body.note)
    db.commit()
    # Past days that were skipped because of this leave now go to review
    d = lv.from_date
    while d <= min(lv.to_date, now.date()):
        evaluate_day(db, d, now)
        d += dt.timedelta(days=1)
    return leave_json(lv)
