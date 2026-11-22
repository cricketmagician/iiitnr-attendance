"""Database tables. All tables are prefixed att_ or leave_ so they sit safely beside
the existing IIITNR app tables. Create them with `python -m scripts.init_db`."""
from __future__ import annotations

import datetime as dt
from typing import Any, Optional

from sqlalchemy import (
    JSON, Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text, Time, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base

SESSIONS = ("M", "A", "E")  # morning, afternoon, evening


ROLE_ALIASES = {"guide": "supervisor", "dean": "dean_ri", "office": "admin"}
STAFF_ROLES = ("supervisor", "hod", "dean_ri", "admin")


class Person(Base):
    """Scholars and staff known to this module. Kept in step with the IIITNR app's user
    list via scripts/import_people.py (or a view over the existing user table)."""

    __tablename__ = "att_person"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(190), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(190))
    roll_no: Mapped[str] = mapped_column(String(40), default="")
    programme: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)  # PhD | MTech | None (staff)
    funding: Mapped[str] = mapped_column(String(10), default="institute")    # institute | external
    joining_date: Mapped[Optional[dt.date]] = mapped_column(Date, nullable=True)
    department: Mapped[str] = mapped_column(String(80), default="")
    supervisor_email: Mapped[str] = mapped_column(String(190), default="")
    # comma-separated: scholar, supervisor, hod, dean_ri, admin, guard (shows the gate QR)
    roles: Mapped[str] = mapped_column(String(120), default="scholar")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    face_embedding: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    face_enrolled_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)

    # Contact details, filled in by the scholar at registration
    phone: Mapped[str] = mapped_column(String(20), default="", server_default="")
    personal_email: Mapped[str] = mapped_column(String(190), default="", server_default="")
    address: Mapped[str] = mapped_column(String(300), default="", server_default="")

    # Registration: none -> pending -> approved | rejected (rejected may resubmit).
    # People imported by the office are approved from the start.
    registration_status: Mapped[str] = mapped_column(String(12), default="approved", server_default="approved")
    registration_note: Mapped[str] = mapped_column(Text, default="", server_default="")
    registered_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    reviewed_by: Mapped[str] = mapped_column(String(190), default="", server_default="")
    reviewed_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)

    @property
    def role_list(self) -> list[str]:
        """Canonical role names. Old names (guide, dean) are read as supervisor, dean_ri."""
        out: list[str] = []
        for r in self.roles.split(","):
            r = ROLE_ALIASES.get(r.strip().lower(), r.strip().lower())
            if r and r not in out:
                out.append(r)
        return out

    def has(self, role: str) -> bool:
        return role in self.role_list

    @property
    def is_staff(self) -> bool:
        return any(self.has(r) for r in STAFF_ROLES)

    @property
    def is_scholar(self) -> bool:
        """A registered, approved PhD or MTech scholar: may mark attendance and apply for leave."""
        return (self.has("scholar") and self.programme in ("PhD", "MTech")
                and (self.registration_status or "approved") == "approved")

    @property
    def needs_registration(self) -> bool:
        """A scholar account that has not been approved yet (and is not also staff)."""
        return self.has("scholar") and not self.is_staff and (self.registration_status or "approved") != "approved"


