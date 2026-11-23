import base64
import datetime as dt
import hashlib
import json
import tempfile
import os
import secrets
import time
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

os.environ.setdefault("ATT_UPLOAD_DIR", "/tmp/att_test_uploads")

from app.clock import get_clock  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.db import Base, get_db  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import Person  # noqa: E402

CAMPUS_IP = "10.20.3.44"
HOME_IP = "49.36.10.10"


class FrozenClock:
    def __init__(self, t: dt.datetime):
        self.t = t

    def now(self):
        return self.t


class Phone:
    """Simulates the Flutter app on one phone: a P-256 key and signed requests."""

    def __init__(self, client, token, hardware_id=None):
        self.client = client
        self.token = token
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.device_id = str(uuid.uuid4())
        self.hardware_id = hardware_id or secrets.token_hex(8)
        self.ip = CAMPUS_IP

    @property
    def public_b64(self):
        raw = self.key.public_key().public_bytes(serialization.Encoding.X962,
                                                 serialization.PublicFormat.UncompressedPoint)
        return base64.b64encode(raw).decode()

    def headers(self, method, path, body=b"", nonce=None, ts=None, sign=True):
        ts = ts or str(int(time.time() * 1000))
        nonce = nonce or secrets.token_hex(16)
        msg = f"{method}\n{path}\n{ts}\n{nonce}\n{hashlib.sha256(body).hexdigest()}".encode()
        der = self.key.sign(msg, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der)
        sig = base64.b64encode(r.to_bytes(32, "big") + s.to_bytes(32, "big")).decode()
        h = {"Authorization": f"Bearer {self.token}", "X-Device-Id": self.device_id,
             "X-Forwarded-For": self.ip, "Content-Type": "application/json"}
        if sign:
            h |= {"X-Timestamp": ts, "X-Nonce": nonce, "X-Signature": sig}
        return h

    def req(self, method, path, payload=None, **kw):
        body = json.dumps(payload).encode() if payload is not None else b""
        return self.client.request(method, path, content=body or None, headers=self.headers(method, path, body, **kw))

    def register(self, reason=""):
        return self.req("POST", "/att/device/register", {
            "device_id": self.device_id, "hardware_id": self.hardware_id, "public_key": self.public_b64,
            "platform": "android", "model": "Test", "reason": reason})


@pytest.fixture
def env():
    s = get_settings()
    # Tests must not depend on the developer's local .env
    s.dev_mode = False
    s.enforce_device_lock = True
    s.kiosk_key = "test-kiosk-key"
    s.qr_secret = ""
    # Most tests check other rules; QR/face requirements have their own tests.
    s.require_guard_qr = False
    s.require_face = False
    s.require_ble = False
    s.keep_mark_selfies = True
    s.liveness_mode = "review"
    s.liveness_retries = 2
    s.liveness_threshold = 0.5
    s.upload_dir = tempfile.mkdtemp(prefix="att-test-")
    s.trust_proxy = True
    s.jwt_secret = "test-secret-0123456789-abcdefghijklmnop"
    s.jwt_algorithm = "HS256"
    s.campus_cidrs = "10.0.0.0/8"
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    clock = FrozenClock(dt.datetime(2026, 11, 23, 9, 40))  # Monday, morning window open

    def _db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app = create_app()
    app.dependency_overrides[get_db] = _db
    app.dependency_overrides[get_clock] = lambda: clock
    client = TestClient(app)

    with Session() as db:
        db.add_all([
            Person(email="s1@iiitnr.edu.in", name="Scholar One", roll_no="P1", programme="PhD", funding="institute",
                   joining_date=dt.date(2024, 8, 1), department="S&M", supervisor_email="guide@iiitnr.edu.in",
                   roles="scholar"),
            Person(email="s2@iiitnr.edu.in", name="Scholar Two", roll_no="M2", programme="MTech", funding="external",
                   joining_date=dt.date(2025, 7, 21), department="CSE", supervisor_email="guide@iiitnr.edu.in",
                   roles="scholar"),
            Person(email="guide@iiitnr.edu.in", name="Guide", department="S&M", roles="supervisor"),
            Person(email="other@iiitnr.edu.in", name="Other Guide", department="CSE", roles="supervisor"),
            Person(email="dean@iiitnr.edu.in", name="Dean", roles="dean_ri"),
            Person(email="office@iiitnr.edu.in", name="Office", roles="admin"),
        ])
        db.commit()

    def token(email):
        return jwt.encode({"email": email, "exp": int(time.time()) + 3600}, "test-secret-0123456789-abcdefghijklmnop", algorithm="HS256")

    def staff(email):
        return {"Authorization": f"Bearer {token(email)}", "Content-Type": "application/json"}

    class Env:
        pass

    e = Env()
    e.client, e.clock, e.Session, e.token, e.staff = client, clock, Session, token, staff
    e.phone = lambda email, **kw: Phone(client, token(email), **kw)
    yield e


@pytest.fixture
def s1(env):
    ph = env.phone("s1@iiitnr.edu.in")
    assert ph.register().json()["status"] == "active"
    return ph


@pytest.fixture
def s2(env):
    ph = env.phone("s2@iiitnr.edu.in")
    assert ph.register().json()["status"] == "active"
    return ph
