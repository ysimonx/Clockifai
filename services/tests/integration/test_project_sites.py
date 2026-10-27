"""Présence chantier (plans/13-ux-moderne.md, lot 13) : position du chantier et règle d'arrondi, par la RLS."""

from __future__ import annotations

import uuid

import pytest

from .test_backend import rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


def test_site_position_and_rounding_rule():
    boss_t, boss = signup("conductrice")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{boss}&select=workspace_id", boss_t)
    wid = rows[0]["workspace_id"]
    mate_t, mate = signup("compagnon")
    assert rest("POST", "workspace_members", boss_t,
                {"workspace_id": wid, "user_id": mate, "role": "member", "display_name": "compagnon"})[0] == 201
    pid = str(uuid.uuid4())
    assert rest("POST", "projects", boss_t, {"id": pid, "workspace_id": wid, "name": "Chantier Dupuis"})[0] == 201

    # Le manager pose la position et le rayon ; le membre les lit (workspace_core), sans pouvoir les changer.
    site = {"site_lat": 48.8566, "site_lng": 2.3522, "site_radius": 200}
    status, rows = rest("PATCH", f"projects?id=eq.{pid}", boss_t, site)
    assert status == 200 and rows[0]["site_radius"] == 200
    _, rows = rest("GET", f"projects?id=eq.{pid}&select=site_lat,site_lng,site_radius", mate_t)
    assert rows == [site]
    status, rows = rest("PATCH", f"projects?id=eq.{pid}", mate_t, {"site_radius": 5000})
    assert status >= 400 or rows == []
    _, rows = rest("GET", f"projects?id=eq.{pid}&select=site_radius", boss_t)
    assert rows[0]["site_radius"] == 200

    # Contraintes : latitude sans longitude, hors limites, rayon trop petit.
    for bad in ({"site_lat": 48.0, "site_lng": None}, {"site_lat": 95.0}, {"site_radius": 10}):
        assert rest("PATCH", f"projects?id=eq.{pid}", boss_t, bad)[0] >= 400, bad

    # Règle de l'entreprise : nulle par défaut (heures détectées), 'planning' ou 'actual' seulement.
    _, rows = rest("GET", f"workspaces?id=eq.{wid}&select=presence_rounding", boss_t)
    assert rows == [{"presence_rounding": None}]
    assert rest("PATCH", f"workspaces?id=eq.{wid}", boss_t, {"presence_rounding": "planning"})[0] == 200
    assert rest("PATCH", f"workspaces?id=eq.{wid}", boss_t, {"presence_rounding": "arrondi"})[0] >= 400
