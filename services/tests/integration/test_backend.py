"""Tests d'intégration contre la pile Docker locale (Supabase + Flask).

    make up && make test-integration

Ignorés si INTEGRATION=1 n'est pas défini. Lit deploy/.env pour les clés.
Vérifie : création auto du profil et du workspace, RLS multi-tenant, rôles,
résolution des conflits de chronomètre, verrouillage, export Flask.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
import uuid
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(os.environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

ROOT = Path(__file__).resolve().parents[3]


def _env() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (ROOT / "deploy" / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip().strip('"')
    return values


ENV = _env() if (ROOT / "deploy" / ".env").exists() else {}
SUPABASE = os.environ.get("SUPABASE_URL", "http://localhost:8000")
SERVICES = os.environ.get("SERVICES_URL", f"http://localhost:{ENV.get('SERVICES_PORT', '5050')}")
ANON = ENV.get("ANON_KEY", "")


def _call(method: str, url: str, token: str | None = None, body=None, headers=None):
    h = {"apikey": ANON, "Content-Type": "application/json", **(headers or {})}
    if token:
        h["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            ctype = resp.headers.get("Content-Type", "")
            return resp.status, (json.loads(raw) if raw and "json" in ctype else raw)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


def rest(method: str, path: str, token: str, body=None, prefer="return=representation"):
    return _call(method, f"{SUPABASE}/rest/v1/{path}", token, body, {"Prefer": prefer})


def signup(name: str) -> tuple[str, str]:
    email = f"{name}-{uuid.uuid4().hex[:8]}@test.local"
    status, data = _call("POST", f"{SUPABASE}/auth/v1/signup", None,
                         {"email": email, "password": "Passw0rd!Passw0rd", "data": {"display_name": name}})
    assert status == 200, data
    return data["access_token"], data["user"]["id"]


def iso(dt: datetime) -> str:
    return dt.astimezone(UTC).isoformat()


@pytest.fixture(scope="module")
def alice():
    token, uid = signup("alice")
    return {"token": token, "id": uid}


@pytest.fixture(scope="module")
def bob():
    token, uid = signup("bob")
    return {"token": token, "id": uid}


@pytest.fixture(scope="module")
def alice_ws(alice):
    status, rows = rest("GET", f"workspace_members?user_id=eq.{alice['id']}&select=workspace_id,role", alice["token"])
    assert status == 200 and len(rows) == 1, rows
    assert rows[0]["role"] == "owner"
    return rows[0]["workspace_id"]


def test_signup_creates_profile_and_personal_workspace(alice, alice_ws):
    status, rows = rest("GET", "profiles?select=id,display_name,default_workspace_id", alice["token"])
    assert status == 200 and rows[0]["display_name"] == "alice"
    assert rows[0]["default_workspace_id"] == alice_ws


def test_tenant_isolation(alice, bob, alice_ws):
    pid = str(uuid.uuid4())
    status, _ = rest("POST", "projects", alice["token"], {"id": pid, "workspace_id": alice_ws, "name": "Site web"})
    assert status == 201
    # Bob ne voit pas le projet d'Alice et ne peut pas écrire dans son workspace.
    status, rows = rest("GET", f"projects?id=eq.{pid}", bob["token"])
    assert status == 200 and rows == []
    status, err = rest("POST", "time_entries", bob["token"], {
        "workspace_id": alice_ws, "user_id": bob["id"], "start_at": iso(datetime.now(UTC)),
    })
    assert status in (401, 403) and err["code"] == "42501"


def test_running_timer_conflict_latest_wins(alice, alice_ws):
    now = datetime.now(UTC).replace(microsecond=0)
    a, b, c = (str(uuid.uuid4()) for _ in range(3))
    # A démarre à t-30min, puis B à t (autre appareil) → A est arrêté à t.
    assert rest("POST", "time_entries", alice["token"], {
        "id": a, "workspace_id": alice_ws, "user_id": alice["id"], "start_at": iso(now - timedelta(minutes=30))})[0] == 201
    assert rest("POST", "time_entries", alice["token"], {
        "id": b, "workspace_id": alice_ws, "user_id": alice["id"], "start_at": iso(now)})[0] == 201
    # C arrive en retard (créé hors ligne) mais a démarré à t-10min → enregistré terminé à t.
    assert rest("POST", "time_entries", alice["token"], {
        "id": c, "workspace_id": alice_ws, "user_id": alice["id"], "start_at": iso(now - timedelta(minutes=10))})[0] == 201

    _, rows = rest("GET", f"time_entries?id=in.({a},{b},{c})&select=id,end_at,duration_seconds", alice["token"])
    by_id = {r["id"]: r for r in rows}
    assert by_id[a]["duration_seconds"] == 30 * 60
    assert by_id[b]["end_at"] is None
    assert by_id[c]["duration_seconds"] == 10 * 60
    # Arrêt de B.
    status, _ = rest("PATCH", f"time_entries?id=eq.{b}", alice["token"], {"end_at": iso(now + timedelta(minutes=5))})
    assert status == 200


def test_parallel_timers_limit(bob):
    """0011 : `max_running_timers` généralise « le plus récent gagne » à N chronomètres."""
    token, uid = signup("parallel")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{uid}&select=workspace_id", token)
    wid = rows[0]["workspace_id"]
    assert rest("PATCH", f"workspaces?id=eq.{wid}", token, {"max_running_timers": 2})[0] == 200
    now = datetime.now(UTC).replace(microsecond=0)

    def start(minutes_ago: int) -> str:
        eid = str(uuid.uuid4())
        status, body = rest("POST", "time_entries", token, {
            "id": eid, "workspace_id": wid, "user_id": uid, "start_at": iso(now - timedelta(minutes=minutes_ago))})
        assert status == 201, body
        return eid

    def durations(*ids: str) -> dict:
        _, rows = rest("GET", f"time_entries?id=in.({','.join(ids)})&select=id,duration_seconds", token)
        return {r["id"]: r["duration_seconds"] for r in rows}

    a, b = start(30), start(20)
    c = start(0)   # limite atteinte : A, le plus ancien, s'arrête au début de C
    d = start(40)  # arrivé en retard, plus ancien que B et C : enregistré terminé au début de B
    assert durations(a, b, c, d) == {a: 30 * 60, b: None, c: None, d: 20 * 60}

    # Illimité : rien ne s'arrête.
    assert rest("PATCH", f"workspaces?id=eq.{wid}", token, {"max_running_timers": 0})[0] == 200
    e = start(5)
    assert durations(b, c, e) == {b: None, c: None, e: None}

    # Un simple membre ne change pas le réglage (la RLS filtre la ligne).
    assert rest("POST", "workspace_members", token,
                {"workspace_id": wid, "user_id": bob["id"], "role": "member", "display_name": "bob"})[0] == 201
    status, rows = rest("PATCH", f"workspaces?id=eq.{wid}", bob["token"], {"max_running_timers": 1})
    assert status == 200 and rows == []
    _, rows = rest("GET", f"workspaces?id=eq.{wid}&select=max_running_timers", token)
    assert rows == [{"max_running_timers": 0}]


def test_roles_and_visibility(alice, bob, alice_ws):
    # Alice (owner) ajoute Bob comme simple membre.
    status, rows = rest("POST", "workspace_members", alice["token"], {
        "workspace_id": alice_ws, "user_id": bob["id"], "role": "member", "display_name": "bob"})
    assert status == 201, rows
    member_id = rows[0]["id"]

    # Bob voit le référentiel mais pas les entrées d'Alice.
    status, rows = rest("GET", f"projects?workspace_id=eq.{alice_ws}", bob["token"])
    assert status == 200 and len(rows) >= 1
    status, rows = rest("GET", f"time_entries?workspace_id=eq.{alice_ws}&user_id=eq.{alice['id']}", bob["token"])
    assert status == 200 and rows == []

    # Bob ne peut pas s'auto-promouvoir.
    status, err = rest("PATCH", f"workspace_members?id=eq.{member_id}", bob["token"], {"role": "admin"})
    assert status in (401, 403) and err["code"] == "42501"

    # Bob ne peut pas créer de projet (réservé manager+).
    status, err = rest("POST", "projects", bob["token"], {"workspace_id": alice_ws, "name": "Pirate"})
    assert status in (401, 403)

    # Promu manager, Bob voit les entrées de l'équipe.
    assert rest("PATCH", f"workspace_members?id=eq.{member_id}", alice["token"], {"role": "manager"})[0] == 200
    status, rows = rest("GET", f"time_entries?workspace_id=eq.{alice_ws}&user_id=eq.{alice['id']}", bob["token"])
    assert status == 200 and len(rows) >= 3

    # Le dernier owner ne peut pas être rétrogradé.
    _, own = rest("GET", f"workspace_members?workspace_id=eq.{alice_ws}&user_id=eq.{alice['id']}", alice["token"])
    status, err = rest("PATCH", f"workspace_members?id=eq.{own[0]['id']}", alice["token"], {"role": "admin"})
    assert status >= 400 and err["code"] == "23514"


def test_locked_period(alice, bob, alice_ws):
    # Bob saisit une entrée d'hier, puis Alice verrouille jusqu'à aujourd'hui.
    eid = str(uuid.uuid4())
    yesterday = datetime.now(UTC) - timedelta(days=1)
    assert rest("POST", "time_entries", bob["token"], {
        "id": eid, "workspace_id": alice_ws, "user_id": bob["id"],
        "start_at": iso(yesterday), "end_at": iso(yesterday + timedelta(hours=1))})[0] == 201
    assert rest("PATCH", f"workspaces?id=eq.{alice_ws}", alice["token"],
                {"lock_entries_before": date.today().isoformat()})[0] == 200
    status, err = rest("PATCH", f"time_entries?id=eq.{eid}", bob["token"], {"description": "modifié"})
    assert status >= 400 and err["code"] == "42501"
    # Un admin peut toujours corriger.
    assert rest("PATCH", f"time_entries?id=eq.{eid}", alice["token"], {"description": "corrigé"})[0] == 200
    rest("PATCH", f"workspaces?id=eq.{alice_ws}", alice["token"], {"lock_entries_before": None})


def test_flask_export(alice, alice_ws):
    frm = (date.today() - timedelta(days=7)).isoformat()
    to = date.today().isoformat()
    status, body = _call("GET", f"{SERVICES}/api/exports/report?workspace_id={alice_ws}&from={frm}&to={to}&format=csv",
                         alice["token"])
    assert status == 200, body
    text = body.decode("utf-8-sig")
    assert text.startswith("Utilisateur;")
    assert len(text.strip().splitlines()) >= 4  # en-tête + entrées terminées

    status, body = _call("GET", f"{SERVICES}/api/exports/report?workspace_id={alice_ws}&format=xlsx", alice["token"])
    assert status == 200 and body[:2] == b"PK"
    status, body = _call("GET", f"{SERVICES}/api/exports/report?workspace_id={alice_ws}&format=pdf", alice["token"])
    assert status == 200 and body[:4] == b"%PDF"


def test_flask_export_uses_the_current_rate_of_an_entry_without_rate(alice, alice_ws):
    # Entrée saisie avant que le projet ait un taux : l'export prend le taux actuel, une entrée qui a le sien le garde.
    pid = str(uuid.uuid4())
    assert rest("POST", "projects", alice["token"], {"id": pid, "workspace_id": alice_ws, "name": "Taux tardif"})[0] == 201
    start = datetime.now(UTC).replace(microsecond=0) - timedelta(hours=3)
    for i, rate in enumerate([None, 9000]):
        assert rest("POST", "time_entries", alice["token"], {
            "id": str(uuid.uuid4()), "workspace_id": alice_ws, "user_id": alice["id"], "project_id": pid,
            "description": f"taux {rate}", "hourly_rate_cents": rate,
            "start_at": iso(start + timedelta(minutes=10 * i)), "end_at": iso(start + timedelta(minutes=10 * i + 5))})[0] == 201
    assert rest("PATCH", f"projects?id=eq.{pid}", alice["token"], {"hourly_rate_cents": 12345})[0] == 200

    day = start.date().isoformat()
    status, body = _call("GET", f"{SERVICES}/api/exports/report?workspace_id={alice_ws}&project_id={pid}"
                                f"&from={day}&to={date.today().isoformat()}&format=csv", alice["token"])
    assert status == 200, body
    header, *lines = body.decode("utf-8-sig").strip().splitlines()
    rate = header.split(";").index("Taux horaire")
    rates = {line.split(";")[6]: line.split(";")[rate] for line in lines}
    assert rates == {"taux None": "123,45", "taux 9000": "90,00"}


def test_flask_export_forbidden_for_outsider(alice_ws):
    token, _ = signup("eve")
    status, _ = _call("GET", f"{SERVICES}/api/exports/report?workspace_id={alice_ws}", token)
    assert status == 403


def upsert(path: str, token: str, body):
    """Même requête que le connecteur PowerSync de l'app (PUT → upsert PostgREST)."""
    return _call("POST", f"{SUPABASE}/rest/v1/{path}", token, body,
                 {"Prefer": "resolution=merge-duplicates,return=minimal"})


