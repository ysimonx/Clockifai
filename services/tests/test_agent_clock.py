"""Chronomètre d'agent (plan 10, D7) : intervalles d'une session et rapprochement avec les entrées existantes."""

import random
from datetime import UTC, datetime, timedelta

from app.services.agent_clock import (
    IDLE_TIMEOUT,
    Create,
    Event,
    Existing,
    Update,
    compute_intervals,
    frozen_spans,
    plan_session,
)

T0 = datetime(2026, 10, 23, 14, 0, tzinfo=UTC)


def m(minutes: float) -> datetime:
    return T0 + timedelta(minutes=minutes)


def ev(kind: str, minute: float, duration_min: float | None = None, id: str | None = None) -> Event:
    return Event(kind, m(minute), int(duration_min * 60_000) if duration_min else None, id)


def spans(intervals):
    return [(iv.start, iv.end) for iv in intervals]


def intervals(events, now, existing=()):
    return compute_intervals(events, frozen_spans(list(existing), now), now)


def test_session_start_alone_starts_nothing():
    assert intervals([ev("session_start", 0)], now=m(30)) == []


def test_prompt_starts_and_entry_runs_while_active():
    out = intervals([ev("session_start", 0), ev("prompt", 0), ev("agent_tool", 2), ev("agent_stop", 6)], now=m(8))
    assert spans(out) == [(m(0), None)]
    assert out[0].last == m(6)


def test_idle_entry_closes_at_last_activity():
    out = intervals([ev("prompt", 0), ev("agent_tool", 2), ev("agent_stop", 6)], now=m(30))
    assert spans(out) == [(m(0), m(6))]
    assert out[0].closed_by_idle


def test_short_pause_between_turns_counts():
    out = intervals([ev("prompt", 0), ev("agent_stop", 5), ev("prompt", 12), ev("agent_stop", 15)], now=m(40))
    assert spans(out) == [(m(0), m(15))]


def test_long_pause_opens_a_new_entry():
    out = intervals([ev("prompt", 0), ev("agent_stop", 5), ev("prompt", 20), ev("agent_stop", 22)], now=m(40))
    assert spans(out) == [(m(0), m(5)), (m(20), m(22))]


def test_session_end_closes_now_or_at_last_activity():
    out = intervals([ev("prompt", 0), ev("agent_stop", 5), ev("session_end", 7)], now=m(8))
    assert spans(out) == [(m(0), m(7))]
    out = intervals([ev("prompt", 0), ev("agent_stop", 5), ev("session_end", 600)], now=m(601))
    assert spans(out) == [(m(0), m(5))]


def test_long_command_extends_the_entry():
    # Une commande de 29 minutes, lancée à la minute 1 : Claude travaillait.
    out = intervals([ev("prompt", 0), ev("agent_tool", 30, duration_min=29), ev("agent_stop", 31)], now=m(60))
    assert spans(out) == [(m(0), m(31))]


def test_permission_wait_counts_only_under_the_timeout():
    short = intervals([ev("prompt", 0), ev("agent_tool", 1), ev("agent_wait", 2), ev("agent_tool", 5, 0.5),
                       ev("agent_stop", 6)], now=m(30))
    assert spans(short) == [(m(0), m(6))]
    long = intervals([ev("prompt", 0), ev("agent_tool", 1), ev("agent_wait", 2), ev("agent_tool", 40, 1),
                      ev("agent_stop", 41)], now=m(60))
    assert spans(long) == [(m(0), m(1)), (m(39), m(41))]


def test_a_stop_alone_proves_nothing_but_a_tool_does():
    assert intervals([ev("session_start", 0), ev("agent_stop", 1), ev("session_end", 2)], now=m(30)) == []
    out = intervals([ev("agent_tool", 10, duration_min=3)], now=m(12))
    assert spans(out) == [(m(7), None)]


def test_late_and_duplicate_events_give_the_same_result():
    events = [ev("prompt", 0, id="a"), ev("agent_tool", 3, id="b"), ev("agent_stop", 5, id="c"),
              ev("prompt", 8, id="d"), ev("agent_stop", 9, id="e"), ev("prompt", 30, id="f"), ev("agent_stop", 33, id="g")]
    expected = spans(intervals(events, now=m(60)))
    shuffled = events + [events[1], events[4]]
    random.Random(4).shuffle(shuffled)
    assert spans(intervals(shuffled, now=m(60))) == expected == [(m(0), m(9)), (m(30), m(33))]


def test_new_entry_then_updates_as_the_session_goes_on():
    events = [ev("prompt", 0), ev("agent_tool", 2)]
    ops = plan_session(events, [], now=m(3))
    assert len(ops) == 1 and isinstance(ops[0], Create) and ops[0].interval.end is None

    running = Existing("e1", m(0), None, None, m(0), None)
    ops = plan_session(events + [ev("agent_stop", 4)], [running], now=m(5))
    assert len(ops) == 1 and isinstance(ops[0], Update) and not ops[0].times_changed
    assert ops[0].interval.last == m(4)

    ops = plan_session(events + [ev("agent_stop", 4)], [running], now=m(20))
    assert isinstance(ops[0], Update) and ops[0].times_changed and ops[0].interval.end == m(4)