class Device(Base):
    __tablename__ = "att_device"
    id: Mapped[int] = mapped_column(primary_key=True)
    person_id: Mapped[int] = mapped_column(ForeignKey("att_person.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(64), unique=True)       # app-generated UUID
    hardware_id: Mapped[str] = mapped_column(String(128), index=True)     # Android ID / iOS identifierForVendor
    public_key: Mapped[str] = mapped_column(Text)                         # base64 uncompressed P-256 point
    platform: Mapped[str] = mapped_column(String(20), default="")
    model: Mapped[str] = mapped_column(String(80), default="")
    status: Mapped[str] = mapped_column(String(12), default="pending")    # pending | active | revoked | rejected
    reason: Mapped[str] = mapped_column(String(300), default="")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime)
    decided_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    decided_by: Mapped[str] = mapped_column(String(190), default="")
    person: Mapped[Person] = relationship()


class Nonce(Base):
    """Seen request nonces, to refuse replayed requests."""
    __tablename__ = "att_nonce"
    nonce: Mapped[str] = mapped_column(String(64), primary_key=True)
    device_id: Mapped[str] = mapped_column(String(64))
    seen_at: Mapped[dt.datetime] = mapped_column(DateTime, index=True)


class SessionWindow(Base):
    __tablename__ = "att_session_window"
    session: Mapped[str] = mapped_column(String(1), primary_key=True)  # M | A | E
    label: Mapped[str] = mapped_column(String(20))
    start_time: Mapped[dt.time] = mapped_column(Time)
    end_time: Mapped[dt.time] = mapped_column(Time)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Mark(Base):
    __tablename__ = "att_mark"
    __table_args__ = (UniqueConstraint("person_id", "date", "session"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    person_id: Mapped[int] = mapped_column(ForeignKey("att_person.id"), index=True)
    date: Mapped[dt.date] = mapped_column(Date, index=True)
    session: Mapped[str] = mapped_column(String(1))
    marked_at: Mapped[dt.datetime] = mapped_column(DateTime)
    device_id: Mapped[str] = mapped_column(String(64))
    client_ip: Mapped[str] = mapped_column(String(64))


class Attempt(Base):
    """Every refused marking attempt, with its reason (for the admin list and audits)."""
    __tablename__ = "att_attempt"
    id: Mapped[int] = mapped_column(primary_key=True)
    person_id: Mapped[Optional[int]] = mapped_column(ForeignKey("att_person.id"), nullable=True, index=True)
    at: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    session: Mapped[str] = mapped_column(String(1), default="")
    reason: Mapped[str] = mapped_column(String(40))
    client_ip: Mapped[str] = mapped_column(String(64), default="")
    device_id: Mapped[str] = mapped_column(String(64), default="")


class DayReview(Base):
    """A working day on which a scholar marked fewer than two sessions and was not on leave.
    The central admin decides: present (P*, remark required) or absent."""
    __tablename__ = "att_day_review"
    __table_args__ = (UniqueConstraint("person_id", "date"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    person_id: Mapped[int] = mapped_column(ForeignKey("att_person.id"), index=True)
    date: Mapped[dt.date] = mapped_column(Date, index=True)
    sessions_marked: Mapped[str] = mapped_column(String(3), default="")  # e.g. "M"
    status: Mapped[str] = mapped_column(String(10), default="pending")    # pending | present | absent | leave
    scholar_reason: Mapped[str] = mapped_column(Text, default="")
    remark: Mapped[str] = mapped_column(Text, default="")
    decided_by: Mapped[str] = mapped_column(String(190), default="")
    decided_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime)
    person: Mapped[Person] = relationship()


class Holiday(Base):
    __tablename__ = "att_holiday"
    date: Mapped[dt.date] = mapped_column(Date, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))


class CampusNetwork(Base):
    __tablename__ = "att_campus_network"
    id: Mapped[int] = mapped_column(primary_key=True)
    cidr: Mapped[str] = mapped_column(String(64), unique=True)
    label: Mapped[str] = mapped_column(String(120), default="")


class Setting(Base):
    """Admin-editable rule values (leave limits etc.). Defaults live in rules.DEFAULTS."""
    __tablename__ = "att_setting"
    key: Mapped[str] = mapped_column(String(60), primary_key=True)
    value: Mapped[Any] = mapped_column(JSON)


class LeaveApplication(Base):
    __tablename__ = "leave_application"
    id: Mapped[int] = mapped_column(primary_key=True)
    person_id: Mapped[int] = mapped_column(ForeignKey("att_person.id"), index=True)
    leave_type: Mapped[str] = mapped_column(String(12))  # CASUAL | MEDICAL | MATERNITY | PATERNITY | ACADEMIC
    from_date: Mapped[dt.date] = mapped_column(Date)
    to_date: Mapped[dt.date] = mapped_column(Date)
    days: Mapped[float] = mapped_column(Float)            # days charged to the balance
    reason: Mapped[str] = mapped_column(Text)
    address: Mapped[str] = mapped_column(String(300), default="")
    contact: Mapped[str] = mapped_column(String(40), default="")
    attachment_path: Mapped[str] = mapped_column(String(300), default="")
    needs_dean: Mapped[bool] = mapped_column(Boolean, default=False)
    # pending_supervisor -> [pending_dean] -> pending_admin -> confirmed
    # or declined | returned | withdrawn | cancelled
    status: Mapped[str] = mapped_column(String(20), default="pending_supervisor", index=True)
    supervisor_note: Mapped[str] = mapped_column(Text, default="")
    dean_note: Mapped[str] = mapped_column(Text, default="")
    admin_note: Mapped[str] = mapped_column(Text, default="")
    approved_by: Mapped[str] = mapped_column(String(190), default="")
    approved_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    dean_by: Mapped[str] = mapped_column(String(190), default="")
    dean_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    confirmed_by: Mapped[str] = mapped_column(String(190), default="")
    confirmed_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime)
    person: Mapped[Person] = relationship()


ACTIVE_LEAVE = ("pending_supervisor", "pending_dean", "pending_admin", "confirmed")


class LeaveAdjustment(Base):
    """Days added (or removed, if negative) by the admin to a scholar's balance for one
    leave year, e.g. to carry leave forward by hand."""
    __tablename__ = "leave_adjustment"
    id: Mapped[int] = mapped_column(primary_key=True)
    person_id: Mapped[int] = mapped_column(ForeignKey("att_person.id"), index=True)
    pool: Mapped[str] = mapped_column(String(12))  # ORDINARY | MEDICAL | ACADEMIC
    leave_year_start: Mapped[dt.date] = mapped_column(Date)
    days: Mapped[float] = mapped_column(Float)
    remark: Mapped[str] = mapped_column(Text)
    by: Mapped[str] = mapped_column(String(190))
    at: Mapped[dt.datetime] = mapped_column(DateTime)


class AuditLog(Base):
    __tablename__ = "att_audit"
    id: Mapped[int] = mapped_column(primary_key=True)
    at: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    actor: Mapped[str] = mapped_column(String(190))
    action: Mapped[str] = mapped_column(String(60))
    subject: Mapped[str] = mapped_column(String(120), default="")
    detail: Mapped[str] = mapped_column(Text, default="")
