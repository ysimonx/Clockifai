"""« Demander à Clockifai » (plans/13-ux-moderne.md, lot 12).

  GET  /api/assistant/status                              → {enabled}
  POST /api/assistant/ask  {workspace_id, question, history?} → {answer, proposals, refused}

Désactivé sans `ANTHROPIC_API_KEY` (503 `assistant_disabled`). Claude ne reçoit que des agrégats et le référentiel
(services/assistant.py) ; une proposition de modification n'écrit rien, l'app l'applique si la personne le décide.
"""

from __future__ import annotations

import logging
from datetime import datetime

import anthropic
from flask import Blueprint, current_app, g, jsonify, request

from ..auth import require_user, require_workspace
from ..db import connection
from ..services import assistant
from ..services.profiles import user_tz

bp = Blueprint("assistant", __name__)
log = logging.getLogger(__name__)

_client: anthropic.Anthropic | None = None


def client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        _client = anthropic.Anthropic(api_key=current_app.config["ANTHROPIC_API_KEY"], timeout=90.0, max_retries=2)
    return _client


@bp.get("/status")
@require_user
def status():
    return jsonify(enabled=bool(current_app.config["ANTHROPIC_API_KEY"]))


@bp.post("/ask")
@require_user
@require_workspace()
def ask():
    if not current_app.config["ANTHROPIC_API_KEY"]:
        return jsonify(error="assistant_disabled"), 503
    body = request.get_json(silent=True) or {}
    question = str(body.get("question") or "").strip()[:2000]
    if not question:
        return jsonify(error="question_required"), 400
    history = body.get("history") if isinstance(body.get("history"), list) else []
    if not assistant.allow(g.user.id):
        return jsonify(error="rate_limited"), 429
    with connection() as conn:
        zone = user_tz(conn, g.user.id)
        tz, today = zone.key, datetime.now(zone).date()
        scope = assistant.scope_for(conn, g.workspace_id, g.user.id, g.workspace_role)
        try:
            result = assistant.ask(
                client(), conn, scope, question=question, history=history, tz=tz, today=today,
                model=current_app.config["ASSISTANT_MODEL"], effort=current_app.config["ASSISTANT_EFFORT"],
            )
        except anthropic.RateLimitError:
            return jsonify(error="rate_limited"), 429
        except (anthropic.APIStatusError, anthropic.APIConnectionError) as err:
            log.warning("assistant : API Anthropic indisponible (%s)", err)
            return jsonify(error="assistant_unavailable"), 502
    return jsonify(answer=result.get("answer"), proposals=result.get("proposals", []), refused=result.get("refused", False))
