"""Assistant « Demander à Clockifai » (plans/13-ux-moderne.md, lot 12) : la boucle d'appels, sans réseau ni base."""

from __future__ import annotations

from datetime import date
from types import SimpleNamespace as NS

from app.services import assistant


class FakeMessages:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append({**kwargs, "messages": list(kwargs["messages"])})  # ce qui a été envoyé, à cet instant
        return self.responses.pop(0)


def fake_client(*responses):
    messages = FakeMessages(responses)
    return NS(beta=NS(messages=messages)), messages


def text(t):
    return NS(type="text", text=t)


def test_tool_then_answer(monkeypatch):
    seen = []

    def run_tool(conn, scope, tz, name, args, proposals):
        seen.append((name, args, tz))
        if name == "propose_update":
            proposals.append({"entry_ids": ["e1"], "billable": False, "summary": "Non facturable"})
        return [{"label": "Chantier", "duration": "12:30"}]

    monkeypatch.setattr(assistant, "run_tool", run_tool)
    client, messages = fake_client(
        NS(stop_reason="tool_use", content=[
            NS(type="thinking", thinking=""),
            NS(type="tool_use", id="t1", name="time_summary",
               input={"date_from": "2026-10-19", "date_to": "2026-10-25", "group_by": "project"}),
            NS(type="tool_use", id="t2", name="propose_update", input={"entry_ids": ["e1"], "summary": "x"}),
        ]),
        NS(stop_reason="end_turn", content=[text("12:30 sur Chantier cette semaine.")]),
    )
    result = assistant.ask(client, None, assistant.Scope("w", ["u"]), question="Combien sur Chantier ?",
                           history=[{"role": "assistant", "text": "Bonjour"}, {"role": "user", "text": "Avant"},
                                    {"role": "assistant", "text": "Réponse"}],
                           tz="Europe/Paris", today=date(2026, 10, 27), model="claude-opus-5-5", effort="low")
    assert result == {"answer": "12:30 sur Chantier cette semaine.", "refused": False,
                      "proposals": [{"entry_ids": ["e1"], "billable": False, "summary": "Non facturable"}]}
    assert [s[0] for s in seen] == ["time_summary", "propose_update"]
    first = messages.calls[0]
    assert first["model"] == "claude-opus-5-5" and first["output_config"] == {"effort": "low"}
    assert first["fallbacks"] == "default" and first["betas"] == ["server-side-fallback-2026-07-01"]
    sent = first["messages"]
    assert sent[0] == {"role": "user", "content": "Avant"}, "l'historique commence par la personne"
    assert sent[-1]["content"].startswith("(Aujourd'hui : mardi 2026-10-27)")
    # Second appel : la réponse de Claude (réflexion comprise) puis les deux résultats, dans un seul message.
    second = messages.calls[1]["messages"]
    assert second[-2]["role"] == "assistant" and second[-2]["content"][0].type == "thinking"
    assert [r["tool_use_id"] for r in second[-1]["content"]] == ["t1", "t2"]


def test_tool_error_goes_back_to_claude(monkeypatch):
    def run_tool(*_):
        raise ValueError("période invalide (400 jours au plus)")

    monkeypatch.setattr(assistant, "run_tool", run_tool)
    client, messages = fake_client(
        NS(stop_reason="tool_use", content=[NS(type="tool_use", id="t1", name="time_summary", input={})]),
        NS(stop_reason="end_turn", content=[text("Période trop longue.")]),
    )
    result = assistant.ask(client, None, assistant.Scope("w", None), question="Sur 5 ans ?", history=[],
                           tz="Europe/Paris", today=date(2026, 10, 27), model="m", effort="low")
    assert result["answer"] == "Période trop longue."
    error = messages.calls[1]["messages"][-1]["content"][0]
    assert error["is_error"] is True and "400 jours" in error["content"]


def test_refusal():
    client, _ = fake_client(NS(stop_reason="refusal", content=[]))
    result = assistant.ask(client, None, assistant.Scope("w", None), question="…", history=[],
                           tz="Europe/Paris", today=date(2026, 10, 27), model="m", effort="low")
    assert result == {"answer": None, "refused": True, "proposals": []}


def test_rate_limit_per_person():
    assistant._recent.clear()
    assert all(assistant.allow("u") for _ in range(assistant.MAX_QUESTIONS_PER_HOUR))
    assert assistant.allow("u") is False
    assert assistant.allow("autre") is True


def test_tools_never_ask_for_descriptions():
    names = {t["name"] for t in assistant._tools()}
    assert names == {"list_catalog", "time_summary", "find_entries", "propose_update"}
    assert "description" not in str(assistant.find_entries.__code__.co_consts)
