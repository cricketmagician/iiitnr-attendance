import base64
from pathlib import Path
import pytest
from conftest import HOME_IP


def make_dummy_face(prefix: str = "scholar_face_sample") -> str:
    """Returns a valid dummy base64 JPEG-like payload."""
    payload = (prefix * 50).encode()  # > 500 bytes
    return base64.b64encode(payload).decode()


def test_face_enrol_and_verification_flow(env, s1):
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
