"""Stopping marks over a video call: the guard Bluetooth beacon, the guard's live feed and flags."""
import base64
import datetime as dt
import time
import uuid

from app.config import get_settings
from app.models import DayReview
from app.qr_service import BLE_SLOT_SECONDS, ble_beacon, verify_ble
from tests.test_face_verification import fake_model  # noqa: F401  (fixture)

KIOSK = {"X-Kiosk-Key": "test-kiosk-key"}
SELFIE = base64.b64encode(b"\xff\xd8 test selfie " * 60).decode()


def code(r):
    return r.json()["detail"]["code"]


def _beacon(env):
    return env.client.get("/att/guard/qr", headers=KIOSK).json()["ble"]["uuid"]


def test_beacon_token_is_signed_and_short_lived():
    now = time.time()
    b = ble_beacon(now)["uuid"]
    assert verify_ble(b, now)[0]
    assert verify_ble(b, now + 3 * BLE_SLOT_SECONDS)[0]          # still fresh enough
    assert not verify_ble(b, now + 6 * BLE_SLOT_SECONDS)[0]      # too old
    raw = bytearray(uuid.UUID(b).bytes)
    raw[-1] ^= 1
    assert not verify_ble(str(uuid.UUID(bytes=bytes(raw))), now)[0]  # forged tag
    assert not verify_ble(str(uuid.uuid4()), now)[0]                  # some other device
    assert not verify_ble("not-a-uuid", now)[0]


def test_beacon_required_outside_dev_mode(env, s1):
    get_settings().require_ble = None   # default: required when not in dev mode
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    assert code(s1.req("POST", "/att/mark", {})) == "PROXIMITY_REQUIRED"
    assert code(s1.req("POST", "/att/mark", {"ble_uuid": str(uuid.uuid4())})) == "BLE_INVALID"
    r = s1.req("POST", "/att/mark", {"ble_uuid": _beacon(env), "ble_rssi": -62})
    assert r.status_code == 200, r.text
    assert r.json()["near_gate"] is True


def test_guard_feed_shows_selfie_and_flag_sends_day_to_office(env, s1, fake_model):  # noqa: F811
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    assert s1.req("POST", "/att/mark", {"face_image": SELFIE, "ble_uuid": _beacon(env), "ble_rssi": -60}).status_code == 200
    env.clock.t = dt.datetime(2026, 11, 23, 17, 50)
    assert s1.req("POST", "/att/mark", {"face_image": SELFIE}).status_code == 200

    feed = env.client.get("/att/guard/feed", headers=KIOSK).json()["marks"]
    assert [m["session"] for m in feed] == ["E", "M"]        # newest first
    morning = feed[1]
    assert morning["near_gate"] is True and morning["rssi"] == -60 and morning["has_selfie"]
    assert feed[0]["near_gate"] is False                     # beacon optional in tests, and none was sent
    img = env.client.get(f"/att/guard/marks/{morning['id']}/selfie", headers=KIOSK)
    assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"

    # Present before the flag
    office = env.staff("office@iiitnr.edu.in")
    row = lambda: next(r for r in env.client.get("/admin/register?m=2026-11", headers=office).json()  # noqa: E731
                       if r["name"] == "Scholar One")["days"][22]
    assert row()["code"] == "P"

    # Guard saw nobody for the evening mark
    r = env.client.post(f"/att/guard/marks/{feed[0]['id']}/flag", json={"note": "Nobody at desk"}, headers=KIOSK)
    assert r.json()["flagged"] is True
    env.clock.t = dt.datetime(2026, 11, 23, 21, 0)            # after the day closes
    assert row()["code"] == "R"                              # one counted session left: office decides
    with env.Session() as db:
        rev = db.query(DayReview).one()
        assert rev.status == "pending" and "Nobody at desk" in rev.remark and rev.sessions_marked == "M"

    # Undo by mistake: day counts again and the review goes away
    assert env.client.post(f"/att/guard/marks/{feed[0]['id']}/unflag", headers=KIOSK).json()["flagged"] is False
    assert row()["code"] == "P"
    with env.Session() as db:
        assert db.query(DayReview).count() == 0


def test_only_guard_desk_sees_the_feed(env, s1):
    assert code(env.client.get("/att/guard/feed")) == "KIOSK_ONLY"
    assert env.client.get("/att/guard/feed", headers=env.staff("s1@iiitnr.edu.in")).status_code == 403
    assert env.client.get("/att/guard/feed", headers=env.staff("office@iiitnr.edu.in")).status_code == 200


def test_qr_is_the_backup_and_is_labelled(env, s1):
    get_settings().require_ble = None
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    qr = env.client.get("/att/guard/qr", headers=KIOSK).json()["qr_string"]
    r = s1.req("POST", "/att/mark", {"qr_token": qr})          # no Bluetooth signal, QR instead
    assert r.status_code == 200 and r.json()["near_gate"] is False
    feed = env.client.get("/att/guard/feed", headers=KIOSK).json()["marks"]
    assert feed[0]["proof"] == "qr"


def test_bluetooth_alone_is_enough(env, s1):
    get_settings().require_ble = None
    get_settings().require_guard_qr = True
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    r = s1.req("POST", "/att/mark", {"ble_uuid": _beacon(env)})    # no QR at all
    assert r.status_code == 200 and r.json()["near_gate"] is True
    assert env.client.get("/att/guard/feed", headers=KIOSK).json()["marks"][0]["proof"] == "bluetooth"
    get_settings().require_guard_qr = False
