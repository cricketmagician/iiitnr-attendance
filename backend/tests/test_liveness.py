"""Photo / screen check on the attendance selfie."""
import base64
import datetime as dt

import pytest

from app import face_service
from app.config import get_settings
from app.models import DayReview, Mark
from app.routers import attendance as att_router
from tests.test_face_verification import fake_model  # noqa: F401  (fixture)

SELFIE = base64.b64encode(b"\xff\xd8 test selfie " * 60).decode()


def code(r):
    return r.json()["detail"]["code"]


@pytest.fixture
def score(monkeypatch):
    """Set what the photo-check model returns."""
    box = {"v": 0.95}
    monkeypatch.setattr(att_router, "liveness_score", lambda raw: box["v"])
    return box


def _mark(s1):
    return s1.req("POST", "/att/mark", {"face_image": SELFIE})


def test_live_face_is_marked(env, s1, fake_model, score):  # noqa: F811
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    r = _mark(s1)
    assert r.status_code == 200 and r.json()["sent_to_office"] is False
    with env.Session() as db:
        assert db.query(Mark).one().live_score == pytest.approx(0.95)


def test_photo_gets_retries_then_goes_to_office(env, s1, fake_model, score):  # noqa: F811
    score["v"] = 0.08
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    assert code(_mark(s1)) == "LIVENESS_FAILED"
    assert code(_mark(s1)) == "LIVENESS_FAILED"
    r = _mark(s1)                                   # third try: saved, but does not count
    assert r.status_code == 200 and r.json()["sent_to_office"] is True
    with env.Session() as db:
        m = db.query(Mark).one()
        assert m.flagged_at is not None and m.flagged_by == "auto" and "photo" in m.flag_note
        rev = db.query(DayReview).one()
        assert rev.status == "pending" and "Photo check" in rev.remark and rev.sessions_marked == ""

    # The office sees the mark and its selfie in the review
    office = env.staff("office@iiitnr.edu.in")
    env.clock.t = dt.datetime(2026, 11, 23, 21, 0)
    rv = env.client.get("/admin/reviews", headers=office).json()
    marks = rv[0]["marks"]
    assert marks[0]["flagged"] and marks[0]["has_selfie"] and marks[0]["live_score"] == pytest.approx(0.08)
    assert env.client.get(f"/att/guard/marks/{marks[0]['id']}/selfie", headers=office).status_code == 200


def test_a_good_retry_after_a_bad_photo_counts(env, s1, fake_model, score):  # noqa: F811
    score["v"] = 0.1
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    assert code(_mark(s1)) == "LIVENESS_FAILED"
    score["v"] = 0.9                                 # real face, better light
    r = _mark(s1)
    assert r.status_code == 200 and r.json()["sent_to_office"] is False


def test_reject_mode_never_saves(env, s1, fake_model, score):  # noqa: F811
    get_settings().liveness_mode = "reject"
    score["v"] = 0.1
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    for _ in range(4):
        assert code(_mark(s1)) == "LIVENESS_FAILED"
    get_settings().liveness_mode = "review"


def test_missing_model_does_not_block(env, s1, fake_model, monkeypatch):  # noqa: F811
    monkeypatch.setattr(face_service, "_LIVENESS_PATH", face_service._MODELS_DIR / "nope.onnx")
    monkeypatch.setattr(face_service, "_liveness_net", None)
    monkeypatch.setattr(face_service, "_liveness_tried", False)
    env.clock.t = dt.datetime(2026, 11, 23, 9, 35)
    assert _mark(s1).status_code == 200
