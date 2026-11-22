import base64
import hashlib
import math
import os
from pathlib import Path

import pytest

from app import face_service
from app.routers import attendance as att_router


def make_dummy_face(prefix: str = "scholar_face_sample") -> str:
    """Returns a dummy base64 payload (> 500 bytes)."""
    payload = (prefix * 50).encode()
    return base64.b64encode(payload).decode()


@pytest.fixture
def fake_model(monkeypatch):
    """Test-only stand-in for the face model: a deterministic vector per payload."""
    def fake(raw: bytes):
        h = hashlib.sha512(raw).digest() + hashlib.sha512(raw + b"x").digest()
        v = [(b - 128.0) / 128.0 for b in h]
        n = math.sqrt(sum(x * x for x in v))
        return [x / n for x in v]
    monkeypatch.setattr(face_service, "generate_face_embedding", fake)
    monkeypatch.setattr(att_router, "generate_face_embedding", fake)


def test_non_image_bytes_are_rejected_not_hashed():
    """Regression: random bytes used to become a replayable 'face' (synthetic embedding)."""
    with pytest.raises(ValueError):
        face_service.generate_face_embedding(os.urandom(800))


def test_face_cannot_be_re_enrolled_without_admin(env, s1, fake_model):
    assert s1.req("POST", "/att/face/enrol", {"image": make_dummy_face("my_own_face_sample_")}).status_code == 200
    r = s1.req("POST", "/att/face/enrol", {"image": make_dummy_face("a_friends_face_sample_")})
    assert r.status_code == 409 and r.json()["detail"]["code"] == "FACE_ALREADY_ENROLLED"
    r = env.client.post("/admin/face-reset", json={"email": "s1@iiitnr.edu.in", "reason": "wrong face"},
                        headers=env.staff("office@iiitnr.edu.in"))
    assert r.status_code == 200
    assert s1.req("POST", "/att/face/enrol", {"image": make_dummy_face("my_own_face_sample_")}).status_code == 200


def test_face_required_when_enabled(env, s1):
    from app.config import get_settings
    get_settings().require_face = True
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "FACE_REQUIRED"


def test_face_enrol_and_verification_flow(env, s1, fake_model):
    # 1. Enrol s1 face
    face_img = make_dummy_face("scholar_1_face_data_")
    r = s1.req("POST", "/att/face/enrol", {"image": face_img})
    assert r.status_code == 200
    assert r.json()["ok"] is True

    # 2. Try marking attendance without selfie -> FACE_REQUIRED
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "FACE_REQUIRED"

    # 3. Try marking with wrong face -> FACE_MISMATCH
    wrong_face = make_dummy_face("completely_different_person_")
    r = s1.req("POST", "/att/mark", {"face_image": wrong_face})
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "FACE_MISMATCH"

    # 4. Try marking with correct enrolled face -> 200 OK
    r = s1.req("POST", "/att/mark", {"face_image": face_img})
    assert r.status_code == 200
    assert r.json()["ok"] is True
    assert "Morning: marked present" in r.json()["message"]


def test_face_enrol_invalid_image(env, s1):
    # Tiny payload (< 500 bytes)
    tiny_img = base64.b64encode(b"too small").decode()
    r = s1.req("POST", "/att/face/enrol", {"image": tiny_img})
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "INVALID_FACE_IMAGE"


def test_real_ai_face_detection_and_matching(env, s2):
    """Verifies real deep learning face detection and cosine matching via YuNet + SFace."""
    fixtures_dir = Path(__file__).resolve().parent / "fixtures"
    if not (fixtures_dir / "face_a.jpg").exists():
        pytest.skip("tests/fixtures/face_a.jpg is missing (two photos of the same person are needed)")
    face_a_bytes = (fixtures_dir / "face_a.jpg").read_bytes()
    face_b_bytes = (fixtures_dir / "face_b.jpg").read_bytes()

    b64_a = base64.b64encode(face_a_bytes).decode()
    b64_b = base64.b64encode(face_b_bytes).decode()

    # 1. Enrol real face A for scholar 2
    r = s2.req("POST", "/att/face/enrol", {"image": b64_a})
    assert r.status_code == 200
    assert r.json()["ok"] is True

    # 2. Try marking with different person (face B) -> 403 FACE_MISMATCH
    r = s2.req("POST", "/att/mark", {"face_image": b64_b})
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "FACE_MISMATCH"
    assert "Face Mismatch" in r.json()["detail"]["message"]

    # 3. Try marking with same face A -> 200 OK
    r = s2.req("POST", "/att/mark", {"face_image": b64_a})
    assert r.status_code == 200
    assert r.json()["ok"] is True
    assert "AI Face Verified" in r.json()["message"]
    assert "Morning: marked present" in r.json()["message"]
