import base64
import datetime as dt

CERT = {"attachment_name": "cert.pdf", "attachment_base64": base64.b64encode(b"%PDF-1.4 test").decode()}


def code(r):
    return r.json()["detail"]["code"]


def apply(ph, t, a, b, **extra):
    return ph.req("POST", "/leave", {"leave_type": t, "from_date": a, "to_date": b, "reason": "Test reason", **extra})


def test_weekends_and_holidays_not_counted(env, s1):
    env.client.post("/admin/holidays", json={"date": "2026-11-30", "name": "Test"},
                    headers=env.staff("office@iiitnr.edu.in"))
    r = apply(s1, "CASUAL", "2026-11-27", "2026-12-01")  # Fri, Sat, Sun, Mon(holiday), Tue
    assert r.status_code == 200 and r.json()["days"] == 2
    assert code(apply(s1, "CASUAL", "2026-12-05", "2026-12-06")) == "LEAVE_NO_WORKING_DAYS"


def test_institute_scholar_five_days_at_a_stretch(env, s1, s2):
    assert code(apply(s1, "CASUAL", "2026-11-30", "2026-12-07")) == "LEAVE_STRETCH"  # 6 working days
    # back-to-back applications joined by a weekend count as one stretch
    assert apply(s1, "CASUAL", "2026-11-27", "2026-11-27").status_code == 200
    assert apply(s1, "CASUAL", "2026-11-30", "2026-12-03").status_code == 200   # stretch = 5
    assert code(apply(s1, "MEDICAL", "2026-12-04", "2026-12-04")) == "LEAVE_STRETCH"
    # external scholar: no stretch limit
    assert apply(s2, "CASUAL", "2026-11-30", "2026-12-07").status_code == 200


def test_semester_cap_15(env, s2):
    assert apply(s2, "CASUAL", "2026-11-24", "2026-12-07").json()["days"] == 10
    assert apply(s2, "CASUAL", "2026-12-14", "2026-12-18").json()["days"] == 5
    assert code(apply(s2, "CASUAL", "2026-12-21", "2026-12-21")) == "LEAVE_SEMESTER_CAP"
    assert apply(s2, "CASUAL", "2027-01-04", "2027-01-04").status_code == 200  # new semester


def test_medical_limits_certificate_and_backdating(env, s2):
    assert code(apply(s2, "MEDICAL", "2026-11-24", "2026-11-26")) == "LEAVE_CERTIFICATE"   # 3 days, no cert
    assert code(apply(s2, "MEDICAL", "2027-01-04", "2027-01-25", **CERT)) == "LEAVE_MEDICAL_LIMIT"  # 16 days
    assert apply(s2, "MEDICAL", "2026-11-20", "2026-11-20").status_code == 200  # 3 days back, allowed
    assert code(apply(s2, "CASUAL", "2026-11-20", "2026-11-20")) == "LEAVE_BACKDATED"
    assert code(apply(s2, "MEDICAL", "2026-11-16", "2026-11-16")) == "LEAVE_BACKDATED"  # 7 days back


def test_maternity_once(env, s2):
    assert apply(s2, "MATERNITY", "2027-01-04", "2027-07-02").json()["days"] == 180
    assert code(apply(s2, "MATERNITY", "2027-07-05", "2027-07-06")) == "LEAVE_ONCE"
    assert code(apply(s2, "PATERNITY", "2026-12-01", "2026-12-16")) == "LEAVE_BALANCE"  # 16 > 15


def test_academic_duty_dean_and_hard_limit(env, s1):
    r = apply(s1, "ACADEMIC", "2027-01-04", "2027-02-26")  # 40 working days
    assert r.status_code == 200 and r.json()["needs_dean"] is True
    assert code(apply(s1, "ACADEMIC", "2027-03-01", "2027-04-02")) == "LEAVE_BALANCE"  # +25 = 65 > 60
    small = apply(s1, "ACADEMIC", "2026-12-01", "2026-12-02")
    assert small.json()["needs_dean"] is True  # 40 already applied, so any more is beyond 30


def test_leave_year_from_joining_date(env, s1):
    assert code(apply(s1, "CASUAL", "2027-07-30", "2027-08-02")) == "LEAVE_YEAR_SPLIT"
    b = s1.req("GET", "/leave/mine").json()["balances"]
    assert b["leave_year"] == ["2026-08-01", "2027-07-31"]


def test_overlap_refused(env, s1):
    assert apply(s1, "CASUAL", "2026-12-01", "2026-12-02").status_code == 200
    assert code(apply(s1, "MEDICAL", "2026-12-02", "2026-12-02")) == "LEAVE_OVERLAP"


