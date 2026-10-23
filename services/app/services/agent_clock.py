"""Chronomètre d'un agent Claude : entrées de temps d'une session, recalculées à partir de ses événements.

Plan : plans/10-suivi-claude-code.md, D7. Fonctions pures, sans base : Flask leur passe les événements de la
session (7 jours au plus) et ses entrées existantes, puis applique les opérations par agent_entry_write.

- Rien ne démarre avant un prompt, sauf un outil (`agent_tool`) qui prouve que Claude travaille.
- Une pause de moins de IDLE_TIMEOUT continue l'entrée : l'attente entre deux tours compte (D7.2).
- Une entrée inactive depuis IDLE_TIMEOUT se ferme à sa dernière activité, pas à l'instant du constat (D7.4).
- Un outil long (duration_ms) prolonge l'entrée s'il a commencé avant le délai (D7.6) ; après une attente
  d'autorisation (`agent_wait`), la reprise ouvre une nouvelle entrée.
- Recalcul complet : un événement en retard ou en double donne le même résultat qu'à l'heure (D7.7).
- Une entrée qu'un humain a supprimée, arrêtée ou dont il a changé la fin est figée : sa plage est retirée du
  calcul, elle n'est jamais recréée ni modifiée (D7.8). Un début changé à la main est gardé ; la fin suit encore.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta

IDLE_TIMEOUT = timedelta(minutes=10)

# Ordre des événements d'un même instant.
_ORDER = {"session_start": 0, "prompt": 1, "agent_tool": 2, "agent_stop": 3, "agent_wait": 4, "session_end": 5}


@dataclass(frozen=True)
class Event:
    kind: str
    at: datetime
    duration_ms: int | None = None  # agent_tool : durée de l'outil
    id: str | None = None


@dataclass(frozen=True)
class Existing:
    """Entrée d'agent existante : valeurs actuelles (time_entries) et valeurs écrites par le serveur."""

    id: str
    start_at: datetime
    end_at: datetime | None
    deleted_at: datetime | None
    server_start_at: datetime
    server_end_at: datetime | None


@dataclass
class Interval:
    start: datetime
    last: datetime                      # dernière activité
    end: datetime | None = None         # None : en cours
    waiting_since: datetime | None = None
    closed_by_idle: bool = False


@dataclass(frozen=True)
class Create:
    interval: Interval


@dataclass(frozen=True)
class Update:
    entry_id: str
    start: datetime | None              # None : début inchangé (corrigé à la main)
    interval: Interval
    times_changed: bool                 # False : seul le suivi change (dernière activité, attente)


@dataclass
class _Span:
    start: datetime
    end: datetime
    entries: list[str] = field(default_factory=list)


def _s(dt: datetime | None) -> datetime | None:
    return dt.replace(microsecond=0) if dt else None


def _end_touched(x: Existing) -> bool:
    return _s(x.end_at) != _s(x.server_end_at)


def _start_touched(x: Existing) -> bool:
    return _s(x.start_at) != _s(x.server_start_at)


def is_frozen(x: Existing) -> bool:
    """Supprimée, ou fin changée par un humain (arrêt, correction, arrêt automatique)."""
    return x.deleted_at is not None or _end_touched(x)


def frozen_spans(existing: list[Existing], now: datetime) -> list[_Span]:
    spans = []
    for x in existing:
        if not is_frozen(x):
            continue
        end = x.end_at or x.deleted_at or now
        if x.deleted_at and x.end_at is None:
            end = x.deleted_at
        spans.append(_Span(min(x.start_at, end), max(x.start_at, end), [x.id]))
    return sorted(spans, key=lambda s: s.start)


def _inside(spans: list[_Span], at: datetime) -> _Span | None:
    return next((s for s in spans if s.start <= at <= s.end), None)


def _not_inside(spans: list[_Span], at: datetime) -> datetime:
    """Un instant ramené à la fin de la plage figée qui le contiendrait."""
    span = _inside(spans, at)
    return span.end if span else at