def test_a_late_earlier_event_moves_the_start():
    existing = Existing("e1", m(5), m(9), None, m(5), m(9))
    ops = plan_session([ev("prompt", 2), ev("prompt", 5), ev("agent_stop", 9)], [existing], now=m(30))
    assert ops == [Update("e1", m(2), ops[0].interval, True)]


def test_entry_stopped_by_hand_is_frozen_and_work_after_it_opens_a_new_entry():
    # Le serveur avait l'entrée en cours depuis 14:00 ; le pilote l'a arrêtée à 14:30.
    stopped = Existing("e1", m(0), m(30), None, m(0), None)
    events = [ev("prompt", 0), ev("agent_tool", 20), ev("agent_tool", 29), ev("agent_tool", 35, 2), ev("agent_stop", 38)]
    ops = plan_session(events, [stopped], now=m(39))
    assert len(ops) == 1 and isinstance(ops[0], Create)
    assert (ops[0].interval.start, ops[0].interval.end) == (m(33), None)


def test_deleted_entry_is_never_recreated():
    deleted = Existing("e1", m(0), None, m(12), m(0), None)  # supprimée pendant qu'elle tournait
    events = [ev("prompt", 0), ev("agent_tool", 5), ev("agent_tool", 10)]
    assert plan_session(events, [deleted], now=m(13)) == []
    later = plan_session(events + [ev("prompt", 15)], [deleted], now=m(16))
    assert [(o.interval.start, o.interval.end) for o in later] == [(m(15), None)]


def test_start_corrected_by_hand_is_kept_but_the_end_still_follows():
    corrected = Existing("e1", m(-10), None, None, m(0), None)  # début avancé à la main
    ops = plan_session([ev("prompt", 0), ev("agent_stop", 6)], [corrected], now=m(30))
    assert len(ops) == 1 and ops[0].start is None and ops[0].interval.end == m(6) and ops[0].times_changed


def test_idle_timeout_default():
    assert IDLE_TIMEOUT == timedelta(minutes=10)


# ---------------------------------------------------------------- sujets nommés par Claude (D18)
def named(minute: float, subject: str) -> Event:
    return Event("session_task", m(minute), subject=subject)


def subjects(out):
    return [(iv.start, iv.end, iv.subject) for iv in out]


def test_a_name_given_at_the_start_covers_the_whole_entry():
    out = intervals([ev("prompt", 0), named(0.2, "Export PDF"), ev("agent_tool", 1), ev("agent_stop", 5)], now=m(30))
    assert subjects(out) == [(m(0), m(5), "Export PDF")]


def test_a_new_subject_starts_at_the_prompt_that_brought_it():
    out = intervals([ev("prompt", 0), named(0.1, "Export PDF"), ev("agent_stop", 5),
                     ev("prompt", 8), named(8.2, "Connexion mobile"), ev("agent_stop", 12)], now=m(40))
    assert subjects(out) == [(m(0), m(8), "Export PDF"), (m(8), m(12), "Connexion mobile")]


def test_the_same_name_in_another_case_changes_nothing():
    out = intervals([ev("prompt", 0), named(0.1, "Export PDF"), ev("prompt", 8), named(8.1, "export pdf"),
                     ev("agent_stop", 12)], now=m(40))
    assert subjects(out) == [(m(0), m(12), "Export PDF")]


def test_a_subject_named_mid_turn_starts_when_claude_names_it():
    # Pas de prompt récent : Claude change de sujet en cours de travail.
    out = intervals([ev("prompt", 0), named(0.1, "A"), ev("agent_tool", 3), named(6, "B"), ev("agent_stop", 9)],
                    now=m(40))
    assert subjects(out) == [(m(0), m(6), "A"), (m(6), m(9), "B")]


def test_a_first_name_given_late_keeps_the_earlier_minutes_unnamed():
    # Les 8 premières minutes gardent la tâche reprise de l'entrée précédente (ou aucune) : seule la suite est nommée.
    out = intervals([ev("prompt", 0), ev("agent_tool", 5), named(8, "Export PDF"), ev("agent_stop", 10)], now=m(40))
    assert subjects(out) == [(m(0), m(8), None), (m(8), m(10), "Export PDF")]


def test_a_name_given_outside_any_entry_goes_to_the_next_one():
    out = intervals([ev("prompt", 0), ev("agent_stop", 2), named(20, "Export PDF"), ev("prompt", 20.5),
                     ev("agent_stop", 25)], now=m(60))
    assert subjects(out) == [(m(0), m(2), None), (m(20.5), m(25), "Export PDF")]


def test_a_new_entry_after_a_pause_is_not_named_by_the_clock():
    # La continuité d'une entrée à l'autre passe par la tâche de l'entrée précédente (Flask), pas par l'horloge.
    out = intervals([ev("prompt", 0), named(0.1, "A"), ev("agent_stop", 2), ev("prompt", 20), ev("agent_stop", 22)],
                    now=m(60))
    assert subjects(out) == [(m(0), m(2), "A"), (m(20), m(22), None)]
