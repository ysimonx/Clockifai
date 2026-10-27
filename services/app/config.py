"""Configuration par variables d'environnement (voir deploy/.env.example)."""

import os
from pathlib import Path


def _bool(name: str, default: bool) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-only-change-me")
    LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()

    # Postgres (rôle postgres : contourne la RLS → contrôle d'accès explicite dans auth.py)
    DATABASE_URL = os.environ.get("DATABASE_URL", "")

    # Supabase
    SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://kong:8000")
    SUPABASE_JWT_SECRET = os.environ.get("SUPABASE_JWT_SECRET", "")
    SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    # JWKS (clés asymétriques ES256) : utilisé si SUPABASE_JWT_SECRET est vide
    SUPABASE_JWKS_URL = os.environ.get("SUPABASE_JWKS_URL", f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json")

    # Emails (même SMTP que GoTrue)
    SMTP_HOST = os.environ.get("SMTP_HOST", "")
    SMTP_PORT = int(os.environ.get("SMTP_PORT", "587") or 587)
    SMTP_USER = os.environ.get("SMTP_USER", "")
    SMTP_PASS = os.environ.get("SMTP_PASS", "")
    SMTP_SENDER = os.environ.get("SMTP_SENDER", "clockifai@example.com")
    SMTP_SENDER_NAME = os.environ.get("SMTP_SENDER_NAME", "Clockifai")  # nom affiché, comme pour GoTrue
    APP_PUBLIC_URL = os.environ.get("APP_PUBLIC_URL", "http://localhost:3000")

    # Origines autorisées (CORS) pour l'app web servie sur un autre port en développement
    CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "http://localhost:3000")

    # Jobs planifiés
    JOBS_ENABLED = _bool("JOBS_ENABLED", True)
    JOB_AUTOSTOP_INTERVAL_MIN = int(os.environ.get("JOB_AUTOSTOP_INTERVAL_MIN", "5"))
    JOB_PURGE_DELETED_AFTER_DAYS = int(os.environ.get("JOB_PURGE_DELETED_AFTER_DAYS", "30"))

    # Plugin Claude Code servi par /api/claude (copié dans l'image, sinon lu dans le dépôt)
    CLAUDE_PLUGIN_DIR = os.environ.get("CLAUDE_PLUGIN_DIR") or str(
        Path(__file__).resolve().parents[2] / "integrations" / "claude-code")

    # Assistant « Demander à Clockifai » (plan 13, lot 12) : désactivé sans clé d'API Anthropic
    ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
    ASSISTANT_MODEL = os.environ.get("ASSISTANT_MODEL", "claude-opus-5-5")
    ASSISTANT_EFFORT = os.environ.get("ASSISTANT_EFFORT", "low")

    TESTING = False


class TestConfig(Config):
    TESTING = True
    JOBS_ENABLED = False
    DATABASE_URL = os.environ.get("TEST_DATABASE_URL", "")
    SUPABASE_JWT_SECRET = "test-secret-test-secret-test-secret-123"
