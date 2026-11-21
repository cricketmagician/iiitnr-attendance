"""Service settings, read from environment variables (prefix ATT_) or a .env file."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ATT_", env_file=".env", extra="ignore")

    # Database: any SQLAlchemy URL, e.g.
    #   mysql+pymysql://att:pass@localhost/iiitnr
    #   postgresql+psycopg://att:pass@localhost/iiitnr
    database_url: str = "sqlite:///./att_dev.db"

    timezone: str = "Asia/Kolkata"
    # First day the app replaces the paper register (YYYY-MM-DD). Earlier days show blank.
    go_live_date: str = ""
    institute_domain: str = "iiitnr.edu.in"

    # Login tokens issued by the existing IIITNR app's login service.
    # HS256 with a shared secret, or RS256/ES256 with the issuer's public key (PEM).
    jwt_algorithm: str = "HS256"
    jwt_secret: str = "change-me"
    jwt_public_key: str = ""
    jwt_email_claim: str = "email"
    jwt_audience: str = ""

    # Dev only: enables POST /auth/dev-token. Never true on the live server.
    dev_mode: bool = False

    # Campus network check. If the API sits behind a reverse proxy (nginx),
    # set trust_proxy=true so the client IP is read from X-Forwarded-For.
    trust_proxy: bool = False
    # Fallback ranges used only when the att_campus_network table is empty.
    campus_cidrs: str = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

    # If the gateway forwards e.g. /attendance/att/mark to this service without stripping
    # the prefix, set path_prefix=/attendance so signatures are checked on /att/mark.
    path_prefix: str = ""

    # Signed-request tolerance
    signature_max_skew_seconds: int = 120

    # Uploads (leave attachments)
    upload_dir: str = "./uploads"
    max_upload_mb: int = 5

    # Admin e-mail for the daily list (optional; logged if SMTP is not set)
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    admin_notify_email: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
