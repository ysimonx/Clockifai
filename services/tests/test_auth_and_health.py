import datetime as dt

import jwt
import pytest

from app import create_app
from app.config import TestConfig


@pytest.fixture
def client():
    app = create_app(TestConfig)
    with app.test_client() as c:
        yield c


def _token(sub="11111111-1111-1111-1111-111111111111", secret=TestConfig.SUPABASE_JWT_SECRET, **extra):
    now = dt.datetime.now(dt.UTC)
    payload = {"sub": sub, "aud": "authenticated", "role": "authenticated",
               "iat": now, "exp": now + dt.timedelta(hours=1), **extra}
    return jwt.encode(payload, secret, algorithm="HS256")


def test_health_without_database(client):
    rv = client.get("/api/health")
    assert rv.status_code == 200
    assert rv.get_json()["status"] == "ok"


def test_export_requires_token(client):
    rv = client.get("/api/exports/report?workspace_id=x")
    assert rv.status_code == 401


def test_export_rejects_bad_signature(client):
    rv = client.get("/api/exports/report?workspace_id=x",
                    headers={"Authorization": f"Bearer {_token(secret='wrong-secret-wrong-secret-wrong-secret')}"})
    assert rv.status_code == 401


def test_export_requires_workspace_id(client):
    rv = client.get("/api/exports/report", headers={"Authorization": f"Bearer {_token()}"})
    assert rv.status_code == 400
