"""Chefs d'équipe : périmètre, saisie du temps pour autrui, traçabilité, approbations d'équipe, export.

Plan : plans/03-saisie-pour-autrui.md
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from .test_backend import ENV, SERVICES, SUPABASE, _call, iso, rest, signup, upsert

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


def _add_member(owner_t: str, wid: str, uid: str, name: str, role: str = "member") -> str:
    status, rows = rest("POST", "workspace_members", owner_t,
                        {"workspace_id": wid, "user_id": uid, "role": role, "display_name": name})
    assert status == 201, rows
    return rows[0]["id"]


@pytest.fixture(scope="module")
def crew():
    """Owner « patron » ; « chef » (simple membre) encadre le groupe A (ouvrier1) et ouvrier2 en direct ;
    « autre » est hors périmètre ; « adjoint » est manager du workspace."""
    owner_t, owner = signup("patron")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{owner}&select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    people = {"owner": (owner_t, owner)}
    member_ids = {}
    for name in ("chef", "ouvrier1", "ouvrier2", "autre", "adjoint"):
        t, uid = signup(name)
        people[name] = (t, uid)
        member_ids[name] = _add_member(owner_t, wid, uid, name, "manager" if name == "adjoint" else "member")

    gid = str(uuid.uuid4())
    assert rest("POST", "user_groups", owner_t, {"id": gid, "workspace_id": wid, "name": "Équipe A"})[0] == 201
    assert rest("POST", "user_group_members", owner_t,
                {"workspace_id": wid, "group_id": gid, "user_id": people["ouvrier1"][1]})[0] == 201
    chef = people["chef"][1]
    assert rest("POST", "team_manager_assignments", owner_t,
                {"workspace_id": wid, "manager_id": chef, "group_id": gid})[0] == 201
    assert rest("POST", "team_manager_assignments", owner_t,
                {"workspace_id": wid, "manager_id": chef, "user_id": people["ouvrier2"][1]})[0] == 201
    return {"wid": wid, "gid": gid, "people": people, "member_ids": member_ids}


def _set_option(crew, value: str):
    owner_t = crew["people"]["owner"][0]
    assert rest("PATCH", f"workspaces?id=eq.{crew['wid']}", owner_t, {"time_for_others": value})[0] == 200


def _entry_body(wid, uid, start: datetime, minutes=60, **extra):
    return {"id": str(uuid.uuid4()), "workspace_id": wid, "user_id": uid,
            "start_at": iso(start), "end_at": iso(start + timedelta(minutes=minutes)), **extra}


def _day(weeks_ago: int, hour: int) -> datetime:
    monday = date.today() - timedelta(days=date.today().weekday() + 7 * weeks_ago)
    return datetime.combine(monday, datetime.min.time(), UTC).replace(hour=hour)


def test_scope_is_computed(crew):
    chef_t, chef = crew["people"]["chef"]
    status, rows = rest("GET", f"team_scope?manager_id=eq.{chef}&select=user_id", chef_t)
    assert status == 200
    assert {r["user_id"] for r in rows} == {crew["people"]["ouvrier1"][1], crew["people"]["ouvrier2"][1]}
    # Personne n'écrit dans team_scope à la main.
    status, _ = rest("POST", "team_scope", chef_t,
                     {"workspace_id": crew["wid"], "manager_id": chef, "user_id": crew["people"]["autre"][1]})
    assert status >= 400


def test_only_admins_manage_groups(crew):
    chef_t, _ = crew["people"]["chef"]
    status, _ = rest("POST", "user_groups", chef_t, {"workspace_id": crew["wid"], "name": "Pirates"})
    assert status >= 400
    status, _ = rest("POST", "team_manager_assignments", chef_t,
                     {"workspace_id": crew["wid"], "manager_id": crew["people"]["chef"][1],
                      "user_id": crew["people"]["autre"][1]})
    assert status >= 400


def test_group_from_another_workspace_is_rejected(crew):
    other_t, _ = signup("voisin")
    _, rows = rest("GET", "workspace_members?select=workspace_id", other_t)
    other_wid = rows[0]["workspace_id"]
    status, err = rest("POST", "user_group_members", other_t,
                       {"workspace_id": other_wid, "group_id": crew["gid"], "user_id": crew["people"]["chef"][1]})
    assert status >= 400 and err["code"] == "23514"


def test_team_manager_reads_but_cannot_write_by_default(crew):
    wid = crew["wid"]
    chef_t, _ = crew["people"]["chef"]
    o1_t, o1 = crew["people"]["ouvrier1"]
    autre_t, autre = crew["people"]["autre"]
    _set_option(crew, "admins")
    mine = _entry_body(wid, o1, _day(2, 8))
    assert rest("POST", "time_entries", o1_t, mine)[0] == 201
    theirs = _entry_body(wid, autre, _day(2, 8))
    assert rest("POST", "time_entries", autre_t, theirs)[0] == 201

    _, rows = rest("GET", f"time_entries?id=eq.{mine['id']}&select=id", chef_t)
    assert len(rows) == 1
    _, rows = rest("GET", f"time_entries?id=eq.{theirs['id']}&select=id", chef_t)
    assert rows == []

    status, err = rest("POST", "time_entries", chef_t, _entry_body(wid, o1, _day(2, 10)))
    assert status >= 400 and err["code"] == "42501"


def test_team_manager_enters_time_for_team(crew):
    wid = crew["wid"]
    chef_t, chef = crew["people"]["chef"]
    o1_t, o1 = crew["people"]["ouvrier1"]
    _, autre = crew["people"]["autre"]
    _set_option(crew, "admins_and_team_managers")

    # Saisie pour un collaborateur du périmètre : l'auteur est forcé au chef, quoi qu'envoie le client.
    body = _entry_body(wid, o1, _day(1, 8), created_by=o1)
    status, rows = rest("POST", "time_entries", chef_t, body)
    assert status == 201, rows
    assert rows[0]["created_by"] == chef and rows[0]["updated_by"] == chef

    # Hors périmètre : refusé.
    status, err = rest("POST", "time_entries", chef_t, _entry_body(wid, autre, _day(1, 8)))
    assert status >= 400 and err["code"] == "42501"

    # Upsert façon connecteur PowerSync : l'auteur d'origine est conservé.
    assert upsert("time_entries", chef_t, {**body, "description": "pose échafaudage"})[0] in (200, 201)
    _, rows = rest("GET", f"time_entries?id=eq.{body['id']}&select=created_by,description", chef_t)
    assert rows == [{"created_by": chef, "description": "pose échafaudage"}]

    # Le collaborateur garde la main sur son entrée.
    status, rows = rest("PATCH", f"time_entries?id=eq.{body['id']}", o1_t, {"description": "corrigé"})
    assert status == 200 and rows[0]["created_by"] == chef and rows[0]["updated_by"] == o1

    # Impossible de « déplacer » l'entrée vers quelqu'un hors périmètre.
    status, err = rest("PATCH", f"time_entries?id=eq.{body['id']}", chef_t, {"user_id": autre})
    assert status >= 400 and err["code"] == "42501"


def test_no_timer_for_someone_else(crew):
    wid = crew["wid"]
    chef_t, _ = crew["people"]["chef"]
    owner_t, _ = crew["people"]["owner"]
    _, o2 = crew["people"]["ouvrier2"]
    _set_option(crew, "admins_and_team_managers")
    running = {"workspace_id": wid, "user_id": o2, "start_at": iso(datetime.now(UTC))}
    for token in (chef_t, owner_t):
        status, err = rest("POST", "time_entries", token, running)
        assert status >= 400 and err["code"] == "42501" and "timer_for_others" in err["message"]


def test_workspace_manager_enters_time_for_anyone_when_allowed(crew):
    wid = crew["wid"]
    adj_t, _ = crew["people"]["adjoint"]
    _, autre = crew["people"]["autre"]
    _set_option(crew, "admins")
    status, _ = rest("POST", "time_entries", adj_t, _entry_body(wid, autre, _day(1, 13)))
    assert status >= 400
    _set_option(crew, "admins_and_team_managers")
    assert rest("POST", "time_entries", adj_t, _entry_body(wid, autre, _day(1, 13)))[0] == 201


def test_team_manager_approves_team_timesheets_only(crew):
    wid = crew["wid"]
    chef_t, chef = crew["people"]["chef"]
    o2_t, o2 = crew["people"]["ouvrier2"]
    autre_t, autre = crew["people"]["autre"]
    monday = date.today() - timedelta(days=date.today().weekday() + 21)
    period = {"period_start": monday.isoformat(), "period_end": (monday + timedelta(days=6)).isoformat()}

    sub_o2, sub_autre, sub_chef = (str(uuid.uuid4()) for _ in range(3))
    assert upsert("timesheet_submissions", o2_t, {"id": sub_o2, "workspace_id": wid, "user_id": o2, **period})[0] == 201
    assert upsert("timesheet_submissions", autre_t, {"id": sub_autre, "workspace_id": wid, "user_id": autre, **period})[0] == 201
    assert upsert("timesheet_submissions", chef_t, {"id": sub_chef, "workspace_id": wid, "user_id": chef, **period})[0] == 201

    status, rows = rest("PATCH", f"timesheet_submissions?id=eq.{sub_o2}", chef_t, {"status": "approved"})
    assert status == 200 and rows[0]["decided_by"] == chef
    # Hors périmètre : la ligne n'est même pas visible.
    status, rows = rest("PATCH", f"timesheet_submissions?id=eq.{sub_autre}", chef_t, {"status": "approved"})
    assert status == 200 and rows == []
    # Jamais sa propre feuille.
    status, err = rest("PATCH", f"timesheet_submissions?id=eq.{sub_chef}", chef_t, {"status": "approved"})
    assert status >= 400 and err["code"] == "42501"


def test_time_off_approvers_follow_policy(crew):
    wid = crew["wid"]
    owner_t, _ = crew["people"]["owner"]
    chef_t, chef = crew["people"]["chef"]
    o2_t, o2 = crew["people"]["ouvrier2"]
    pid = str(uuid.uuid4())
    assert rest("POST", "time_off_policies", owner_t, {"id": pid, "workspace_id": wid, "name": "Congés"})[0] == 201
    start = date.today() + timedelta(days=40)
    rid = str(uuid.uuid4())
    assert upsert("time_off_requests", o2_t, {"id": rid, "workspace_id": wid, "user_id": o2, "policy_id": pid,
                                              "start_date": start.isoformat(), "end_date": start.isoformat(),
                                              "amount": 1})[0] == 201
    # Le chef voit la demande de son équipe…
    _, rows = rest("GET", f"time_off_requests?id=eq.{rid}&select=status", chef_t)
    assert rows == [{"status": "pending"}]
    # … mais la politique réserve l'approbation aux managers.
    status, rows = rest("PATCH", f"time_off_requests?id=eq.{rid}", chef_t, {"status": "approved"})
    assert status == 200 and rows == []
    assert rest("PATCH", f"time_off_policies?id=eq.{pid}", owner_t, {"approvers": "managers_and_team_managers"})[0] == 200
    status, rows = rest("PATCH", f"time_off_requests?id=eq.{rid}", chef_t, {"status": "approved"})
    assert status == 200 and rows[0]["status"] == "approved" and rows[0]["decided_by"] == chef


def test_flask_export_is_scoped_to_team(crew):
    wid = crew["wid"]
    chef_t, _ = crew["people"]["chef"]
    _, autre = crew["people"]["autre"]
    frm = (date.today() - timedelta(days=35)).isoformat()
    to = date.today().isoformat()
    url = f"{SERVICES}/api/exports/report?workspace_id={wid}&from={frm}&to={to}&format=csv"
    status, body = _call("GET", url, chef_t)
    assert status == 200, body
    text = body.decode("utf-8-sig")
    assert "ouvrier1" in text and "autre" not in text
    status, _ = _call("GET", f"{url}&user_id={autre}", chef_t)
    assert status == 403


def test_scope_follows_groups_and_membership(crew):
    wid = crew["wid"]
    owner_t, _ = crew["people"]["owner"]
    chef_t, chef = crew["people"]["chef"]
    _, o1 = crew["people"]["ouvrier1"]
    _, o2 = crew["people"]["ouvrier2"]
    _set_option(crew, "admins_and_team_managers")

    # ouvrier1 quitte le groupe : plus dans le périmètre.
    assert rest("DELETE", f"user_group_members?group_id=eq.{crew['gid']}&user_id=eq.{o1}", owner_t)[0] in (200, 204)
    status, err = rest("POST", "time_entries", chef_t, _entry_body(wid, o1, _day(0, 7)))
    assert status >= 400 and err["code"] == "42501"

    # ouvrier2 désactivé : retiré du périmètre ; réactivé : il revient.
    mid = crew["member_ids"]["ouvrier2"]
    assert rest("PATCH", f"workspace_members?id=eq.{mid}", owner_t, {"status": "inactive"})[0] == 200
    _, rows = rest("GET", f"team_scope?manager_id=eq.{chef}&select=user_id", chef_t)
    assert rows == []
    assert rest("PATCH", f"workspace_members?id=eq.{mid}", owner_t, {"status": "active"})[0] == 200
    _, rows = rest("GET", f"team_scope?manager_id=eq.{chef}&select=user_id", chef_t)
    assert rows == [{"user_id": o2}]

    # Groupe supprimé (soft delete) puis affectations retirées : périmètre vide.
    assert rest("PATCH", f"user_groups?id=eq.{crew['gid']}", owner_t, {"deleted_at": iso(datetime.now(UTC))})[0] == 200
    assert rest("DELETE", f"team_manager_assignments?manager_id=eq.{chef}", owner_t)[0] in (200, 204)
    _, rows = rest("GET", f"team_scope?manager_id=eq.{chef}&select=user_id", chef_t)
    assert rows == []


def test_deleting_a_team_manager_account_keeps_the_entries_he_entered():
    """Suppression d'un compte (API admin GoTrue) : l'auteur passe à NULL, les entrées restent."""
    owner_t, owner = signup("patron2")
    chef_t, chef = signup("chef2")
    worker_t, worker = signup("ouvrier3")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{owner}&select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    _add_member(owner_t, wid, chef, "chef2")
    _add_member(owner_t, wid, worker, "ouvrier3")
    assert rest("PATCH", f"workspaces?id=eq.{wid}", owner_t, {"time_for_others": "admins_and_team_managers"})[0] == 200
    assert rest("POST", "team_manager_assignments", owner_t,
                {"workspace_id": wid, "manager_id": chef, "user_id": worker})[0] == 201
    body = _entry_body(wid, worker, _day(1, 9))
    assert rest("POST", "time_entries", chef_t, body)[0] == 201

    service = ENV["SERVICE_ROLE_KEY"]
    status, err = _call("DELETE", f"{SUPABASE}/auth/v1/admin/users/{chef}", service)
    assert status == 200, err
    _, rows = rest("GET", f"time_entries?id=eq.{body['id']}&select=user_id,created_by,updated_by", worker_t)
    assert rows == [{"user_id": worker, "created_by": None, "updated_by": None}]
    _, rows = rest("GET", f"team_scope?workspace_id=eq.{wid}&select=id", owner_t)
    assert rows == []
