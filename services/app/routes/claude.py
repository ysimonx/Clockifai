"""Marketplace Claude Code de l'instance (plan 10, §5, §6.1) et connexion d'un poste par lien (plan 21).

La marketplace est publique et sans jeton : le plugin ne contient aucun secret.

  GET /api/claude/marketplace.json      → marketplace « clockifai », qui référence l'archive ci-dessous
  GET /api/claude/clockifai-plugin.zip  → integrations/claude-code/, l'adresse de l'instance dans `metadata.url`

Claude Code n'accepte qu'une archive zip servie en HTTPS. Son empreinte SHA-256, dans la marketplace, sert aussi de
version du plugin : un plugin modifié par une mise à jour de l'instance est proposé aux postes.

Un poste sans jeton demande un lien, que Claude donne à l'utilisateur, et retire son jeton une fois le lien validé :

  POST /api/claude/link                 {machine}          → {url, poll, expires_in}  (sans compte)
  POST /api/claude/link/poll            {poll}             → {status: pending} ou {status: approved, token}  (sans compte)
  GET  /api/claude/link/<code>                             → {machine}  (JWT)
  POST /api/claude/link/<code>/approve  {workspace_id, name} (JWT)
"""

from __future__ import annotations

import hashlib
import io
import json
import re
import secrets
import threading
import zipfile
from pathlib import Path

from flask import Blueprint, Response, abort, current_app, g, jsonify, request

from ..auth import hash_token, require_user, require_workspace
from ..db import connection
from ..services.agents import issue_token

bp = Blueprint("claude", __name__)

PLUGIN_FILES = (".claude-plugin/plugin.json", ".mcp.json", "hooks/hooks.json", "scripts/clockifai_hook.py",
                "scripts/clockifai_mcp.py")
ARCHIVE = "clockifai-plugin.zip"
_HOST = re.compile(r"^(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(?::\d{1,5})?$")
_CACHE_MAX = 8
_cache: dict[str, bytes] = {}
_lock = threading.Lock()
LINK_TTL = 600        # secondes pour ouvrir le lien et le valider
LINK_MAX = 500        # liens vivants : la création est publique, le lien ne sert à rien sans validation
NAME_MAX = 80


def build_plugin_zip(plugin_dir: Path, url: str) -> bytes:
    """Archive reproductible (dates et droits fixes) : même contenu, même empreinte, d'un démarrage à l'autre."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name in PLUGIN_FILES:
            data = (plugin_dir / name).read_bytes()
            if name == ".claude-plugin/plugin.json":
                manifest = json.loads(data)
                manifest["metadata"]["url"] = url
                data = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = (0o100755 if name.startswith("scripts/") else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    return buf.getvalue()


def _base_url() -> str:
    """Adresse publique telle que le poste l'a jointe (Caddy transmet l'hôte et le protocole d'origine)."""
    proto = request.headers.get("X-Forwarded-Proto", request.scheme).split(",")[0].strip()
    if proto not in ("http", "https"):
        proto = request.scheme
    if not _HOST.match(request.host):
        abort(400, "invalid host")
    return f"{proto}://{request.host}"


def _archive(base: str) -> bytes:
    plugin_dir = Path(current_app.config["CLAUDE_PLUGIN_DIR"])
    if not (plugin_dir / PLUGIN_FILES[0]).is_file():
        abort(404, "plugin not available on this instance")
    with _lock:
        data = _cache.get(base)
        if data is None:
            data = build_plugin_zip(plugin_dir, base)
            if len(_cache) < _CACHE_MAX:
                _cache[base] = data
    return data


@bp.get("/marketplace.json")
def marketplace():
    base = _base_url()
    data = _archive(base)
    manifest = json.loads((Path(current_app.config["CLAUDE_PLUGIN_DIR"]) / PLUGIN_FILES[0]).read_text("utf-8"))
    resp = jsonify(
        name="clockifai",
        owner={"name": "Clockifai"},
        description="Plugin Clockifai de cette instance",
        plugins=[{
            "name": manifest["name"],
            "description": manifest.get("description", ""),
            "source": {"source": "archive", "url": f"{base}/api/claude/{ARCHIVE}",
                       "sha256": hashlib.sha256(data).hexdigest()},
        }],
    )
    resp.headers["Cache-Control"] = "no-cache"
    return resp


