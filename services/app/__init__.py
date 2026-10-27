"""Clockifai services — application Flask (app factory).

Rôle volontairement limité : tout ce que Supabase (PostgREST + RLS) ne fait pas bien.
  * /api/exports/*   : CSV / XLSX / PDF des rapports
  * /api/invoices/*  : génération de factures PDF
  * /api/kiosk/*     : pointage par PIN sans session utilisateur
  * /api/jobs/*      : déclenchement manuel des tâches planifiées
  * /api/tokens      : jetons personnels (hooks Claude Code, extension VSCode, MCP)
  * /api/agents/*    : agents Claude retirés, restaurés par un admin
  * /api/activity/*  : événements d'activité et temps des agents Claude (plan 10)
  * /api/claude/*    : marketplace Claude Code de l'instance (plugin clockifai)
  * /api/health      : sonde

L'authentification s'appuie sur le JWT Supabase de l'utilisateur (voir auth.py).
L'accès aux données se fait en rôle service via psycopg, avec un contrôle explicite
de l'appartenance au workspace demandé.
"""

import logging

from flask import Flask, jsonify, request

from .config import Config
from .db import close_pool, init_pool


def create_app(config: type[Config] | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_object(config or Config)

    logging.basicConfig(level=app.config["LOG_LEVEL"], format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    if app.config["DATABASE_URL"]:
        init_pool(app.config["DATABASE_URL"])

    from .routes.activity import bp as activity_bp
    from .routes.agents import bp as agents_bp
    from .routes.assistant import bp as assistant_bp
    from .routes.claude import bp as claude_bp
    from .routes.exports import bp as exports_bp
    from .routes.health import bp as health_bp
    from .routes.invitations import bp as invitations_bp
    from .routes.invoices import bp as invoices_bp
    from .routes.jobs import bp as jobs_bp
    from .routes.kiosk import bp as kiosk_bp
    from .routes.tokens import bp as tokens_bp
    from .routes.traces import bp as traces_bp

    app.register_blueprint(health_bp, url_prefix="/api")
    app.register_blueprint(exports_bp, url_prefix="/api/exports")
    app.register_blueprint(jobs_bp, url_prefix="/api/jobs")
    app.register_blueprint(invitations_bp, url_prefix="/api/invitations")
    app.register_blueprint(kiosk_bp, url_prefix="/api/kiosk")
    app.register_blueprint(invoices_bp, url_prefix="/api/invoices")
    app.register_blueprint(tokens_bp, url_prefix="/api/tokens")
    app.register_blueprint(agents_bp, url_prefix="/api/agents")
    app.register_blueprint(activity_bp, url_prefix="/api/activity")
    app.register_blueprint(claude_bp, url_prefix="/api/claude")
    app.register_blueprint(traces_bp, url_prefix="/api/traces")
    app.register_blueprint(assistant_bp, url_prefix="/api/assistant")

    origins = {o.strip() for o in app.config["CORS_ORIGINS"].split(",") if o.strip()}

    @app.after_request
    def _cors(resp):
        # En production l'app web et /api partagent la même origine (Caddy) : CORS inutile.
        # En développement (app sur :3000, Flask sur :5050) on autorise les origines listées.
        origin = request.headers.get("Origin")
        if origin and (origin in origins or "*" in origins):
            resp.headers["Access-Control-Allow-Origin"] = origin
            resp.headers["Vary"] = "Origin"
            resp.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Kiosk-Token"
            resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
            resp.headers["Access-Control-Expose-Headers"] = "Content-Disposition"
        return resp

    @app.errorhandler(400)
    @app.errorhandler(401)
    @app.errorhandler(403)
    @app.errorhandler(404)
    @app.errorhandler(429)
    @app.errorhandler(502)
    def _json_error(err):  # pragma: no cover - trivial
        return jsonify(error=getattr(err, "description", str(err))), getattr(err, "code", 500)

    if app.config["JOBS_ENABLED"] and not app.testing:
        from .jobs.scheduler import start_scheduler

        start_scheduler(app)

    import atexit

    atexit.register(close_pool)
    return app
