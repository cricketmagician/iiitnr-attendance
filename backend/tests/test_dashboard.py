from app.models import Person
from tests.test_leave import apply


def test_old_role_names_still_work():
    assert Person(email="x", name="x", roles="guide").has("supervisor")
    assert Person(email="x", name="x", roles="dean, hod").role_list == ["dean_ri", "hod"]


def test_dashboard_per_role(env, s1, s2):
    apply(s1, "CASUAL", "2026-11-27", "2026-11-27")

    sup = env.client.get("/admin/dashboard", headers=env.staff("guide@iiitnr.edu.in")).json()
    assert sup["role"] == "supervisor" and sup["scholars"] == 2
    assert sup["pending"] == {"leave_supervisor": 1}
    assert {r["name"] for r in sup["roster"]} == {"Scholar One", "Scholar Two"}

    other = env.client.get("/admin/dashboard", headers=env.staff("other@iiitnr.edu.in")).json()
    assert other["scholars"] == 0 and other["pending"] == {"leave_supervisor": 0}

    dean = env.client.get("/admin/dashboard", headers=env.staff("dean@iiitnr.edu.in")).json()
    assert dean["role"] == "dean_ri" and dean["scholars"] == 2 and "leave_dean" in dean["pending"]

    office = env.client.get("/admin/dashboard", headers=env.staff("office@iiitnr.edu.in")).json()
    assert set(office["pending"]) == {"leave_admin", "reviews", "devices"}
    assert len(office["today"]["sessions"]) == 3


def test_dashboard_refuses_scholars(env, s1):
    r = env.client.get("/admin/dashboard", headers=env.staff("s1@iiitnr.edu.in"))
    assert r.status_code == 403


def test_dean_can_read_register(env):
    r = env.client.get("/admin/register", params={"m": "2026-11"}, headers=env.staff("dean@iiitnr.edu.in"))
    assert r.status_code == 200 and len(r.json()) == 2
