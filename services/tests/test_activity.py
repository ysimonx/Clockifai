"""Événements d'activité et métadonnées des entrées d'agent (plan 10, D6, D9, D10, D17) : fonctions sans base."""

import re
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from app.auth import hash_token, new_api_token
from app.services.activity import (
    EntrySpan,
    Price,
    Rule,
    aggregate_usage,
    auto_description,
    cost_micros,
    match_rule,
    parse_event,
    price_for,
    repo_name,
    usage_entry,
    usage_of,
)

NOW = datetime(2026, 10, 23, 14, 0, tzinfo=UTC)


def raw(**extra):
    return {"id": str(uuid.uuid4()), "kind": "prompt", "occurred_at": "2026-10-23T13:59:00Z", "session_id": "s1",
            **extra}


def test_api_token_format_and_hash():
    token = new_api_token()
    assert re.fullmatch(r"clk_[0-9a-f]{32}", token)
    assert hash_token(token) == hash_token(token) != hash_token(new_api_token())


def test_valid_agent_event():
    row, reason = parse_event(raw(remote_key="github.com/ysimonx/clockifai", git_branch="main"), NOW)
    assert reason is None
    assert row["actor"] == "agent" and row["occurred_at"] == NOW - timedelta(minutes=1)
    assert row["remote_key"] == "github.com/ysimonx/clockifai" and row["payload"] is None


def test_rejected_events():
    cases = {
        "id must be a UUID": raw(id="pas-un-uuid"),
        "unknown kind 'clic'": raw(kind="clic"),
        "occurred_at must be an ISO 8601 date with a time zone": raw(occurred_at="2026-10-23T13:59:00"),
        "occurred_at out of range": raw(occurred_at=(NOW - timedelta(days=8)).isoformat()),
        "session_id is required": raw(session_id=None),
    }
    for reason, event in cases.items():
        assert parse_event(event, NOW) == (None, reason)
    assert parse_event(raw(occurred_at=(NOW + timedelta(minutes=10)).isoformat()), NOW)[1] == "occurred_at out of range"
    assert parse_event("pas un objet", NOW) == (None, "not an object")


def test_tool_duration_goes_to_payload_and_texts_are_cut():
    row, _ = parse_event(raw(kind="agent_tool", duration_ms=12_000, subject="x" * 500), NOW)
    assert row["payload"] == '{"duration_ms": 12000}'
    assert len(row["subject"]) == 200
    assert parse_event(raw(payload={"description": "y" * 3000}), NOW) == (None, "payload too large")


def test_commit_actor_depends_on_its_origin():
    assert parse_event(raw(kind="commit", sha="abc"), NOW)[0]["actor"] == "agent"
    assert parse_event(raw(kind="commit", sha="abc", session_id=None, window_id="w1"), NOW)[0]["actor"] == "human"
    assert parse_event(raw(kind="focus_start", session_id=None, window_id="w1"), NOW)[0]["actor"] == "human"


def test_repo_name():
    assert repo_name("github.com/ysimonx/clockifai") == "clockifai"
    assert repo_name("local:essai") == "essai"
    assert repo_name(None) is None


def test_auto_description():
    assert auto_description(["Ajout export", "Ajout export", "Correctif"], "github.com/a/b", "main") == \
        "Ajout export; Correctif"
    assert auto_description([], "github.com/ysimonx/clockifai", "plan-10") == "clockifai (plan-10)"
    assert auto_description([], None, None) == ""


def test_path_rule_wins_over_repo_rule_and_the_longest_path_wins():
    rules = [Rule("repo", "github.com/ysimonx/clockifai", "p-repo", None),
             Rule("path_prefix", "/Users/y/dev", "p-dev", None),
             Rule("path_prefix", "/Users/y/dev/clockifai-wt2/", "p-wt2", "t2")]
    assert match_rule(rules, "github.com/ysimonx/clockifai", "/Users/y/dev/clockifai-wt2/app").project_id == "p-wt2"
    assert match_rule(rules, "github.com/ysimonx/clockifai", "/Users/y/dev/clockifai").project_id == "p-dev"
    assert match_rule(rules, "github.com/ysimonx/clockifai", "/Users/y/devx").project_id == "p-repo"
    assert match_rule(rules, "github.com/autre/depot", "/tmp") is None


