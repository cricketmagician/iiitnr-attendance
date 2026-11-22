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

    # Google Workspace OAuth2 Client ID for @iiitnr.edu.in
    google_client_id: str = ""

    # Dev only: enables POST /auth/dev-token (password-less login), 24x7 windows and no
    # campus check. NEVER enable on a server reachable by scholars.
    dev_mode: bool = False

    # Device Lock: Enforces 1-phone per scholar via cryptographic hardware keys.
    # Only turn off on a local test machine.
    enforce_device_lock: bool = True

    # Guard kiosk: the QR endpoint is served only to a kiosk holding this key
    # (header X-Kiosk-Key) or to a logged-in admin/guard. Empty = kiosk key disabled.
    kiosk_key: str = ""
    # Key for signing guard QR codes. Empty = derived from jwt_secret (separate from it).
    qr_secret: str = ""
    # Marking requires a scanned guard QR and a live selfie.
    require_guard_qr: bool = True
    require_face: bool = True

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


WEAK_SECRETS = {"", "change-me", "CHANGE_ME_same_secret_as_the_login_service",
                "iiitnr-attendance-production-secret-key-2026", "iiitnr-attendance-secure-jwt-token-key-2026"}


def check_production_settings(s: "Settings") -> None:
    """Refuse to start a non-dev server with a missing, default or leaked secret."""
    if s.dev_mode:
        return
    if not s.jwt_public_key and (s.jwt_secret in WEAK_SECRETS or len(s.jwt_secret) < 32):
        raise RuntimeError("ATT_JWT_SECRET is missing, a default, a leaked value or shorter than 32 characters. "
                           "Generate one with: python -c 'import secrets; print(secrets.token_hex(32))'")


@lru_cache
def get_settings() -> Settings:
    return Settings()
