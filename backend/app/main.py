"""IIITNR Scholar Attendance & Leave service.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8040
Mount behind the IIITNR app's existing API gateway/nginx, e.g. at /attendance/.
"""
from __future__ import annotations

import asyncio
import datetime as dt
import logging
import os
from contextlib import asynccontextmanager

import jwt
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from .clock import clock
from .config import get_settings
from .db import Base, engine
from .routers import admin, attendance, auth, leave
from .security import api_error

log = logging.getLogger("att")


class DevLogin(BaseModel):
    email: str


async def _scheduler():
    """Optional in-process day-close at 18:35 on weekdays (use cron instead if you prefer)."""
    from .jobs import close_day
    done: set[dt.date] = set()
    while True:
        now = clock.now()
        if now.weekday() < 5 and now.time() >= dt.time(18, 35) and now.date() not in done:
            try:
                await asyncio.to_thread(close_day, now.date())
                done.add(now.date())
            except Exception:
                log.exception("close-day failed")
        await asyncio.sleep(60)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if os.environ.get("ATT_CREATE_TABLES", "true").lower() == "true":
        Base.metadata.create_all(engine)
        try:
            from .db import SessionLocal
            from .models import Person
            with SessionLocal() as db:
                if db.query(Person).count() == 0:
                    samples = [
                        Person(email="scholar1@iiitnr.edu.in", name="Aarav Sharma", roll_no="PHD202401", programme="PhD", funding="institute", roles="scholar", active=True),
                        Person(email="mtech1@iiitnr.edu.in", name="Priya Patel", roll_no="MT202401", programme="MTech", funding="institute", roles="scholar", active=True),
                        Person(email="guide1@iiitnr.edu.in", name="Dr. Rajesh Guide", roll_no="FAC001", programme="Faculty", funding="institute", roles="guide", active=True),
                        Person(email="hod.sm@iiitnr.edu.in", name="HoD SM Dept", roll_no="HOD001", programme="Faculty", funding="institute", roles="hod", active=True),
                        Person(email="dean.ri@iiitnr.edu.in", name="Dean R&I", roll_no="DEAN001", programme="Dean", funding="institute", roles="dean", active=True),
                        Person(email="attendance.office@iiitnr.edu.in", name="Attendance Office", roll_no="ADMIN001", programme="Staff", funding="institute", roles="admin", active=True),
                    ]
                    db.add_all(samples)
                    db.commit()
        except Exception:
            log.exception("DB seeding error")
    task = None
    if os.environ.get("ATT_RUN_SCHEDULER", "false").lower() == "true":
        task = asyncio.create_task(_scheduler())
    yield
    if task:
        task.cancel()


def create_app() -> FastAPI:
    app = FastAPI(title="IIITNR Scholar Attendance & Leave", version="1.0", lifespan=lifespan)
    app.include_router(attendance.router)
    app.include_router(auth.router)
    app.include_router(leave.router)
    app.include_router(admin.router)

    @app.get("/health")
    def health():
        return {"ok": True, "server_time": clock.now().isoformat(timespec="seconds")}

    @app.get("/guard", response_class=HTMLResponse, tags=["kiosk"])
    def guard_kiosk():
        """Web Kiosk for Guard Desk displaying dynamic 3-second rotating QR code."""
        from .guard_kiosk_html import GUARD_KIOSK_HTML
        return HTMLResponse(content=GUARD_KIOSK_HTML)

    @app.get("/", response_class=HTMLResponse, tags=["mobile"])
    @app.get("/m", response_class=HTMLResponse, tags=["mobile"])
    @app.get("/mobile", response_class=HTMLResponse, tags=["mobile"])
    def mobile_web():
        """Mobile Web & iOS Attendance & Face Verification Portal."""
        from .mobile_web_html import MOBILE_WEB_HTML
        return HTMLResponse(content=MOBILE_WEB_HTML)

    @app.get("/download/app.apk", tags=["download"])
    @app.get("/download/apk", tags=["download"])
    @app.get("/app.apk", tags=["download"])
    def download_apk():
        """Direct 1-click download of the Android APK."""
        from fastapi.responses import FileResponse
        candidates = [
            os.path.abspath(os.path.join(os.path.dirname(__file__), "../../flutter/build/app/outputs/flutter-apk/app-release.apk")),
            os.path.abspath(os.path.join(os.path.dirname(__file__), "../../flutter/build/app/outputs/apk/release/app-release.apk")),
            os.path.abspath(os.path.join(os.path.dirname(__file__), "../../flutter/build/app/outputs/flutter-apk/app-debug.apk")),
            "/Users/neerajsingh/Documents/IIIT NR Attendance/iiitnr-scholar-attendance/flutter/build/app/outputs/apk/release/app-release.apk",
        ]
        for p in candidates:
            if os.path.exists(p) and os.path.getsize(p) > 1000:
                return FileResponse(
                    p,
                    media_type="application/vnd.android.package-archive",
                    filename="IIITNR-Scholar-Attendance.apk"
                )
        from fastapi.responses import RedirectResponse
        fallback_url = os.environ.get(
            "ATT_APK_URL",
            "https://github.com/cricketmagician/iiitnr-attendance/releases/latest/download/app-release.apk"
        )
        return RedirectResponse(url=fallback_url, status_code=302)

    return app


app = create_app()
