"""Scholar registration.

A scholar signs in with their institute Google account, fills in their academic and
contact details, and waits. The Attendance Office checks the details, may correct them,
and approves or rejects. Only approved scholars can mark attendance or apply for leave.

PhD scholars pick a supervisor from the faculty list. MTech scholars have no supervisor.
"""
from __future__ import annotations

import datetime as dt
import re

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..clock import Clock, get_clock
from ..db import get_db
from ..models import Person
from ..security import Actor, actor, api_error, audit, require_role

router = APIRouter(tags=["registration"])

PROGRAMMES = ("PhD", "MTech")
FUNDING = ("institute", "external")
DEFAULT_DEPARTMENTS = ["CSE", "ECE", "DSAI", "S&M"]
PHONE = re.compile(r"^\+?[0-9]{10,13}$")
EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def profile_json(p: Person, supervisors: dict[str, str] | None = None) -> dict:
    sup = p.supervisor_email or ""
    return {
        "id": p.id, "email": p.email, "name": p.name, "roll_no": p.roll_no, "programme": p.programme,
        "department": p.department, "funding": p.funding,
        "joining_date": p.joining_date.isoformat() if p.joining_date else None,
        "batch": p.joining_date.year if p.joining_date else None,
        "supervisor_email": sup, "supervisor_name": (supervisors or {}).get(sup.lower(), "") if sup else "",
        "phone": p.phone or "", "personal_email": p.personal_email or "", "address": p.address or "",
        "status": p.registration_status or "approved", "note": p.registration_note or "",
        "registered_at": p.registered_at.isoformat() if p.registered_at else None,
        "reviewed_by": p.reviewed_by or "",
        "reviewed_at": p.reviewed_at.isoformat() if p.reviewed_at else None,
        "active": p.active, "face_enrolled": p.face_embedding is not None,
    }


def _supervisors(db: Session) -> list[Person]:
    rows = db.scalars(select(Person).where(Person.active).order_by(Person.name)).all()
    return [p for p in rows if p.has("supervisor")]


def _supervisor_names(db: Session) -> dict[str, str]:
    return {p.email.lower(): p.name for p in _supervisors(db)}


def _departments(db: Session) -> list[str]:
    have = {d for d in db.scalars(select(Person.department).distinct()).all() if d}
    return sorted(set(DEFAULT_DEPARTMENTS) | have)


class ProfileIn(BaseModel):
    name: str = Field(min_length=2, max_length=190)
    roll_no: str = Field(min_length=2, max_length=40)
    programme: str
    department: str = Field(min_length=1, max_length=80)
    supervisor_email: str = Field(default="", max_length=190)
    joining_date: dt.date
    funding: str = "institute"
    phone: str = Field(min_length=10, max_length=20)
    personal_email: str = Field(default="", max_length=190)
    address: str = Field(default="", max_length=300)


def _clean(db: Session, body: ProfileIn, person_id: int, today: dt.date) -> dict:
    """Check the form and return the values to store. Raises a 400 with a clear message."""
    def bad(code: str, msg: str):
        return api_error(400, code, msg)

    roll = body.roll_no.strip().upper()
    if body.programme not in PROGRAMMES:
        raise bad("REG_PROGRAMME", "Choose PhD or MTech.")
    if body.funding not in FUNDING:
        raise bad("REG_FUNDING", "Choose institute or external funding.")
    if body.joining_date > today:
        raise bad("REG_JOINING", "Joining date cannot be in the future.")
    phone = re.sub(r"[\s-]", "", body.phone)
    if not PHONE.match(phone):
        raise bad("REG_PHONE", "Enter a valid mobile number.")
    personal = body.personal_email.strip().lower()
    if personal and not EMAIL.match(personal):
        raise bad("REG_EMAIL", "Enter a valid personal email, or leave it empty.")
    taken = db.scalar(select(Person.id).where(func.upper(Person.roll_no) == roll, Person.id != person_id))
    if taken:
        raise bad("REG_ROLL_TAKEN", "This roll number is already registered. Contact the attendance office.")

    sup = ""
    if body.programme == "PhD":
        sup = body.supervisor_email.strip().lower()
        if not sup:
            raise bad("REG_SUPERVISOR", "Choose your supervisor.")
        if sup not in _supervisor_names(db):
            raise bad("REG_SUPERVISOR", "Choose your supervisor from the list.")
    # MTech scholars have no supervisor: their leave goes straight to the attendance office.

    return dict(name=body.name.strip(), roll_no=roll, programme=body.programme, department=body.department.strip(),
                supervisor_email=sup, joining_date=body.joining_date, funding=body.funding, phone=phone,
                personal_email=personal, address=body.address.strip())


# ---------------------------------------------------------------- scholar side

