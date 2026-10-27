"""Rapports enregistrés et lien public (plans/18-rapports-presence-alertes-partage.md, lot 3), de bout en bout."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

import psycopg
import pytest
from flask import Flask
from psycopg.rows import dict_row

from app.services import shared_reports

from .test_backend import ENV, SERVICES, _call, iso, rest, signup

DSN = (f"postgresql://postgres.{ENV.get('POOLER_TENANT_ID', '')}:{ENV.get('POSTGRES_PASSWORD', '')}"
       f"@localhost:{ENV.get('POSTGRES_PORT', '5432')}/postgres")

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


def api(method: str, path: str, token: str | None, body=None):
    return _call(method, f"{SERVICES}{path}", token, body)


@pytest.fixture(scope="module")
def agency():
    boss_t, boss = signup("agence")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{boss}&select=workspace_id", boss_t)
    wid = rows[0]["workspace_id"]
    people = {"boss": (boss_t, boss)}
    for name, role in (("cheffe", "manager"), ("graphiste", "member")):
        t, uid = signup(name)
        assert rest("POST", "workspace_members", boss_t,
                    {"workspace_id": wid, "user_id": uid, "role": role, "display_name": name})[0] == 201
        people[name] = (t, uid)
    project = str(uuid.uuid4())
    assert rest("POST", "projects", boss_t, {"id": project, "workspace_id": wid, "name": "Site vitrine",
                                             "hourly_rate_cents": 8000})[0] == 201
    t, uid = people["graphiste"]
    start = datetime.now(UTC).replace(hour=8, minute=0, second=0, microsecond=0) - timedelta(days=1)
    assert rest("POST", "time_entries", t, {"workspace_id": wid, "user_id": uid, "project_id": project,
                                            "description": "Maquette page d'accueil", "start_at": iso(start),
                                            "end_at": iso(start + timedelta(hours=2)), "billable": True})[0] == 201
    return {"wid": wid, "project": project, **people}


def test_only_managers_save_reports(agency):
    t, _ = agency["graphiste"]
    status, _ = api("POST", "/api/reports/saved", t, {"workspace_id": agency["wid"], "name": "Le mien"})
    assert status == 403
    status, _ = api("GET", f"/api/reports/saved?workspace_id={agency['wid']}", t)
    assert status == 403


def test_public_link_lifecycle(agency):
    t, _ = agency["cheffe"]
    status, rep = api("POST", "/api/reports/saved", t, {
        "workspace_id": agency["wid"], "name": "Site vitrine — client", "period": "last_week",
        "filters": {"project_id": agency["project"]}, "public": True})
    assert status == 201, rep
    status, bad = api("POST", "/api/reports/saved", t, {"workspace_id": agency["wid"], "name": "x",
                                                         "filters": {"project_id": "pas-un-uuid"}})
    assert status == 400, bad

    # Hier peut tomber la semaine dernière ou cette semaine : on prend cette semaine si besoin.
    status, rep = api("PUT", f"/api/reports/saved/{rep['id']}", t, {"workspace_id": agency["wid"], "period": "custom",
                      "date_from": (datetime.now(UTC) - timedelta(days=3)).date().isoformat(),
                      "date_to": datetime.now(UTC).date().isoformat()})
    assert status == 200 and rep["public_path"], rep
    status, page = api("GET", rep["public_path"], None)
    page = page.decode()
    assert status == 200 and "Site vitrine — client" in page and "2:00" in page and "160,00" in page
    assert "Maquette page d'accueil" not in page, "pas de description sans le détail"

    status, rep = api("PUT", f"/api/reports/saved/{rep['id']}", t,
                      {"workspace_id": agency["wid"], "detailed": True, "show_amounts": False})
    status, page = api("GET", rep["public_path"], None)
    assert "Maquette page d" in page.decode() and "160,00" not in page.decode()

    status, pdf = api("GET", rep["public_path"] + "?format=pdf", None)
    assert status == 200 and pdf[:4] == b"%PDF"

    old = rep["public_path"]
    status, rep = api("PUT", f"/api/reports/saved/{rep['id']}", t, {"workspace_id": agency["wid"], "new_link": True})
    assert rep["public_path"] != old
    assert api("GET", old, None)[0] == 404
    assert api("GET", rep["public_path"], None)[0] == 200

    status, rep2 = api("PUT", f"/api/reports/saved/{rep['id']}", t, {"workspace_id": agency["wid"], "public": False})
    assert rep2["public_path"] is None and api("GET", rep["public_path"], None)[0] == 404

    status, listed = api("GET", f"/api/reports/saved?workspace_id={agency['wid']}", agency["boss"][0])
    assert [r["name"] for r in listed["reports"]] == ["Site vitrine — client"], "partagés entre managers"
    assert api("DELETE", f"/api/reports/saved/{rep['id']}?workspace_id={agency['wid']}", t)[0] == 204
    assert api("DELETE", f"/api/reports/saved/{rep['id']}?workspace_id={agency['wid']}", t)[0] == 404


def test_a_link_dies_with_its_creator_rights(agency):
    t, uid = agency["cheffe"]
    _, rep = api("POST", "/api/reports/saved", t, {"workspace_id": agency["wid"], "name": "Temporaire",
                                                     "public": True})
    assert api("GET", rep["public_path"], None)[0] == 200
    boss_t, _ = agency["boss"]
    assert rest("PATCH", f"workspace_members?workspace_id=eq.{agency['wid']}&user_id=eq.{uid}", boss_t,
                {"role": "member"})[0] == 200
    try:
        assert api("GET", rep["public_path"], None)[0] == 404
    finally:
        rest("PATCH", f"workspace_members?workspace_id=eq.{agency['wid']}&user_id=eq.{uid}", boss_t, {"role": "manager"})


def test_scheduled_email_goes_once_with_the_pdf(agency):
    t, _ = agency["cheffe"]
    name = f"Hebdo client {uuid.uuid4().hex[:6]}"
    status, rep = api("POST", "/api/reports/saved", t, {
        "workspace_id": agency["wid"], "name": name, "public": True, "schedule": "weekly",
        "recipients": ["Compta@ACME.example", "direction@acme.example"]})
    assert status == 201 and rep["schedule"] == "weekly", rep
    assert rep["recipients"] == ["compta@acme.example", "direction@acme.example"]
    bad, _ = api("PUT", f"/api/reports/saved/{rep['id']}", t, {"workspace_id": agency["wid"], "recipients": ["x"]})
    assert bad == 400

    # Lundi prochain, 9 h à Paris : la semaine en cours vient de finir, elle part ; la précédente comptait comme envoyée.
    paris = ZoneInfo("Europe/Paris")
    today = datetime.now(paris).date()
    monday = today + timedelta(days=7 - today.weekday())
    now = datetime.combine(monday, time(9), paris)
    sent = []

    def fake_send(to, subject, text, attachments):
        if name in subject:
            sent.append((to, subject, text, attachments))
        return True

    # WeasyPrint ne tourne que dans le conteneur : le PDF réel est vérifié par la route publique (?format=pdf).
    def fake_pdf(html):
        return b"%PDF " + html.encode()

    def send_due(at):
        shared_reports.send_due_reports(conn, at, "https://clockifai.example.fr", fake_send, pdf=fake_pdf)

    with psycopg.connect(DSN, row_factory=dict_row) as conn, Flask(__name__).app_context():
        send_due(now - timedelta(days=7))
        assert sent == [], "pas la semaine d'avant"
        send_due(now)
        assert [m[0] for m in sent] == ["compta@acme.example", "direction@acme.example"]
        _, _, text, [(filename, pdf, mimetype)] = sent[0]
        assert mimetype == "application/pdf" and filename.endswith(".pdf") and name in pdf.decode()
        assert "https://clockifai.example.fr/api/reports/public/" in text
        send_due(now + timedelta(hours=1))
        assert len(sent) == 2, "une seule fois"
    assert api("DELETE", f"/api/reports/saved/{rep['id']}?workspace_id={agency['wid']}", t)[0] == 204

