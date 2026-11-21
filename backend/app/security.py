"""Login, device lock (signed requests) and the campus-network check."""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import ipaddress
from dataclasses import dataclass

import jwt
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from fastapi import Depends, HTTPException, Request
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .clock import Clock, get_clock
from .config import get_settings
from .db import get_db
from .models import Attempt, AuditLog, CampusNetwork, Device, Nonce, Person


def api_error(status: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status, detail={"code": code, "message": message})


def audit(db: Session, now: dt.datetime, actor: str, action: str, subject: str = "", detail: str = "") -> None:
    db.add(AuditLog(at=now, actor=actor, action=action, subject=subject, detail=detail[:4000]))


# ---------------------------------------------------------------- login token

def _decode_token(token: str) -> str:
    s = get_settings()
    key = s.jwt_public_key or s.jwt_secret
    options = {"verify_aud": bool(s.jwt_audience)}
    try:
        claims = jwt.decode(token, key, algorithms=[s.jwt_algorithm],
                            audience=s.jwt_audience or None, options=options)
    except jwt.PyJWTError:
        raise api_error(401, "AUTH_INVALID", "Your login has expired. Please log in again.")
    email = str(claims.get(s.jwt_email_claim, "")).lower().strip()
    if not email.endswith("@" + s.institute_domain):
        raise api_error(403, "AUTH_DOMAIN", "Use your institute email account.")
    return email


def current_person(request: Request, db: Session = Depends(get_db)) -> Person:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise api_error(401, "AUTH_MISSING", "Please log in.")
    email = _decode_token(header[7:])
    person = db.scalar(select(Person).where(Person.email == email))
    if person is None or not person.active:
        raise api_error(403, "NOT_ENROLLED", "Your account is not set up for attendance. Contact the admin office.")
    return person


# ---------------------------------------------------------------- signed requests

def load_public_key(b64: str) -> ec.EllipticCurvePublicKey:
    raw = base64.b64decode(b64)
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)


def _signature_der(b64: str) -> bytes:
    raw = base64.b64decode(b64)
    if len(raw) == 64:  # r || s, as sent by the Flutter app
        return encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    return raw  # already DER


def canonical(method: str, path_qs: str, ts: str, nonce: str, body: bytes) -> bytes:
    return f"{method.upper()}\n{path_qs}\n{ts}\n{nonce}\n{hashlib.sha256(body).hexdigest()}".encode()


def verify_signature(public_key_b64: str, signature_b64: str, message: bytes) -> bool:
    try:
        load_public_key(public_key_b64).verify(_signature_der(signature_b64), message, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError, TypeError):
        return False


def _path_qs(request: Request) -> str:
    """The path the app signed: relative to the API base URL, with the raw query string."""
    path = request.url.path
    prefix = get_settings().path_prefix.rstrip("/")
    if prefix and path.startswith(prefix + "/"):
        path = path[len(prefix):]
    q = request.url.query
    return path + (f"?{q}" if q else "")


async def check_signature(request: Request, db: Session, now: dt.datetime, public_key_b64: str,
                          device_id: str) -> None:
    """Raises if the request is not signed by `public_key_b64`, is stale, or is a replay."""
    s = get_settings()
    h = request.headers
    ts, nonce, sig = h.get("X-Timestamp", ""), h.get("X-Nonce", ""), h.get("X-Signature", "")
    if not (ts and nonce and sig) or len(nonce) > 64:
        raise api_error(401, "SIGNATURE_MISSING", "This request did not come from the registered app.")
    try:
        sent = dt.datetime.fromtimestamp(int(ts) / 1000, dt.timezone.utc)
    except ValueError:
        raise api_error(401, "SIGNATURE_MISSING", "This request did not come from the registered app.")
    server_utc = dt.datetime.now(dt.timezone.utc)
    if abs((server_utc - sent).total_seconds()) > s.signature_max_skew_seconds:
        raise api_error(401, "CLOCK_SKEW", "Your phone's clock is wrong. Set it to automatic time and try again.")
    body = await request.body()
    if not verify_signature(public_key_b64, sig, canonical(request.method, _path_qs(request), ts, nonce, body)):
        raise api_error(401, "SIGNATURE_INVALID", "This request did not come from the registered phone.")
    if db.get(Nonce, nonce) is not None:
        raise api_error(401, "REPLAY", "This request was already used.")
    db.add(Nonce(nonce=nonce, device_id=device_id, seen_at=now))
    db.execute(delete(Nonce).where(Nonce.seen_at < now - dt.timedelta(hours=1)))
    db.commit()


