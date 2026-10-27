"""Rapports enregistrés et lien public (plans/18-rapports-presence-alertes-partage.md, lot 3), de bout en bout."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from .test_backend import SERVICES, _call, iso, rest, signup

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
