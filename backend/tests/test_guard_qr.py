import time
from app.qr_service import generate_guard_qr, verify_guard_qr


def test_guard_qr_generation_and_verification():
    qr = generate_guard_qr("morning")
    assert qr["session"] == "morning"
    assert qr["qr_string"].startswith("IIITNR-ATT:morning:")
    assert qr["rotation_interval"] == 3

    # Verification within valid time window
    ok, msg = verify_guard_qr(qr["qr_string"], "morning")
    assert ok is True

    # Session mismatch check
    ok, msg = verify_guard_qr(qr["qr_string"], "evening", strict=True)
    assert ok is False
    assert "session" in msg.lower()

    # Tampered signature check
    tampered = qr["qr_string"][:-4] + "dead"
    ok, msg = verify_guard_qr(tampered, "morning")
    assert ok is False
    assert "Counterfeit" in msg or "Invalid" in msg

    # Expired token check (older slot)
    old_slot = (int(time.time()) // 3) - 20 # 60 seconds ago
    old_qr = f"IIITNR-ATT:morning:{old_slot}:somerealsig"
    ok, msg = verify_guard_qr(old_qr, "morning", max_drift_seconds=15)
    assert ok is False


def test_guard_qr_endpoint_is_kiosk_only(env, s1):
    # no key, no login -> refused
    assert env.client.get("/att/guard/qr").status_code == 403
    # a scholar cannot fetch the live QR
    assert env.client.get("/att/guard/qr", headers={"Authorization": f"Bearer {env.token('s1@iiitnr.edu.in')}"}).status_code == 403
    # wrong key -> refused; kiosk key or admin -> allowed
    assert env.client.get("/att/guard/qr", headers={"X-Kiosk-Key": "nope"}).status_code == 403
    assert env.client.get("/att/guard/qr", headers={"X-Kiosk-Key": "test-kiosk-key"}).status_code == 200
    assert env.client.get("/att/guard/qr", headers=env.staff("office@iiitnr.edu.in")).status_code == 200


def test_mark_requires_qr_when_enabled(env, s1):
    from app.config import get_settings
    get_settings().require_guard_qr = True
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "QR_REQUIRED"
    qr = env.client.get("/att/guard/qr", headers={"X-Kiosk-Key": "test-kiosk-key"}).json()["qr_string"]
    assert s1.req("POST", "/att/mark", {"qr_token": qr}).status_code == 200


def test_qr_not_signed_with_jwt_secret(env):
    import hashlib, hmac, time as _t
    from app.config import get_settings
    slot = int(_t.time()) // 3
    sig = hmac.new(get_settings().jwt_secret.encode(), f"IIITNR-ATT:M:{slot}".encode(), hashlib.sha256).hexdigest()[:16]
    ok, _ = verify_guard_qr(f"IIITNR-ATT:M:{slot}:{sig}", "M")
    assert ok is False


def test_test_verify_endpoint_off_outside_dev_mode(env):
    r = env.client.post("/att/face/test-verify", json={"email": "s1@iiitnr.edu.in", "face_image": "x" * 800})
    assert r.status_code == 404


def test_production_refuses_weak_jwt_secret():
    import pytest
    from app.config import Settings, check_production_settings
    with pytest.raises(RuntimeError):
        check_production_settings(Settings(dev_mode=False, jwt_secret="iiitnr-attendance-secure-jwt-token-key-2026"))
    check_production_settings(Settings(dev_mode=True, jwt_secret="change-me"))  # testing mode allowed


def test_guard_login_shows_qr_but_scholar_cannot(env, s1):
    from app.config import get_settings
    from app.models import Person
    with env.Session() as db:
        db.add(Person(email="gate@iiitnr.edu.in", name="Gate", roles="guard"))
        db.commit()
    assert get_settings().dev_mode is False
    r = env.client.get("/att/guard/qr", headers=env.staff("gate@iiitnr.edu.in"))
    assert r.status_code == 200 and r.json()["qr_string"]
    assert env.client.get("/att/guard/qr", headers=env.staff("s1@iiitnr.edu.in")).status_code == 403
