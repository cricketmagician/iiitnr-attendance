import datetime as dt

from conftest import HOME_IP


def code(r):
    return r.json()["detail"]["code"]


# ---------------------------------------------------------------- device lock

def test_first_phone_active_second_needs_admin(env, s1):
    new = env.phone("s1@iiitnr.edu.in")
    assert new.register("old phone damaged").json()["status"] == "pending"
    r = new.req("POST", "/att/mark")
    assert r.status_code == 403 and code(r) == "DEVICE_PENDING"
    # old phone still works until the admin approves
    assert s1.req("POST", "/att/mark").status_code == 200

    pend = env.client.get("/admin/devices", headers=env.staff("office@iiitnr.edu.in")).json()
    assert len(pend) == 1 and pend[0]["reason"] == "old phone damaged"
    env.client.post(f"/admin/devices/{pend[0]['id']}", json={"approve": True},
                    headers=env.staff("office@iiitnr.edu.in"))
    r = s1.req("GET", "/att/today")
    assert r.status_code == 403 and code(r) == "DEVICE_REVOKED"
    assert new.req("GET", "/att/today").status_code == 200


def test_friend_logs_in_on_own_phone_is_refused(env, s1):
    friend_phone = env.phone("s1@iiitnr.edu.in")  # scholar's password used on another phone
    r = friend_phone.req("POST", "/att/mark")
    assert r.status_code == 403 and code(r) == "DEVICE_NOT_REGISTERED"


def test_one_phone_cannot_serve_two_scholars(env, s1):
    p2 = env.phone("s2@iiitnr.edu.in", hardware_id=s1.hardware_id)
    r = p2.register()
    assert r.status_code == 409 and code(r) == "DEVICE_TAKEN"


def test_register_requires_proof_of_key(env):
    ph = env.phone("s1@iiitnr.edu.in")
    other = env.phone("s1@iiitnr.edu.in")
    body = {"device_id": ph.device_id, "hardware_id": ph.hardware_id, "public_key": other.public_b64}
    r = ph.req("POST", "/att/device/register", body)
    assert r.status_code == 401 and code(r) == "SIGNATURE_INVALID"


def test_non_institute_email_refused(env):
    ph = env.phone("someone@gmail.com")
    r = ph.register()
    assert r.status_code == 403 and code(r) == "AUTH_DOMAIN"


# ---------------------------------------------------------------- marking

def test_mark_in_window_on_campus(env, s1):
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["session"] == "M" and j["marked_at"] == "09:40"
    assert j["today"]["marked_count"] == 1 and not j["today"]["day_complete"]


def test_mark_off_campus_refused_and_logged(env, s1):
    s1.ip = HOME_IP
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 403 and code(r) == "NOT_ON_CAMPUS"
    tries = env.client.get("/admin/attempts?date=2026-11-23", headers=env.staff("office@iiitnr.edu.in")).json()
    assert tries[-1]["reason"] == "NOT_ON_CAMPUS" and tries[-1]["ip"] == HOME_IP


def test_campus_networks_from_admin_settings(env, s1):
    env.client.post("/admin/settings/campus-networks", json={"cidr": "49.36.10.0/24", "label": "Hostel NAT"},
                    headers=env.staff("office@iiitnr.edu.in"))
    s1.ip = HOME_IP  # now inside a configured campus range; 10.x fallback no longer applies
    assert s1.req("POST", "/att/mark").status_code == 200


def test_outside_window_refused(env, s1):
    env.clock.t = dt.datetime(2026, 11, 23, 10, 1)
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 409 and code(r) == "OUTSIDE_WINDOW"


def test_window_edges(env, s1):
    env.clock.t = dt.datetime(2026, 11, 23, 12, 45)
    assert s1.req("POST", "/att/mark").json()["session"] == "A"
    env.clock.t = dt.datetime(2026, 11, 23, 18, 30)
    assert s1.req("POST", "/att/mark").json()["session"] == "E"


def test_double_mark_refused(env, s1):
    assert s1.req("POST", "/att/mark").status_code == 200
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 409 and code(r) == "ALREADY_MARKED"


def test_weekend_and_holiday_refused(env, s1):
    env.clock.t = dt.datetime(2026, 11, 28, 9, 40)  # Saturday
    r = s1.req("POST", "/att/mark")
    assert code(r) == "NOT_WORKING_DAY"
    env.client.post("/admin/holidays", json={"date": "2026-11-24", "name": "Test holiday"},
                    headers=env.staff("office@iiitnr.edu.in"))
    env.clock.t = dt.datetime(2026, 11, 24, 9, 40)
    assert code(s1.req("POST", "/att/mark")) == "NOT_WORKING_DAY"


def test_unsigned_tampered_replayed_requests_refused(env, s1):
    r = s1.client.post("/att/mark", headers=s1.headers("POST", "/att/mark", sign=False))
    assert code(r) == "SIGNATURE_MISSING"
    h = s1.headers("POST", "/att/mark")
    h["X-Signature"] = s1.headers("POST", "/att/today")["X-Signature"]
    assert code(s1.client.post("/att/mark", headers=h)) == "SIGNATURE_INVALID"
    h = s1.headers("POST", "/att/mark", nonce="fixed-nonce-1")
    assert s1.client.post("/att/mark", headers=h).status_code == 200
    env.clock.t = dt.datetime(2026, 11, 23, 12, 50)
    assert code(s1.client.post("/att/mark", headers=h)) == "REPLAY"