@router.get("/registration/options")
def options(a: Actor = Depends(actor), db: Session = Depends(get_db)):
    """Lists for the form: programmes, departments and faculty who supervise PhD scholars."""
    return {
        "programmes": list(PROGRAMMES),
        "funding": list(FUNDING),
        "departments": _departments(db),
        "supervisors": [{"email": p.email, "name": p.name, "department": p.department} for p in _supervisors(db)],
        "supervisor_needed_for": ["PhD"],
    }


@router.get("/registration")
def my_registration(a: Actor = Depends(actor), db: Session = Depends(get_db)):
    return profile_json(a.person, _supervisor_names(db))


@router.post("/registration")
def submit(body: ProfileIn, a: Actor = Depends(actor), db: Session = Depends(get_db), clk: Clock = Depends(get_clock)):
    p = a.person
    if not p.has("scholar") or p.is_staff:
        raise api_error(403, "REG_NOT_SCHOLAR", "Only scholars register here.")
    if (p.registration_status or "approved") == "approved":
        raise api_error(409, "REG_APPROVED", "You are already registered. Ask the attendance office to change details.")
    now = clk.now()
    for k, v in _clean(db, body, p.id, now.date()).items():
        setattr(p, k, v)
    p.registration_status, p.registration_note, p.registered_at = "pending", "", now
    audit(db, now, p.email, "registration.submit", p.email)
    db.commit()
    return profile_json(p, _supervisor_names(db))


# ---------------------------------------------------------------- attendance office

admin_only = require_role("admin")


@router.get("/admin/scholars")
def list_scholars(status: str = "all", q: str = "", a: Actor = Depends(admin_only), db: Session = Depends(get_db)):
    """Every scholar account with full details. status: pending | approved | rejected | none | all."""
    stmt = select(Person).order_by(Person.registered_at.desc().nullslast(), Person.name)
    if q.strip():
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(or_(func.lower(Person.name).like(like), func.lower(Person.email).like(like),
                              func.lower(Person.roll_no).like(like)))
    people = [p for p in db.scalars(stmt).all() if p.has("scholar") and not p.is_staff]
    counts = {k: 0 for k in ("pending", "approved", "rejected", "none")}
    for p in people:
        counts[p.registration_status or "approved"] = counts.get(p.registration_status or "approved", 0) + 1
    if status != "all":
        people = [p for p in people if (p.registration_status or "approved") == status]
    names = _supervisor_names(db)
    return {"counts": counts, "scholars": [profile_json(p, names) for p in people]}


def _scholar(db: Session, person_id: int) -> Person:
    p = db.get(Person, person_id)
    if p is None or not p.has("scholar"):
        raise api_error(404, "NOT_FOUND", "No such scholar.")
    return p


@router.get("/admin/scholars/{person_id}")
def get_scholar(person_id: int, a: Actor = Depends(admin_only), db: Session = Depends(get_db)):
    return profile_json(_scholar(db, person_id), _supervisor_names(db))


@router.put("/admin/scholars/{person_id}")
def edit_scholar(person_id: int, body: ProfileIn, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
                 clk: Clock = Depends(get_clock)):
    """The office corrects details, before or after approval."""
    now = clk.now()
    p = _scholar(db, person_id)
    before = profile_json(p)
    for k, v in _clean(db, body, p.id, now.date()).items():
        setattr(p, k, v)
    changed = [k for k, v in profile_json(p).items() if before.get(k) != v]
    audit(db, now, a.person.email, "scholar.edit", p.email, ", ".join(changed))
    db.commit()
    return profile_json(p, _supervisor_names(db))


class DecisionIn(BaseModel):
    approve: bool
    note: str = Field(default="", max_length=1000)


@router.post("/admin/scholars/{person_id}/decision")
def decide(person_id: int, body: DecisionIn, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
           clk: Clock = Depends(get_clock)):
    now = clk.now()
    p = _scholar(db, person_id)
    if p.registration_status != "pending":
        raise api_error(409, "REG_STATE", "This registration is not waiting for a decision.")
    if not body.approve and not body.note.strip():
        raise api_error(400, "REG_NOTE", "Write what the scholar should fix.")
    p.registration_status = "approved" if body.approve else "rejected"
    p.registration_note = body.note.strip()
    p.reviewed_by, p.reviewed_at = a.person.email, now
    audit(db, now, a.person.email, "registration.approve" if body.approve else "registration.reject", p.email,
          body.note.strip())
    db.commit()
    return profile_json(p, _supervisor_names(db))


class ActiveIn(BaseModel):
    active: bool


@router.post("/admin/scholars/{person_id}/active")
def set_active(person_id: int, body: ActiveIn, a: Actor = Depends(admin_only), db: Session = Depends(get_db),
               clk: Clock = Depends(get_clock)):
    """Deactivate a scholar who has left; they can no longer sign in."""
    now = clk.now()
    p = _scholar(db, person_id)
    p.active = body.active
    audit(db, now, a.person.email, "scholar.active", p.email, str(body.active))
    db.commit()
    return profile_json(p, _supervisor_names(db))
