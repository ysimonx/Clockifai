"""Envoi d'emails via le SMTP partagé avec GoTrue. Sans SMTP configuré : journalise et renvoie False."""

from __future__ import annotations

import logging
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr

from flask import current_app

log = logging.getLogger(__name__)

_PLACEHOLDER_HOSTS = {"", "supabase-mail", "localhost"}


def mail_configured() -> bool:
    """Vrai si l'installation a un vrai serveur SMTP (pas l'hôte de remplacement de la pile locale)."""
    return current_app.config.get("SMTP_HOST", "") not in _PLACEHOLDER_HOSTS


def send_mail(to: str, subject: str, text: str, attachments: list[tuple[str, bytes, str]] = ()) -> bool:
    """Envoie un email texte, avec des pièces jointes (nom, contenu, type MIME « application/pdf »…)."""
    cfg = current_app.config
    host = cfg.get("SMTP_HOST", "")
    if not mail_configured():
        log.info("SMTP non configuré : email non envoyé à %s (%s)", to, subject)
        return False
    msg = EmailMessage()
    name = cfg.get("SMTP_SENDER_NAME", "")
    msg["From"] = formataddr((name, cfg["SMTP_SENDER"])) if name else cfg["SMTP_SENDER"]
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(text)
    for filename, data, mimetype in attachments:
        maintype, subtype = mimetype.split("/", 1)
        msg.add_attachment(data, maintype=maintype, subtype=subtype, filename=filename)
    port = cfg["SMTP_PORT"]
    try:
        if port == 465:
            with smtplib.SMTP_SSL(host, port, context=ssl.create_default_context(), timeout=20) as s:
                if cfg["SMTP_USER"]:
                    s.login(cfg["SMTP_USER"], cfg["SMTP_PASS"])
                s.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=20) as s:
                s.ehlo()
                if s.has_extn("starttls"):
                    s.starttls(context=ssl.create_default_context())
                if cfg["SMTP_USER"]:
                    s.login(cfg["SMTP_USER"], cfg["SMTP_PASS"])
                s.send_message(msg)
        return True
    except Exception:
        log.exception("échec d'envoi d'email à %s", to)
        return False