def test_connector_style_upserts():
    token, uid = signup("dave")
    wid = str(uuid.uuid4())
    # Création d'un workspace depuis l'app : l'auteur devient owner (trigger serveur).
    assert upsert("workspaces", token, {"id": wid, "name": "Équipe Dave", "created_by": uid})[0] == 201
    # Rejeu (réponse perdue côté client) : idempotent.
    assert upsert("workspaces", token, {"id": wid, "name": "Équipe Dave", "created_by": uid})[0] == 200
    _, rows = rest("GET", f"workspace_members?workspace_id=eq.{wid}&select=role", token)
    assert rows == [{"role": "owner"}]
    # Booléens SQLite (0/1) acceptés par Postgres.
    eid = str(uuid.uuid4())
    status, _ = upsert("time_entries", token, {
        "id": eid, "workspace_id": wid, "user_id": uid, "description": "",
        "start_at": datetime.now(UTC).isoformat(), "billable": 0, "locked": 0})
    assert status == 201
    _, rows = rest("GET", f"time_entries?id=eq.{eid}&select=billable,end_at", token)
    assert rows == [{"billable": False, "end_at": None}]

    # « Annuler » une suppression (plan 13, AppDatabase.restoreRow) : la ligne, déjà retirée de la base locale,
    # est réinsérée encore supprimée (PUT sans les colonnes nulles), puis rétablie (PATCH deleted_at nul).
    deleted = datetime.now(UTC).isoformat()
    assert rest("PATCH", f"time_entries?id=eq.{eid}", token, {"deleted_at": deleted})[0] in (200, 204)
    assert upsert("time_entries", token, {
        "id": eid, "workspace_id": wid, "user_id": uid, "description": "", "deleted_at": deleted,
        "start_at": datetime.now(UTC).isoformat(), "billable": 0, "locked": 0})[0] in (200, 201)
    assert rest("PATCH", f"time_entries?id=eq.{eid}", token, {"deleted_at": None})[0] in (200, 204)
    _, rows = rest("GET", f"time_entries?id=eq.{eid}&select=deleted_at", token)
    assert rows == [{"deleted_at": None}]