@dataclass
class Actor:
    person: Person
    device: Device | None  # set for scholars (always signed); None for staff without a device


def _log_attempt(db: Session, person: Person | None, now: dt.datetime, reason: str, ip: str, device_id: str) -> None:
    db.add(Attempt(person_id=person.id if person else None, at=now, reason=reason, client_ip=ip, device_id=device_id))
    db.commit()


async def actor(request: Request, db: Session = Depends(get_db), clk: Clock = Depends(get_clock),
                person: Person = Depends(current_person)) -> Actor:
    """Scholars: every request must be signed by their one active phone (device lock).
    Staff (supervisor, dean, admin): login token is enough; a signed device is used if present."""
    now = clk.now()
    device_id = request.headers.get("X-Device-Id", "")
    if not person.is_scholar and not device_id:
        return Actor(person, None)
    ip = client_ip(request)
    dev = db.scalar(select(Device).where(Device.device_id == device_id)) if device_id else None
    if dev is None or dev.person_id != person.id:
        if person.is_scholar:
            _log_attempt(db, person, now, "DEVICE_UNKNOWN", ip, device_id)
            raise api_error(403, "DEVICE_NOT_REGISTERED", "Register this phone first.")
        return Actor(person, None)
    if dev.status != "active":
        _log_attempt(db, person, now, f"DEVICE_{dev.status.upper()}", ip, device_id)
        code = {"pending": "DEVICE_PENDING", "revoked": "DEVICE_REVOKED", "rejected": "DEVICE_REJECTED"}[dev.status]
        msg = {
            "pending": "This phone is waiting for the admin's approval.",
            "revoked": "This account is registered to another phone.",
            "rejected": "The admin did not approve this phone.",
        }[dev.status]
        raise api_error(403, code, msg)
    try:
        await check_signature(request, db, now, dev.public_key, dev.device_id)
    except HTTPException as e:
        _log_attempt(db, person, now, e.detail["code"], ip, device_id)
        raise
    return Actor(person, dev)


def require_role(*roles: str):
    def dep(a: Actor = Depends(actor)) -> Actor:
        if not any(a.person.has(r) for r in roles):
            raise api_error(403, "FORBIDDEN", "You do not have permission for this.")
        return a
    return dep


def require_scholar(a: Actor = Depends(actor)) -> Actor:
    if not a.person.is_scholar:
        raise api_error(403, "NOT_SCHOLAR", "Only PhD and MTech scholars use this.")
    return a


# ---------------------------------------------------------------- campus network

def client_ip(request: Request) -> str:
    if get_settings().trust_proxy:
        # Use the LAST address: the one our own proxy added. Earlier entries can be
        # typed in by the client and must not be trusted.
        fwd = request.headers.get("X-Forwarded-For", "")
        if fwd:
            return fwd.split(",")[-1].strip()
        real = request.headers.get("X-Real-IP", "")
        if real:
            return real.strip()
    return request.client.host if request.client else ""


def campus_networks(db: Session) -> list[ipaddress._BaseNetwork]:
    rows = db.scalars(select(CampusNetwork.cidr)).all()
    cidrs = rows or [c.strip() for c in get_settings().campus_cidrs.split(",") if c.strip()]
    return [ipaddress.ip_network(c, strict=False) for c in cidrs]


def on_campus(db: Session, ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return any(addr in net for net in campus_networks(db))