def test_supervisor_then_admin_flow_and_register(env, s1):
    lv = apply(s1, "CASUAL", "2026-11-24", "2026-11-25").json()
    other = env.client.post(f"/leave/{lv['id']}/approve", json={"approve": True},
                            headers=env.staff("other@iiitnr.edu.in"))
    assert other.status_code == 404  # not this scholar's supervisor
    q = env.client.get("/leave/queue?role=supervisor", headers=env.staff("guide@iiitnr.edu.in")).json()
    assert [x["id"] for x in q] == [lv["id"]]
    r = env.client.post(f"/leave/{lv['id']}/approve", json={"approve": True, "note": "ok"},
                        headers=env.staff("guide@iiitnr.edu.in"))
    assert r.json()["status"] == "pending_admin"
    office = env.staff("office@iiitnr.edu.in")
    assert code(env.client.post(f"/leave/{lv['id']}/confirm", json={"confirm": False}, headers=office)) == "NOTE_REQUIRED"
    r = env.client.post(f"/leave/{lv['id']}/confirm", json={"confirm": True}, headers=office)
    assert r.json()["status"] == "confirmed"
    env.clock.t = dt.datetime(2026, 11, 26, 9, 0)
    month = s1.req("GET", "/att/month?m=2026-11").json()
    codes = {d["date"]: d["code"] for d in month["days"]}
    assert codes["2026-11-24"] == "L" and codes["2026-11-25"] == "L"
    # withdraw is not possible after confirmation
    assert code(s1.req("POST", f"/leave/{lv['id']}/withdraw")) == "LEAVE_DECIDED"


def test_academic_goes_through_dean(env, s1):
    lv = apply(s1, "ACADEMIC", "2027-01-04", "2027-02-26").json()
    env.client.post(f"/leave/{lv['id']}/approve", json={"approve": True}, headers=env.staff("guide@iiitnr.edu.in"))
    q = env.client.get("/leave/queue?role=dean", headers=env.staff("dean@iiitnr.edu.in")).json()
    assert q[0]["id"] == lv["id"]
    assert env.client.post(f"/leave/{lv['id']}/confirm", json={"confirm": True},
                           headers=env.staff("office@iiitnr.edu.in")).status_code == 409
    r = env.client.post(f"/leave/{lv['id']}/dean", json={"approve": True}, headers=env.staff("dean@iiitnr.edu.in"))
    assert r.json()["status"] == "pending_admin"


def test_late_leave_turns_review_into_leave(env, s1):
    office = env.staff("office@iiitnr.edu.in")
    env.clock.t = dt.datetime(2026, 11, 23, 18, 40)
    env.client.post("/admin/run-day-close?date=2026-11-23", headers=office)
    mine = lambda st="pending": [r for r in env.client.get(f"/admin/reviews?status={st}", headers=office).json()  # noqa: E731
                                 if r["scholar"]["email"] == "s1@iiitnr.edu.in"]
    assert len(mine()) == 1
    env.clock.t = dt.datetime(2026, 11, 24, 11, 0)
    lv = apply(s1, "MEDICAL", "2026-11-23", "2026-11-23").json()
    env.client.post(f"/leave/{lv['id']}/approve", json={"approve": True}, headers=env.staff("guide@iiitnr.edu.in"))
    env.client.post(f"/leave/{lv['id']}/confirm", json={"confirm": True}, headers=office)
    assert mine() == []
    assert mine("leave")[0]["date"] == "2026-11-23"
    # cancelling the leave sends the day back for review
    env.client.post(f"/leave/{lv['id']}/cancel", json={"approve": True, "note": "certificate invalid"},
                    headers=office)
    assert len(mine()) == 1


def test_withdraw_and_balance_release(env, s1):
    lv = apply(s1, "CASUAL", "2026-12-01", "2026-12-03").json()
    pools = {p["pool"]: p for p in s1.req("GET", "/leave/mine").json()["balances"]["pools"]}
    assert pools["ORDINARY"]["used"] == 3
    assert s1.req("POST", f"/leave/{lv['id']}/withdraw").json()["status"] == "withdrawn"
    pools = {p["pool"]: p for p in s1.req("GET", "/leave/mine").json()["balances"]["pools"]}
    assert pools["ORDINARY"]["used"] == 0 and pools["ORDINARY"]["left"] == 30


def test_admin_adjustment_and_settings(env, s2):
    office = env.staff("office@iiitnr.edu.in")
    r = env.client.post("/admin/leave-adjustments", json={"email": "s2@iiitnr.edu.in", "pool": "ORDINARY",
                                                          "days": 5, "remark": "Carried forward by order"},
                        headers=office)
    assert r.json()["leave_year_start"] == "2026-07-21"
    pools = {p["pool"]: p for p in s2.req("GET", "/leave/mine").json()["balances"]["pools"]}
    assert pools["ORDINARY"]["entitled"] == 35
    # rule numbers are settings
    assert env.client.put("/admin/settings/rules", json={"semester_cap_days": 20}, headers=office).status_code == 200
    assert apply(s2, "CASUAL", "2026-11-24", "2026-12-14").json()["days"] == 15
    assert apply(s2, "CASUAL", "2026-12-15", "2026-12-18").status_code == 200   # 19 <= 20
    assert code(env.client.put("/admin/settings/rules", json={"nope": 1}, headers=office)) == "UNKNOWN_SETTING"
    assert env.client.put("/admin/settings/rules", json={"semester_cap_days": 20},
                          headers=env.staff("guide@iiitnr.edu.in")).status_code == 403
