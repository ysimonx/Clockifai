from typing import ClassVar

import pytest

from app import create_app
from app.config import TestConfig
from app.services import mailer


class FakeSMTP:
    sent: ClassVar[list] = []

    def __init__(self, host, port, timeout=None):
        self.host, self.port = host, port

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def ehlo(self):
        pass

    def has_extn(self, name):
        return False

    def login(self, user, password):
        pass

    def send_message(self, msg):
        FakeSMTP.sent.append(msg)


@pytest.fixture
def app(monkeypatch):
    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    FakeSMTP.sent = []
    app = create_app(TestConfig)
    app.config.update(SMTP_HOST="smtp.test", SMTP_PORT=587, SMTP_SENDER="clockifai@kysoe.com")
    return app


def test_expediteur_avec_son_nom(app):
    with app.app_context():
        assert mailer.send_mail("camille@example.com", "Invitation", "Bonjour")
    assert FakeSMTP.sent[0]["From"] == "Clockifai <clockifai@kysoe.com>"


def test_expediteur_sans_nom(app):
    app.config["SMTP_SENDER_NAME"] = ""
    with app.app_context():
        assert mailer.send_mail("camille@example.com", "Invitation", "Bonjour")
    assert FakeSMTP.sent[0]["From"] == "clockifai@kysoe.com"


def test_sans_smtp_rien_n_est_envoye(app):
    app.config["SMTP_HOST"] = "supabase-mail"
    with app.app_context():
        assert not mailer.send_mail("camille@example.com", "Invitation", "Bonjour")
    assert FakeSMTP.sent == []
