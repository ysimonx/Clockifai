"""Marketplace Claude Code de l'instance (plan 10, §5, §6.1). Publique et sans jeton : le plugin ne contient aucun secret.

  GET /api/claude/marketplace.json      → marketplace « clockifai », qui référence l'archive ci-dessous
  GET /api/claude/clockifai-plugin.zip  → integrations/claude-code/, l'adresse de l'instance en valeur par défaut

Claude Code n'accepte qu'une archive zip servie en HTTPS. Son empreinte SHA-256, dans la marketplace, sert aussi de
version du plugin : un plugin modifié par une mise à jour de l'instance est proposé aux postes.
"""

from __future__ import annotations

import hashlib
import io
import json
import re
import threading
import zipfile
from pathlib import Path

from flask import Blueprint, Response, abort, current_app, jsonify, request

bp = Blueprint("claude", __name__)

PLUGIN_FILES = (".claude-plugin/plugin.json", "hooks/hooks.json", "scripts/clockifai_hook.py")
ARCHIVE = "clockifai-plugin.zip"
_HOST = re.compile(r"^(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(?::\d{1,5})?$")
_CACHE_MAX = 8
_cache: dict[str, bytes] = {}
_lock = threading.Lock()


def build_plugin_zip(plugin_dir: Path, url: str) -> bytes:
    """Archive reproductible (dates et droits fixes) : même contenu, même empreinte, d'un démarrage à l'autre."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name in PLUGIN_FILES:
            data = (plugin_dir / name).read_bytes()
            if name == ".claude-plugin/plugin.json":
                manifest = json.loads(data)
                manifest["userConfig"]["url"]["default"] = url
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
