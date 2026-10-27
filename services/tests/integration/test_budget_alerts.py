"""Alertes de budget (plans/18-rapports-presence-alertes-partage.md, lot 2) contre la pile Docker : seuils de 80 et
100 %, une seule fois chacun, réarmés par un budget relevé ; budget en montant ; estimation d'une tâche avec ses
sous-tâches ; emails aux managers seulement."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from psycopg.rows import dict_row

from app.services import budget_alerts

from .test_backend import ENV, iso, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

DSN = (f"postgresql://postgres.{ENV.get('POOLER_TENANT_ID', '')}:{ENV.get('POSTGRES_PASSWORD', '')}"
       f"@localhost:{ENV.get('POSTGRES_PORT', '5432')}/postgres")


@pytest.fixture(scope="module")
def site():
    owner_t, owner = signup("conducteur")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{owner}&select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    member_t, member = signup("compagnon")
    assert rest("POST", "workspace_members", owner_t,
                {"workspace_id": wid, "user_id": member, "role": "member", "display_name": "Compagnon"})[0] == 201
    project = str(uuid.uuid4())
    assert rest("POST", "projects", owner_t, {"id": project, "workspace_id": wid, "name": "Unité 4", "budget_hours": 10,
                                              "budget_amount_cents": 100_000, "hourly_rate_cents": 10_000})[0] == 201
    task, sub = str(uuid.uuid4()), str(uuid.uuid4())
    assert rest("POST", "tasks", owner_t, {"id": task, "workspace_id": wid, "project_id": project, "name": "Montage",
                                           "estimate_seconds": 4 * 3600})[0] == 201
    assert rest("POST", "tasks", owner_t, {"id": sub, "workspace_id": wid, "project_id": project, "name": "Niveau 3",
                                           "parent_id": task})[0] == 201
    clock = [datetime.now(UTC).replace(microsecond=0) - timedelta(days=20)]

    def work(hours: float, task_id: str | None = None, billable: bool = True) -> None:
        start = clock[0]
        clock[0] = start + timedelta(hours=hours)
        assert rest("POST", "time_entries", member_t, {
            "id": str(uuid.uuid4()), "workspace_id": wid, "user_id": member, "project_id": project, "task_id": task_id,
            "start_at": iso(start), "end_at": iso(clock[0]), "billable": billable})[0] == 201

    return {"wid": wid, "owner_t": owner_t, "owner": owner, "project": project, "task": task, "sub": sub, "work": work}


def _mine(conn, wid: str) -> list[tuple[str, str, int]]:
    return sorted((a.metric, a.name, a.threshold) for a in budget_alerts.new_alerts(conn) if a.workspace_id == wid)


def test_thresholds_once_each_and_rearmed_by_a_bigger_budget(site):
    work = site["work"]
    with psycopg.connect(DSN, row_factory=dict_row) as conn:
        work(2, site["task"])
        work(1.5, site["sub"])
        work(4.5, billable=False)
        # 8 h sur 10 h ; 350 € sur 1 000 € ; Montage : 3 h 30 sur 4 h (sous-tâche comprise).
        assert _mine(conn, site["wid"]) == [("estimate", "Montage", 80), ("hours", "Unité 4", 80)]
        assert _mine(conn, site["wid"]) == [], "une seule fois"

        work(3)  # 11 h ; 650 €
        assert _mine(conn, site["wid"]) == [("hours", "Unité 4", 100)]
        work(3)  # 14 h ; 950 €
        assert _mine(conn, site["wid"]) == [("amount", "Unité 4", 80)]

        assert rest("PATCH", f"projects?id=eq.{site['project']}", site["owner_t"], {"budget_hours": 16})[0] == 200
        assert _mine(conn, site["wid"]) == [("hours", "Unité 4", 80)], "budget relevé : l'alerte se réarme"

        # Une tâche finie ne déclenche plus rien.
        assert rest("PATCH", f"tasks?id=eq.{site['task']}", site["owner_t"], {"status": "done"})[0] == 200
        work(1, site["task"])
        assert _mine(conn, site["wid"]) == [("amount", "Unité 4", 100)]


def test_emails_go_to_the_managers_only(site):
    alert = budget_alerts.Alert(workspace_id=site["wid"], target_id=site["project"], metric="hours", name="Unité 4",
                                project_name=None, used=9 * 3600, budget=10 * 3600, threshold=80)
    with psycopg.connect(DSN, row_factory=dict_row) as conn:
        owner_email = conn.execute("select email from auth.users where id = %s", (site["owner"],)).fetchone()["email"]
        mails = budget_alerts.messages(conn, [alert], "https://clockifai.example.fr")
    assert [m[0] for m in mails] == [owner_email]
    assert mails[0][1] == "Clockifai · Unité 4 : 90 % du budget en heures (9 h sur 10 h)"
