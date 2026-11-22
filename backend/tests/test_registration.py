"""Scholar registration: fill form -> office approves -> scholar can use attendance and leave."""
from app.models import Person

FORM = {
    "name": "New Scholar", "roll_no": "phd2026x1", "programme": "PhD", "department": "S&M",
    "supervisor_email": "guide@iiitnr.edu.in", "joining_date": "2026-08-01", "funding": "institute",
    "phone": "98765 43210", "personal_email": "new.scholar@gmail.com", "address": "Hostel B-12, Naya Raipur",
}


def code(r):
    return r.json()["detail"]["code"]


def _new(env, email="new@iiitnr.edu.in"):
    with env.Session() as db:
        db.add(Person(email=email, name="Google Name", roles="scholar", registration_status="none"))
        db.commit()
    return env.phone(email)


def test_new_scholar_registers_and_office_approves(env):
    ph = _new(env)
    me = ph.req("GET", "/att/me").json()
    assert me["is_scholar"] is False and me["registration"] == {"status": "none", "note": "", "needed": True}
    # Not registered: no attendance yet
    assert ph.req("GET", "/att/today").status_code == 403

    opts = ph.req("GET", "/registration/options").json()
    assert {s["email"] for s in opts["supervisors"]} == {"guide@iiitnr.edu.in", "other@iiitnr.edu.in"}

    r = ph.req("POST", "/registration", FORM)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["status"] == "pending" and j["roll_no"] == "PHD2026X1" and j["phone"] == "9876543210"
    assert j["supervisor_name"] == "Guide"

    office = env.staff("office@iiitnr.edu.in")
    lst = env.client.get("/admin/scholars?status=pending", headers=office).json()
    assert lst["counts"]["pending"] == 1 and lst["scholars"][0]["address"] == "Hostel B-12, Naya Raipur"
    dash = env.client.get("/admin/dashboard", headers=office).json()
    assert dash["pending"]["registrations"] == 1

    # Office fixes a detail, then approves
    pid = j["id"]
    fixed = {**FORM, "address": "Hostel C-3"}
    assert env.client.put(f"/admin/scholars/{pid}", json=fixed, headers=office).json()["address"] == "Hostel C-3"
    r = env.client.post(f"/admin/scholars/{pid}/decision", json={"approve": True}, headers=office)
    assert r.json()["status"] == "approved"

    # Now a scholar: the phone lock applies, so this phone is registered next
    assert code(ph.req("GET", "/att/me")) == "DEVICE_NOT_REGISTERED"
    assert ph.register().json()["status"] == "active"
    me = ph.req("GET", "/att/me").json()
    assert me["is_scholar"] is True and me["registration"]["needed"] is False
    # Approved but already registered: the scholar cannot resubmit
    assert code(ph.req("POST", "/registration", FORM)) == "REG_APPROVED"


def test_reject_needs_a_note_and_scholar_can_resubmit(env):
    ph = _new(env)
    pid = ph.req("POST", "/registration", FORM).json()["id"]
    office = env.staff("office@iiitnr.edu.in")
    assert code(env.client.post(f"/admin/scholars/{pid}/decision", json={"approve": False}, headers=office)) == "REG_NOTE"
    r = env.client.post(f"/admin/scholars/{pid}/decision", json={"approve": False, "note": "Wrong roll number"},
                        headers=office)
    assert r.json()["status"] == "rejected"
    me = ph.req("GET", "/att/me").json()
    assert me["registration"]["status"] == "rejected" and me["registration"]["note"] == "Wrong roll number"
    assert ph.req("POST", "/registration", {**FORM, "roll_no": "PHD2026X2"}).json()["status"] == "pending"


def test_mtech_has_no_supervisor_and_leave_goes_to_office(env):
    ph = _new(env)
    form = {**FORM, "programme": "MTech", "roll_no": "MT2026X1", "supervisor_email": "guide@iiitnr.edu.in"}
    j = ph.req("POST", "/registration", form).json()
    assert j["supervisor_email"] == ""          # ignored for MTech
    office = env.staff("office@iiitnr.edu.in")
    env.client.post(f"/admin/scholars/{j['id']}/decision", json={"approve": True}, headers=office)
    assert ph.register().json()["status"] == "active"
    r = ph.req("POST", "/leave", {"leave_type": "CASUAL", "from_date": "2026-11-27", "to_date": "2026-11-27",
                                  "reason": "Going home"})
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "pending_admin"


def test_form_checks(env, s1):
    ph = _new(env)
    assert code(ph.req("POST", "/registration", {**FORM, "supervisor_email": ""})) == "REG_SUPERVISOR"
    assert code(ph.req("POST", "/registration", {**FORM, "supervisor_email": "dean@iiitnr.edu.in"})) == "REG_SUPERVISOR"
    assert code(ph.req("POST", "/registration", {**FORM, "phone": "12345abcde"})) == "REG_PHONE"
    assert code(ph.req("POST", "/registration", {**FORM, "joining_date": "2030-01-01"})) == "REG_JOINING"
    assert code(ph.req("POST", "/registration", {**FORM, "roll_no": "p1"})) == "REG_ROLL_TAKEN"  # s1's roll no
    assert code(ph.req("POST", "/registration", {**FORM, "programme": "BTech"})) == "REG_PROGRAMME"


def test_only_office_sees_scholar_details(env):
    _new(env)
    assert env.client.get("/admin/scholars", headers=env.staff("guide@iiitnr.edu.in")).status_code == 403
    assert env.client.get("/admin/scholars", headers=env.staff("office@iiitnr.edu.in")).status_code == 200


def test_imported_scholars_stay_approved(env, s1):
    me = s1.req("GET", "/att/me").json()
    assert me["is_scholar"] is True and me["registration"]["status"] == "approved"
