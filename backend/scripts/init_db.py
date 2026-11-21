"""Create the att_* and leave_* tables and the default windows.
Usage:  python -m scripts.init_db"""
from app.clock import ensure_windows
from app.db import Base, SessionLocal, engine
from app import models  # noqa: F401  (registers the tables)

if __name__ == "__main__":
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        ensure_windows(db)
    print("Tables ready. Windows: 09:30-10:00, 12:45-13:30, 17:45-18:30 (change in admin settings).")