def compute_intervals(events: list[Event], frozen: list[_Span], now: datetime,
                      idle: timedelta = IDLE_TIMEOUT) -> list[Interval]:
    seen: set = set()
    evs = []
    for e in events:
        key = e.id or (e.kind, e.at, e.duration_ms)
        if key not in seen:
            seen.add(key)
            evs.append(e)
    evs.sort(key=lambda e: (e.at, _ORDER.get(e.kind, 9)))

    out: list[Interval] = []
    cur: Interval | None = None

    def close(at: datetime, by_idle: bool) -> None:
        nonlocal cur
        assert cur is not None
        cur.end, cur.closed_by_idle = at, by_idle
        if cur.end > cur.start:
            out.append(cur)
        cur = None

    for e in evs:
        if e.kind not in _ORDER or e.kind == "session_start":
            continue
        # Une plage figée commence avant cet événement : l'entrée en cours s'arrête là.
        if cur is not None:
            cut = next((s for s in frozen if cur.last < s.start <= e.at), None)
            if cut is not None:
                close(min(cur.last, cut.start), by_idle=False)
        if _inside(frozen, e.at):
            continue  # activité déjà comptée dans une entrée retouchée à la main

        gap = e.at - cur.last if cur is not None else None
        if e.kind == "prompt":
            if cur is not None and gap <= idle:
                cur.last, cur.waiting_since = e.at, None
            else:
                if cur is not None:
                    close(cur.last, by_idle=True)
                cur = Interval(start=e.at, last=e.at)
        elif e.kind in ("agent_tool", "agent_stop"):
            work_start = e.at
            if e.kind == "agent_tool" and e.duration_ms:
                work_start = _not_inside(frozen, e.at - timedelta(milliseconds=e.duration_ms))
                if out:  # jamais avant la fin de l'entrée précédente
                    work_start = max(work_start, out[-1].end)
            if cur is None:
                if e.kind == "agent_tool":  # un « Stop » seul ne prouve pas de travail
                    cur = Interval(start=work_start, last=e.at)
                continue
            if gap <= idle:
                cur.last, cur.waiting_since = e.at, None
            elif cur.waiting_since is None and work_start <= cur.last + idle:
                cur.last = e.at  # outil long : Claude travaillait
            else:
                close(cur.last, by_idle=True)
                if e.kind == "agent_tool":
                    cur = Interval(start=work_start, last=e.at)
        elif e.kind == "agent_wait":
            if cur is not None:
                cur.waiting_since = e.at
        elif e.kind == "session_end" and cur is not None:
            if gap <= idle:
                close(e.at, by_idle=False)
            else:
                close(cur.last, by_idle=True)

    if cur is not None:
        if now - cur.last >= idle:
            close(cur.last, by_idle=True)
        else:
            out.append(cur)
    return out


def _overlap(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> timedelta:
    return max(timedelta(0), min(a_end, b_end) - max(a_start, b_start))


def reconcile(intervals: list[Interval], existing: list[Existing], now: datetime) -> list[Create | Update]:
    """Opérations pour passer des entrées existantes aux intervalles calculés. Une entrée figée n'est jamais
    touchée ; une entrée existante sans intervalle correspondant est laissée telle quelle."""
    live = [x for x in existing if not is_frozen(x)]
    used: set[str] = set()
    ops: list[Create | Update] = []
    for iv in intervals:
        iv_end = iv.end or now
        best, best_overlap = None, timedelta(0)
        for x in live:
            if x.id in used:
                continue
            ov = _overlap(x.start_at, x.end_at or now, iv.start, iv_end)
            if ov > best_overlap or (ov == best_overlap and best is None and _s(x.start_at) == _s(iv.start)):
                best, best_overlap = x, ov
        if best is None:
            ops.append(Create(iv))
            continue
        used.add(best.id)
        keep_start = _start_touched(best)
        same_start = keep_start or _s(iv.start) == _s(best.server_start_at)
        changed = not (same_start and _s(iv.end) == _s(best.server_end_at))
        ops.append(Update(best.id, None if keep_start else iv.start, iv, changed))
    return ops


def plan_session(events: list[Event], existing: list[Existing], now: datetime,
                 idle: timedelta = IDLE_TIMEOUT) -> list[Create | Update]:
    """Entrée principale : opérations à appliquer pour une session."""
    return reconcile(compute_intervals(events, frozen_spans(existing, now), now, idle), existing, now)
