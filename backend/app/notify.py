"""E-mail to the central admin (optional). Without SMTP settings, messages are only logged."""
from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage

from .config import get_settings

log = logging.getLogger("att.notify")


def send_mail(to: str, subject: str, body: str) -> bool:
    s = get_settings()
    if not (s.smtp_host and to):
        log.info("mail (not sent, SMTP not set) to=%s subject=%s\n%s", to, subject, body)
        return False
    msg = EmailMessage()
    msg["From"] = s.smtp_from or s.smtp_user
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    try:
        with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=20) as smtp:
            smtp.starttls()
            if s.smtp_user:
                smtp.login(s.smtp_user, s.smtp_password)
            smtp.send_message(msg)
        return True
    except Exception:  # never fail the caller because mail failed
        log.exception("mail failed to=%s", to)
        return False
