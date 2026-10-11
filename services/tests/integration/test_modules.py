"""Règles serveur des modules : approbations, absences, facturation, PIN kiosque, planning."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from .test_backend import SUPABASE, _call, iso, rest, signup, upsert

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


@pytest.fixture(scope="module")
def team():
    """Un workspace avec une owner (manager+) et un membre."""
    boss_t, boss = signup("boss")
    worker_t, worker = signup("worker")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{boss}&select=workspace_id", boss_t)
    wid = rows[0]["workspace_id"]
    status, _ = rest("POST", "workspace_members", boss_t,
                     {"workspace_id": wid, "user_id": worker, "role": "member", "display_name": "worker"})
    assert status == 201
    return {"wid": wid, "boss": (boss_t, boss), "worker": (worker_t, worker)}


def _entry(token, wid, uid, start: datetime, minutes=60, **extra):
    eid = str(uuid.uuid4())
    status, body = rest("POST", "time_entries", token, {
        "id": eid, "workspace_id": wid, "user_id": uid,
        "start_at": iso(start), "end_at": iso(start + timedelta(minutes=minutes)), **extra})
    assert status == 201, body
    return eid


def test_timesheet_approval_locks_and_reopens(team):
    wid = team["wid"]
    wt, w = team["worker"]
    bt, _ = team["boss"]
    monday = date.today() - timedelta(days=date.today().weekday() + 7)   # semaine dernière
    eid = _entry(wt, wid, w, datetime.combine(monday, datetime.min.time(), UTC).replace(hour=9))

    sid = str(uuid.uuid4())
    period = {"period_start": monday.isoformat(), "period_end": (monday + timedelta(days=6)).isoformat()}
    assert upsert("timesheet_submissions", wt, {"id": sid, "workspace_id": wid, "user_id": w, **period})[0] == 201
    # Le membre ne peut pas s'auto-approuver.
    status, err = rest("PATCH", f"timesheet_submissions?id=eq.{sid}", wt, {"status": "approved"})
    assert status >= 400 and err["code"] == "42501"
    # Le manager approuve → entrées verrouillées.
    assert rest("PATCH", f"timesheet_submissions?id=eq.{sid}", bt, {"status": "approved"})[0] == 200
    _, rows = rest("GET", f"time_entries?id=eq.{eid}&select=locked", wt)
    assert rows == [{"locked": True}]
    _, sub = rest("GET", f"timesheet_submissions?id=eq.{sid}&select=decided_by,decided_at", wt)
    assert sub[0]["decided_by"] == team["boss"][1] and sub[0]["decided_at"]
    # Plus de modification ni d'ajout dans la période pour le membre.
    status, err = rest("PATCH", f"time_entries?id=eq.{eid}", wt, {"description": "triche"})
    assert status >= 400 and err["code"] == "42501"
    status, err = rest("POST", "time_entries", wt, {
        "workspace_id": wid, "user_id": w,
        "start_at": iso(datetime.combine(monday, datetime.min.time(), UTC).replace(hour=14)),
        "end_at": iso(datetime.combine(monday, datetime.min.time(), UTC).replace(hour=15))})
    assert status >= 400 and err["code"] == "42501"
    # Réouverture (rejet) par le manager → déverrouillage.
    assert rest("PATCH", f"timesheet_submissions?id=eq.{sid}", bt, {"status": "rejected", "decision_note": "à revoir"})[0] == 200
    _, rows = rest("GET", f"time_entries?id=eq.{eid}&select=locked", wt)
    assert rows == [{"locked": False}]
    assert rest("PATCH", f"time_entries?id=eq.{eid}", wt, {"description": "corrigé"})[0] == 200


def test_time_off_workflow(team):
    wid = team["wid"]
    wt, w = team["worker"]
    bt, _ = team["boss"]
    pid, auto = str(uuid.uuid4()), str(uuid.uuid4())
    assert rest("POST", "time_off_policies", bt, {"id": pid, "workspace_id": wid, "name": "Congés payés", "annual_allowance": 25})[0] == 201
    assert rest("POST", "time_off_policies", bt, {"id": auto, "workspace_id": wid, "name": "Télétravail", "requires_approval": False})[0] == 201
    # Un membre ne crée pas de politique.
    assert rest("POST", "time_off_policies", wt, {"workspace_id": wid, "name": "Pirate"})[0] >= 400

    start = date.today() + timedelta(days=30)
    rid = str(uuid.uuid4())
    assert upsert("time_off_requests", wt, {"id": rid, "workspace_id": wid, "user_id": w, "policy_id": pid,
                                            "start_date": start.isoformat(), "end_date": (start + timedelta(days=4)).isoformat(),
                                            "amount": 5})[0] == 201
    status, err = rest("PATCH", f"time_off_requests?id=eq.{rid}", wt, {"status": "approved"})
    assert status >= 400 and err["code"] == "42501"
    assert rest("PATCH", f"time_off_requests?id=eq.{rid}", bt, {"status": "approved"})[0] == 200
    # Annulation par le demandeur toujours possible.
    assert rest("PATCH", f"time_off_requests?id=eq.{rid}", wt, {"status": "cancelled"})[0] == 200

    rid2 = str(uuid.uuid4())
    assert upsert("time_off_requests", wt, {"id": rid2, "workspace_id": wid, "user_id": w, "policy_id": auto,
                                             "start_date": start.isoformat(), "end_date": start.isoformat(), "amount": 1})[0] == 201
    _, rows = rest("GET", f"time_off_requests?id=eq.{rid2}&select=status", wt)
    assert rows == [{"status": "approved"}]


def test_invoices_numbering_totals_and_rights(team):
    wid = team["wid"]
    wt, w = team["worker"]
    bt, _ = team["boss"]
    eid = _entry(wt, wid, w, datetime.now(UTC) - timedelta(hours=3))
    inv1, inv2 = str(uuid.uuid4()), str(uuid.uuid4())
    assert upsert("invoices", bt, {"id": inv1, "workspace_id": wid, "tax_percent": 20})[0] == 201
    assert upsert("invoices", bt, {"id": inv2, "workspace_id": wid})[0] == 201
    _, rows = rest("GET", f"invoices?id=in.({inv1},{inv2})&select=id,number&order=number", bt)
    year = date.today().year
    assert [r["number"] for r in rows] == [f"F-{year}-0001", f"F-{year}-0002"]

    assert upsert("invoice_items", bt, {"id": str(uuid.uuid4()), "workspace_id": wid, "invoice_id": inv1,
                                         "description": "Dev", "quantity": 2.5, "unit_price_cents": 8000})[0] == 201
    _, rows = rest("GET", f"invoices?id=eq.{inv1}&select=subtotal_cents,tax_cents,total_cents", bt)
    assert rows == [{"subtotal_cents": 20000, "tax_cents": 4000, "total_cents": 24000}]

    # Un membre ne voit pas les factures.
    _, rows = rest("GET", f"invoices?workspace_id=eq.{wid}", wt)
    assert rows == []
    # Une entrée facturée n'est plus modifiable par son auteur.
    assert upsert("invoice_entries", bt, {"id": str(uuid.uuid4()), "workspace_id": wid, "invoice_id": inv1, "time_entry_id": eid})[0] == 201
    status, err = rest("PATCH", f"time_entries?id=eq.{eid}", wt, {"description": "après facture"})
    assert status >= 400 and err["code"] == "42501"
    # Facture annulée → modifiable à nouveau.
    assert rest("PATCH", f"invoices?id=eq.{inv1}", bt, {"status": "void"})[0] == 200
    assert rest("PATCH", f"time_entries?id=eq.{eid}", wt, {"description": "après annulation"})[0] == 200


def test_kiosk_pin_is_private(team):
    wid = team["wid"]
    wt, _ = team["worker"]
    status, _ = _call("POST", f"{SUPABASE}/rest/v1/rpc/set_kiosk_pin", wt, {"p_workspace_id": wid, "p_pin": "4321"})
    assert status in (200, 204)
    status, body = _call("POST", f"{SUPABASE}/rest/v1/rpc/has_kiosk_pin", wt, {"p_workspace_id": wid})
    assert status == 200 and body is True
    status, _ = _call("POST", f"{SUPABASE}/rest/v1/rpc/set_kiosk_pin", wt, {"p_workspace_id": wid, "p_pin": "12"})
    assert status >= 400
    # La table des PIN n'est pas exposée par l'API.
    status, _ = rest("GET", "member_pins", wt)
    assert status >= 400


def test_schedule_rights(team):
    wid = team["wid"]
    wt, w = team["worker"]
    bt, _ = team["boss"]
    d = date.today()
    body = {"workspace_id": wid, "user_id": w, "start_date": d.isoformat(), "end_date": (d + timedelta(days=2)).isoformat(), "hours_per_day": 7}
    assert rest("POST", "schedule_assignments", wt, body)[0] >= 400
    assert rest("POST", "schedule_assignments", bt, body)[0] == 201
    _, rows = rest("GET", f"schedule_assignments?user_id=eq.{w}", wt)
    assert len(rows) == 1


def test_kiosk_device_and_punch(team):
    from .test_backend import SERVICES
    wid = team["wid"]
    bt, _ = team["boss"]
    wt, w = team["worker"]
    # Le membre définit son PIN (fait aussi dans test_kiosk_pin_is_private, refait ici pour l'isolement).
    _call("POST", f"{SUPABASE}/rest/v1/rpc/set_kiosk_pin", wt, {"p_workspace_id": wid, "p_pin": "2468"})
    # Un membre ne peut pas créer d'appareil.
    assert _call("POST", f"{SERVICES}/api/kiosk/devices", wt, {"workspace_id": wid, "name": "x"})[0] == 403
    status, dev = _call("POST", f"{SERVICES}/api/kiosk/devices", bt, {"workspace_id": wid, "name": "Atelier"})
    assert status == 201 and dev["token"].startswith("kio_")
    h = {"X-Kiosk-Token": dev["token"]}

    def kiosk(method, path, body=None):
        return _call(method, f"{SERVICES}/api/kiosk{path}", None, body, h)

    status, st = kiosk("GET", "/state")
    assert status == 200 and any(m["user_id"] == w and m["has_pin"] for m in st["members"])
    assert kiosk("POST", "/punch", {"user_id": w, "pin": "0000"})[0] == 403
    status, res = kiosk("POST", "/punch", {"user_id": w, "pin": "2468"})
    assert status == 200 and res["action"] == "in"
    _, rows = rest("GET", f"time_entries?id=eq.{res['entry_id']}&select=end_at", wt)
    assert rows == [{"end_at": None}]
    status, res2 = kiosk("POST", "/punch", {"user_id": w, "pin": "2468"})
    assert status == 200 and res2["action"] == "out" and res2["entry_id"] == res["entry_id"]
    # Révocation → le jeton ne fonctionne plus.
    assert _call("DELETE", f"{SERVICES}/api/kiosk/devices/{dev['id']}?workspace_id={wid}", bt)[0] == 200
    assert kiosk("GET", "/state")[0] == 401


def test_invoice_pdf(team):
    from .test_backend import SERVICES
    wid = team["wid"]
    bt, _ = team["boss"]
    wt, _ = team["worker"]
    inv = str(uuid.uuid4())
    assert upsert("invoices", bt, {"id": inv, "workspace_id": wid, "tax_percent": 20})[0] == 201
    assert upsert("invoice_items", bt, {"id": str(uuid.uuid4()), "workspace_id": wid, "invoice_id": inv,
                                         "description": "Montage échafaudage", "quantity": 3, "unit_price_cents": 4500})[0] == 201
    status, body = _call("GET", f"{SERVICES}/api/invoices/{inv}/pdf?workspace_id={wid}", bt)
    assert status == 200 and body[:4] == b"%PDF"
    assert _call("GET", f"{SERVICES}/api/invoices/{inv}/pdf?workspace_id={wid}", wt)[0] == 403
