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