# ---------------------------------------------------------------- usage IA (D17)
USAGE = {"model": "claude-opus-5-5", "effort": "xhigh", "speed": "standard", "requests": 3, "input_tokens": 10,
         "output_tokens": 2_000, "cache_write_5m_tokens": 1_000, "cache_write_1h_tokens": 20_000,
         "cache_read_tokens": 300_000}
OPUS = Price(Decimal(4), Decimal(20), Decimal(5), Decimal(8), Decimal("0.20"), Decimal(2))


def test_usage_event_is_checked_on_arrival():
    row, reason = parse_event(raw(kind="agent_usage", payload=USAGE), NOW)
    assert reason is None and row["actor"] == "agent"
    assert usage_of(dict(USAGE, effort=None, speed=None))["speed"] == "standard"
    for bad in ({"model": ""}, {"input_tokens": -1}, {"output_tokens": "12"}, {"requests": True},
                {"cache_read_tokens": 10**13}):
        assert parse_event(raw(kind="agent_usage", payload=dict(USAGE, **bad)), NOW)[1].startswith("agent_usage payload")
    assert parse_event(raw(kind="agent_usage", session_id=None, payload=USAGE), NOW) == (None, "session_id is required")


def test_price_of_a_dated_model_and_unknown_model():
    prices = {"claude-haiku-4-5": OPUS, "claude-opus-5": OPUS}
    assert price_for("claude-haiku-4-5-20251001", prices) is OPUS
    assert price_for("claude-opus-5-5", prices) is None, "un préfixe ne suffit pas : Opus 5.5 n'est pas Opus 5"
    assert cost_micros(USAGE, None) is None


def test_cost_in_millionths_of_a_dollar():
    # 10×4 + 2000×20 + 1000×5 + 20000×8 + 300000×0,20 = 265 040 millionièmes de dollar (0,27 $)
    assert cost_micros(USAGE, OPUS) == 265_040
    assert cost_micros(dict(USAGE, speed="fast"), OPUS) == 530_080, "mode rapide : tout le tarif doublé"
    assert cost_micros(dict(USAGE, speed="fast"), Price(*[Decimal(1)] * 5)) == 323_010, "sans mode rapide connu"


def test_usage_goes_to_the_entry_that_covers_its_time():
    at = lambda h, m=0: datetime(2026, 10, 23, h, m, tzinfo=UTC)
    entries = [EntrySpan("a", at(9), at(10)), EntrySpan("b", at(11), at(12)), EntrySpan("c", at(13), None)]
    assert usage_entry(entries, at(9, 30), NOW) == "a"
    assert usage_entry(entries, at(10, 30), NOW) == "a", "après une fin corrigée à la main : l'entrée d'avant"
    assert usage_entry(entries, at(13, 59), NOW) == "c", "entrée en cours"
    assert usage_entry(entries, at(8), NOW) == "a", "avant la première : la première"
    assert usage_entry([], at(9), NOW) is None

    totals = aggregate_usage([(at(9, 10), usage_of(USAGE)), (at(9, 50), usage_of(USAGE)),
                              (at(11, 5), usage_of(dict(USAGE, effort="high")))], entries, NOW)
    assert set(totals) == {("a", "claude-opus-5-5", "xhigh", "standard"), ("b", "claude-opus-5-5", "high", "standard")}
    assert totals["a", "claude-opus-5-5", "xhigh", "standard"]["cache_read_tokens"] == 600_000
    assert totals["a", "claude-opus-5-5", "xhigh", "standard"]["requests"] == 6