def test_invitations(alice, alice_ws):
    # Compte existant : ajout direct.
    token_f, fid = signup("frank")
    status, body = _call("POST", f"{SERVICES}/api/invitations", alice["token"],
                         {"workspace_id": alice_ws, "email": _email_of(token_f), "role": "manager"})
    assert status == 201, body
    assert body["created"] is False and body["user_id"] == fid
    assert body["invite_link"] is None and body["app_url"].startswith("http")
    _, rows = rest("GET", f"workspace_members?workspace_id=eq.{alice_ws}&user_id=eq.{fid}&select=role", alice["token"])
    assert rows == [{"role": "manager"}]

    # Pas de SMTP en dev : l'app le sait avant d'inviter.
    status, body = _call("GET", f"{SERVICES}/api/invitations/options?workspace_id={alice_ws}", alice["token"])
    assert status == 200 and body == {"email": False}

    # Nouveau compte : lien d'invitation renvoyé, avec ou sans email demandé.
    for send_email in (True, False):
        email = f"newbie-{uuid.uuid4().hex[:8]}@test.local"
        status, body = _call("POST", f"{SERVICES}/api/invitations", alice["token"],
                             {"workspace_id": alice_ws, "email": email, "send_email": send_email})
        assert status == 201, body
        assert body["created"] is True and body["emailed"] is False and body["invite_link"].startswith("http")

    # Un simple membre ne peut pas inviter.
    status, _ = _call("POST", f"{SERVICES}/api/invitations", token_f,
                      {"workspace_id": alice_ws, "email": "x@test.local"})
    assert status == 403
    status, _ = _call("GET", f"{SERVICES}/api/invitations/options?workspace_id={alice_ws}", token_f)
    assert status == 403


def _email_of(token: str) -> str:
    status, user = _call("GET", f"{SUPABASE}/auth/v1/user", token)
    assert status == 200
    return user["email"]
