"""Mode kiosque : pointage par PIN sur un appareil partagé (tablette à l'entrée de l'atelier…).

Administration (JWT utilisateur, admin du workspace) :
  POST   /api/kiosk/devices            {workspace_id, name}  → {id, token}   (jeton affiché une seule fois)
  GET    /api/kiosk/devices?workspace_id=…
  DELETE /api/kiosk/devices/<id>?workspace_id=…

Appareil (en-tête X-Kiosk-Token, aucun compte utilisateur sur la tablette) :
  GET  /api/kiosk/state                → workspace, membres (avec chronomètre en cours), projets
  POST /api/kiosk/punch {user_id, pin, project_id?}  → démarre ou arrête le chronomètre du membre
"""

from __future__ import annotations

import hashlib
import secrets
import threading
import time
from functools import wraps

from flask import Blueprint, abort, g, jsonify, request

from ..auth import require_user, require_workspace
from ..db import connection, fetch_all

bp = Blueprint("kiosk", __name__)

# Anti force brute : 5 échecs → blocage 5 minutes par (appareil, membre).
_MAX_FAILS, _LOCK_SECONDS = 5, 300
_fails: dict[tuple[str, str], tuple[int, float]] = {}
_fails_lock = threading.Lock()


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---------------------------------------------------------------- administration
@bp.post("/devices")
@require_user
@require_workspace("admin")
def create_device():
    name = ((request.get_json(silent=True) or {}).get("name") or "Kiosque").strip()[:80]
    token = "kio_" + secrets.token_urlsafe(32)
    with connection() as conn:
        row = conn.execute(
            "insert into public.kiosk_devices (workspace_id, name, token_hash, created_by) values (%s, %s, %s, %s) returning id",
            (g.workspace_id, name, _hash(token), g.user.id),
        ).fetchone()
        conn.commit()
    return jsonify(id=str(row["id"]), name=name, token=token), 201


@bp.get("/devices")
@require_user
@require_workspace("admin")
def list_devices():
    rows = fetch_all(
        "select id, name, last_seen_at, created_at from public.kiosk_devices "
        "where workspace_id = %s and deleted_at is null order by created_at",
        (g.workspace_id,),
    )
    return jsonify(devices=[{**r, "id": str(r["id"])} for r in rows])


@bp.delete("/devices/<device_id>")
@require_user
@require_workspace("admin")
def revoke_device(device_id: str):
    with connection() as conn:
        n = conn.execute(
            "update public.kiosk_devices set deleted_at = now() where id = %s and workspace_id = %s and deleted_at is null",
            (device_id, g.workspace_id),
        ).rowcount
        conn.commit()
    if not n:
        abort(404, "device not found")
    return jsonify(revoked=True)


# ---------------------------------------------------------------- appareil
def require_device(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = request.headers.get("X-Kiosk-Token", "")
        if not token:
            abort(401, "missing kiosk token")
        with connection() as conn:
            dev = conn.execute(
                "update public.kiosk_devices set last_seen_at = now() where token_hash = %s and deleted_at is null "
                "returning id, workspace_id, name",
                (_hash(token),),
            ).fetchone()
            conn.commit()
        if dev is None:
            abort(401, "invalid kiosk token")
        g.device_id, g.workspace_id = str(dev["id"]), str(dev["workspace_id"])
        return fn(*args, **kwargs)

    return wrapper


@bp.get("/state")
@require_device
def state():
    ws = fetch_all("select name, currency from public.workspaces where id = %s", (g.workspace_id,))
    members = fetch_all(
        """
        select m.user_id, m.display_name,
               exists (select 1 from clockifai_private.member_pins p
                        where p.workspace_id = m.workspace_id and p.user_id = m.user_id) as has_pin,
               te.start_at as running_since, pr.name as running_project
          from public.workspace_members m
          -- Le plus récent seulement : plusieurs chronomètres peuvent tourner (0011).
          left join lateral (
                select t.start_at, t.project_id from public.time_entries t
                 where t.workspace_id = m.workspace_id and t.user_id = m.user_id
                   and t.end_at is null and t.deleted_at is null
                 order by t.start_at desc limit 1) te on true
          left join public.projects pr on pr.id = te.project_id
         where m.workspace_id = %s and m.status = 'active' and m.deleted_at is null
         order by lower(m.display_name)
        """,
        (g.workspace_id,),
    )
    projects = fetch_all(
        "select id, name, color from public.projects where workspace_id = %s and deleted_at is null and not archived order by lower(name)",
        (g.workspace_id,),
    )
    return jsonify(
        workspace=ws[0] if ws else None,
        members=[{**m, "user_id": str(m["user_id"]),
                  "running_since": m["running_since"].isoformat() if m["running_since"] else None} for m in members],
        projects=[{**p, "id": str(p["id"])} for p in projects],
    )


@bp.post("/punch")
@require_device
def punch():
    body = request.get_json(silent=True) or {}
    user_id, pin, project_id = body.get("user_id"), str(body.get("pin") or ""), body.get("project_id")
    if not user_id or not pin:
        abort(400, "user_id and pin are required")

    key = (g.device_id, str(user_id))
    with _fails_lock:
        count, until = _fails.get(key, (0, 0.0))
        if until > time.time():
            abort(429, "too many attempts, try again later")

    with connection() as conn:
        ok = conn.execute(
            """
            select p.pin_hash = extensions.crypt(%s, p.pin_hash) as ok
              from clockifai_private.member_pins p
              join public.workspace_members m on m.workspace_id = p.workspace_id and m.user_id = p.user_id
             where p.workspace_id = %s and p.user_id = %s and m.status = 'active' and m.deleted_at is null
            """,
            (pin, g.workspace_id, user_id),
        ).fetchone()
        if not ok or not ok["ok"]:
            with _fails_lock:
                count = _fails.get(key, (0, 0.0))[0] + 1
                _fails[key] = (count, time.time() + _LOCK_SECONDS if count >= _MAX_FAILS else 0.0)
            abort(403, "wrong PIN")
        with _fails_lock:
            _fails.pop(key, None)

        # Le kiosque pointe la présence : la sortie arrête tous les chronomètres en cours.
        running = conn.execute(
            "select id from public.time_entries where workspace_id = %s and user_id = %s and end_at is null and deleted_at is null"
            " order by start_at desc",
            (g.workspace_id, user_id),
        ).fetchall()
        if running:
            conn.execute("update public.time_entries set end_at = now() where id = any(%s)", ([r["id"] for r in running],))
            action, entry_id = "out", running[0]["id"]
        else:
            rate = None
            billable = True
            if project_id:
                proj = conn.execute(
                    "select billable_default, hourly_rate_cents from public.projects where id = %s and workspace_id = %s",
                    (project_id, g.workspace_id),
                ).fetchone()
                if proj is None:
                    abort(400, "unknown project")
                billable, rate = proj["billable_default"], proj["hourly_rate_cents"]
            if rate is None:
                m = conn.execute(
                    "select hourly_rate_cents from public.workspace_members where workspace_id = %s and user_id = %s",
                    (g.workspace_id, user_id),
                ).fetchone()
                rate = m["hourly_rate_cents"] if m else None
            entry_id = conn.execute(
                """
                insert into public.time_entries (workspace_id, user_id, project_id, description, start_at, billable, hourly_rate_cents)
                values (%s, %s, %s, '', now(), %s, %s) returning id
                """,
                (g.workspace_id, user_id, project_id, billable, rate),
            ).fetchone()["id"]
            action = "in"
        conn.commit()
    return jsonify(action=action, entry_id=str(entry_id))
