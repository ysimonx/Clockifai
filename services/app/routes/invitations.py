"""Invitations dans un workspace (admin+).

GET  /api/invitations/options?workspace_id=…  → {"email": bool} (un SMTP est-il configuré ?)
POST /api/invitations  {"workspace_id", "email", "role"?: "member"|"manager"|"admin", "display_name"?,
                        "send_email"?: bool}

* Compte existant : ajout direct au workspace (ou réactivation).
* Nouveau compte : lien d'invitation généré par l'API admin GoTrue (`generate_link`).
* Email envoyé si un SMTP est configuré et que l'admin le demande (`send_email`, vrai par défaut). Le lien
  (activation, ou adresse de l'app pour un compte existant) est toujours renvoyé, pour être copié et transmis.
"""

from __future__ import annotations

import logging

from flask import Blueprint, abort, current_app, g, jsonify, request

from ..auth import require_user, require_workspace
from ..db import connection
from ..services.gotrue import gotrue_admin
from ..services.mailer import mail_configured, send_mail

log = logging.getLogger(__name__)
bp = Blueprint("invitations", __name__)

_ROLES = ("member", "manager", "admin")


@bp.get("/options")
@require_user
@require_workspace("admin")
def options():
    return jsonify(email=mail_configured())


@bp.post("")
@require_user
@require_workspace("admin")
def invite():
    body = request.get_json(silent=True) or {}
    email = (body.get("email") or "").strip().lower()
    role = body.get("role") or "member"
    if "@" not in email:
        abort(400, "valid email required")
    if role not in _ROLES:
        abort(400, f"role must be one of {_ROLES}")
    display_name = (body.get("display_name") or email.split("@")[0]).strip()
    send_email = body.get("send_email") is not False

    with connection() as conn:
        ws = conn.execute("select name from public.workspaces where id = %s", (g.workspace_id,)).fetchone()
        user = conn.execute("select id from auth.users where lower(email) = %s", (email,)).fetchone()

    link = None
    created = False
    if user is None:
        res = gotrue_admin("admin/generate_link", {
            "type": "invite",
            "email": email,
            "data": {"display_name": display_name},
            "redirect_to": current_app.config["APP_PUBLIC_URL"],
        })
        user_id = res.get("id") or (res.get("user") or {}).get("id")
        link = res.get("action_link") or (res.get("properties") or {}).get("action_link")
        if not user_id:
            abort(502, "auth service did not return a user id")
        created = True
    else:
        user_id = str(user["id"])

    with connection() as conn:
        prof = conn.execute("select display_name, email from public.profiles where id = %s", (user_id,)).fetchone()
        conn.execute(
            """
            insert into public.workspace_members (workspace_id, user_id, role, display_name, email)
            values (%(wid)s, %(uid)s, %(role)s, %(name)s, %(email)s)
            on conflict (workspace_id, user_id) do update
               set status = 'active', deleted_at = null,
                   role = case when workspace_members.role = 'owner' then 'owner' else excluded.role end
            """,
            {"wid": g.workspace_id, "uid": user_id, "role": role,
             "name": (prof or {}).get("display_name") or display_name, "email": email},
        )
        conn.commit()

    ws_name = ws["name"] if ws else "Clockifai"
    app_url = current_app.config["APP_PUBLIC_URL"]
    if created:
        subject = f"Invitation à rejoindre « {ws_name} » sur Clockifai"
        text = (f"Bonjour,\n\nVous êtes invité(e) à rejoindre l'espace « {ws_name} » sur Clockifai.\n"
                f"Activez votre compte avec ce lien :\n{link}\n\nPuis définissez votre mot de passe dans les paramètres.\n")
    else:
        subject = f"Vous avez été ajouté(e) à « {ws_name} » sur Clockifai"
        text = f"Bonjour,\n\nVous avez maintenant accès à l'espace « {ws_name} » : {app_url}\n"
    emailed = send_mail(email, subject, text) if send_email else False

    return jsonify(user_id=user_id, created=created, emailed=emailed, invite_link=link, app_url=app_url), 201
