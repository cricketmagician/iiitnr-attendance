"""Authentication endpoints: Google Workspace SSO and Dev Login."""
from __future__ import annotations

import datetime as dt

import jwt
from fastapi import APIRouter, Depends
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db import get_db
from ..models import Person
from ..security import api_error

router = APIRouter(prefix="/auth", tags=["auth"])


class GoogleLoginIn(BaseModel):
    id_token: str = Field(min_length=20)


class DevLoginIn(BaseModel):
    email: str


def issue_session_jwt(person: Person) -> str:
    """Issues an authenticated session JWT for an enrolled IIITNR person."""
    s = get_settings()
    now_utc = dt.datetime.now(dt.timezone.utc)
    # Session lasts for 30 days
    exp = now_utc + dt.timedelta(days=30)
    payload = {
        s.jwt_email_claim: person.email.lower(),
        "sub": str(person.id),
        "name": person.name,
        "roles": person.roles,
        "iat": int(now_utc.timestamp()),
        "exp": int(exp.timestamp()),
    }
    if s.jwt_audience:
        payload["aud"] = s.jwt_audience
    return jwt.encode(payload, s.jwt_secret, algorithm=s.jwt_algorithm)


@router.post("/google")
def google_login(body: GoogleLoginIn, db: Session = Depends(get_db)):
    """Verifies Google Workspace OAuth2 ID Token for @iiitnr.edu.in scholars and staff."""
    s = get_settings()
    try:
        # Verify with Google's public certs
        # If google_client_id is set, verify audience; otherwise accept any valid Google token
        req = google_requests.Request()
        claims = id_token.verify_oauth2_token(
            body.id_token,
            req,
            audience=s.google_client_id if s.google_client_id else None,
        )
    except Exception as e:
        raise api_error(401, "GOOGLE_AUTH_FAILED", f"Google authentication failed: {e}")

    email = str(claims.get("email", "")).lower().strip()
    if not email:
        raise api_error(400, "NO_EMAIL", "Google account did not provide an email address.")

    # Domain enforcement: Must be official institute account!
    if not email.endswith("@" + s.institute_domain):
        raise api_error(403, "AUTH_DOMAIN", f"Only official @{s.institute_domain} Google accounts are permitted.")

    if not claims.get("email_verified", False):
        raise api_error(403, "EMAIL_NOT_VERIFIED", "Google email is not verified.")

    # Check if student/staff is enrolled in attendance database; auto-enroll if verified institute account
    person = db.scalar(select(Person).where(Person.email == email))
    if person is None:
        name = claims.get("name") or email.split("@")[0].replace(".", " ").title()
        roll_no = email.split("@")[0].upper()
        person = Person(
            email=email,
            name=name,
            roll_no=roll_no,
            programme="PhD" if "phd" in email else "MTech" if "mtech" in email else "Scholar",
            funding="institute",
            roles="scholar",
            active=True,
        )
        db.add(person)
        db.commit()
        db.refresh(person)

    if not person.active:
        raise api_error(403, "ACCOUNT_INACTIVE", "Your attendance account is currently deactivated.")

    # Issue session JWT
    token = issue_session_jwt(person)
    return {
        "ok": True,
        "token": token,
        "person": {
            "id": person.id,
            "email": person.email,
            "name": person.name,
            "roll_no": person.roll_no,
            "roles": person.roles,
            "is_scholar": person.is_scholar,
            "picture": claims.get("picture", ""),
        }
    }


@router.post("/dev-token")
def dev_token(body: DevLoginIn, db: Session = Depends(get_db)):
    """DEV ONLY: Fast login for development testing."""
    s = get_settings()
    if not s.dev_mode:
        raise api_error(403, "DEV_DISABLED", "dev-token is disabled in production.")

    email = body.email.lower().strip()
    if not email.endswith("@" + s.institute_domain):
        raise api_error(403, "AUTH_DOMAIN", f"Only official @{s.institute_domain} emails are allowed.")
    person = db.scalar(select(Person).where(Person.email == email))
    if person is None:
        role = "scholar"
        if "guide" in email:
            role = "guide"
        elif "hod" in email:
            role = "hod"
        elif "dean" in email:
            role = "dean"
        elif "office" in email or "admin" in email:
            role = "admin"
        name = email.split("@")[0].replace(".", " ").title()
        person = Person(
            email=email,
            name=name,
            roll_no=email.split("@")[0].upper(),
            programme="PhD" if "phd" in email else "MTech" if "mtech" in email else "Scholar",
            funding="institute",
            roles=role,
            active=True,
        )
        db.add(person)
        db.commit()
        db.refresh(person)

    token = issue_session_jwt(person)
    return {
        "ok": True,
        "token": token,
        "person": {
            "id": person.id,
            "email": person.email,
            "name": person.name,
            "roll_no": person.roll_no,
            "roles": person.roles,
            "is_scholar": person.is_scholar,
        }
    }