@bp.get(f"/{ARCHIVE}")
def archive():
    resp = Response(_archive(_base_url()), mimetype="application/zip")
    resp.headers["Content-Disposition"] = f"attachment; filename={ARCHIVE}"
    resp.headers["Cache-Control"] = "no-cache"
    return resp


def _clean(value: object) -> str:
    return " ".join(str(value or "").split())[:NAME_MAX]


@bp.post("/link")
def create_link():
    code, poll = secrets.token_urlsafe(16), secrets.token_urlsafe(32)
    machine = _clean((request.get_json(silent=True) or {}).get("machine"))
    with connection() as conn:
        conn.execute("delete from clockifai_private.device_links where expires_at < now()")
        alive = conn.execute("select count(*) as n from clockifai_private.device_links").fetchone()["n"]
        if alive >= LINK_MAX:
            abort(429, "too many pending links")
        conn.execute(
            "insert into clockifai_private.device_links (code_hash, poll_hash, machine, expires_at) "
            "values (%s, %s, %s, now() + make_interval(secs => %s))",
            (hash_token(code), hash_token(poll), machine, LINK_TTL),
        )
        conn.commit()
    url = f"{current_app.config['APP_PUBLIC_URL'].rstrip('/')}/connect/{code}"
    return jsonify(url=url, poll=poll, expires_in=LINK_TTL), 201


@bp.post("/link/poll")
def poll_link():
    """Une seule remise : `delete … returning` départage deux hooks simultanés. Le jeton naît ici, jamais stocké."""
    poll = (request.get_json(silent=True) or {}).get("poll")
    if not isinstance(poll, str) or not poll:
        abort(400, "poll is required")
    digest = hash_token(poll)
    with connection() as conn:
        link = conn.execute(
            "delete from clockifai_private.device_links "
            "where poll_hash = %s and approved_at is not null and expires_at > now() "
            "returning workspace_id, user_id, name",
            (digest,),
        ).fetchone()
        if link is None:
            pending = conn.execute(
                "select 1 from clockifai_private.device_links where poll_hash = %s and expires_at > now()", (digest,)
            ).fetchone()
            if pending is None:
                abort(404, "link expired or already used")
            return jsonify(status="pending")
        # Un poste relié sous le même nom le remplace : ordinateur réinstallé, plugin réinstallé.
        conn.execute(
            "update clockifai_private.api_tokens set revoked_at = now() "
            "where workspace_id = %s and user_id = %s and name = %s and revoked_at is null",
            (link["workspace_id"], link["user_id"], link["name"]),
        )
        issued = issue_token(conn, str(link["workspace_id"]), str(link["user_id"]), link["name"])
        conn.commit()
    return jsonify(status="approved", token=issued["token"])


@bp.get("/link/<code>")
@require_user
def link_info(code: str):
    with connection() as conn:
        row = conn.execute(
            "select machine from clockifai_private.device_links "
            "where code_hash = %s and approved_at is null and expires_at > now()",
            (hash_token(code),),
        ).fetchone()
    if row is None:
        abort(404, "link expired or already used")
    return jsonify(machine=row["machine"])


@bp.post("/link/<code>/approve")
@require_user
@require_workspace()
def approve_link(code: str):
    name = _clean((request.get_json(silent=True) or {}).get("name"))
    with connection() as conn:
        row = conn.execute(
            """
            update clockifai_private.device_links
               set workspace_id = %s, user_id = %s, name = coalesce(nullif(%s, ''), nullif(machine, ''), 'Poste'),
                   approved_at = now(), expires_at = now() + interval '1 day'
             where code_hash = %s and approved_at is null and expires_at > now()
            returning name
            """,
            (g.workspace_id, g.user.id, name, hash_token(code)),
        ).fetchone()
        conn.commit()
    if row is None:
        abort(404, "link expired or already used")
    return jsonify(approved=True, name=row["name"])