def test_stale_timestamp_refused(env, s1):
    import time
    old = str(int((time.time() - 600) * 1000))
    assert code(s1.req("POST", "/att/mark", ts=old)) == "CLOCK_SKEW"


def test_staff_need_no_device(env):
    r = env.client.get("/att/me", headers=env.staff("guide@iiitnr.edu.in"))
    assert r.status_code == 200 and "supervisor" in r.json()["roles"]


# ---------------------------------------------------------------- day rule and admin review

def _mark(env, ph, h, m):
    env.clock.t = dt.datetime(2026, 11, 23, h, m)
    assert ph.req("POST", "/att/mark").status_code == 200


def test_two_sessions_make_a_day_one_goes_to_admin(env, s1, s2):
    _mark(env, s1, 9, 35)
    _mark(env, s1, 17, 50)   # s1: M + E = present
    _mark(env, s2, 9, 50)    # s2: only M
    env.clock.t = dt.datetime(2026, 11, 23, 18, 35)
    office = env.staff("office@iiitnr.edu.in")
    r = env.client.post("/admin/run-day-close?date=2026-11-23", headers=office)
    assert r.json()["new_reviews"] == 1
    # re-running does not duplicate
    assert env.client.post("/admin/run-day-close?date=2026-11-23", headers=office).json()["new_reviews"] == 0

    revs = env.client.get("/admin/reviews", headers=office).json()
    assert len(revs) == 1 and revs[0]["scholar"]["email"] == "s2@iiitnr.edu.in"
    assert revs[0]["sessions_marked"] == "M"

    # scholar adds a reason
    mine = s2.req("GET", "/att/reviews").json()
    assert s2.req("POST", f"/att/reviews/{mine[0]['id']}/reason", {"reason": "Lab experiment ran late"}).status_code == 200

    # present needs a remark
    r = env.client.post(f"/admin/reviews/{revs[0]['id']}", json={"decision": "present"}, headers=office)
    assert code(r) == "REMARK_REQUIRED"
    r = env.client.post(f"/admin/reviews/{revs[0]['id']}",
                        json={"decision": "present", "remark": "Seen in lab"}, headers=office)
    assert r.json()["status"] == "present"

    grid = {row["name"]: row for row in env.client.get("/admin/register?m=2026-11", headers=office).json()}
    day = lambda name: next(d for d in grid[name]["days"] if d["date"] == "2026-11-23")  # noqa: E731
    assert day("Scholar One")["code"] == "P"
    assert day("Scholar Two")["code"] == "P*" and day("Scholar Two")["remark"] == "Seen in lab"
    assert next(d for d in grid["Scholar One"]["days"] if d["date"] == "2026-11-22")["code"] == "W"


def test_day_not_closed_before_evening_window_ends(env, s1):
    env.clock.t = dt.datetime(2026, 11, 23, 18, 0)
    r = env.client.post("/admin/run-day-close?date=2026-11-23", headers=env.staff("office@iiitnr.edu.in"))
    assert r.json()["new_reviews"] == 0
    assert next(d for d in s1.req("GET", "/att/month?m=2026-11").json()["days"]
                if d["date"] == "2026-11-23")["code"] == "-"


def test_register_visibility_and_csv(env, s1, s2):
    _mark(env, s1, 9, 35)
    _mark(env, s1, 12, 50)
    guide = env.client.get("/admin/register?m=2026-11", headers=env.staff("guide@iiitnr.edu.in")).json()
    assert {r["name"] for r in guide} == {"Scholar One", "Scholar Two"}
    other = env.client.get("/admin/register?m=2026-11", headers=env.staff("other@iiitnr.edu.in")).json()
    assert other == []
    r = env.client.get("/admin/register?m=2026-11&format=csv", headers=env.staff("office@iiitnr.edu.in"))
    assert r.headers["content-type"].startswith("text/csv") and "Scholar One" in r.text
    assert env.client.get("/admin/register?m=2026-11", headers=env.staff("dean@iiitnr.edu.in")).status_code == 403


def test_schedule_lists_working_days(env, s1):
    j = s1.req("GET", "/att/schedule?days=7").json()
    dates = [d["date"] for d in j["days"]]
    assert "2026-11-28" not in dates and "2026-11-23" in dates and len(j["windows"]) == 3


def test_admin_can_change_windows(env, s1):
    office = env.staff("office@iiitnr.edu.in")
    r = env.client.put("/admin/settings/windows", json=[{"session": "M", "start": "09:00", "end": "09:45"}],
                       headers=office)
    assert r.status_code == 200
    env.clock.t = dt.datetime(2026, 11, 23, 9, 50)  # was open under the old 9:30–10:00 window
    assert code(s1.req("POST", "/att/mark")) == "OUTSIDE_WINDOW"


def test_spoofed_forwarded_for_is_ignored(env, s1):
    # A phone off campus types a campus address into X-Forwarded-For; nginx appends the real one.
    s1.ip = "10.1.1.1, 49.36.10.10"
    r = s1.req("POST", "/att/mark")
    assert r.status_code == 403 and code(r) == "NOT_ON_CAMPUS"
