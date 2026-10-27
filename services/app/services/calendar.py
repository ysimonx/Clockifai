"""Agenda de chacun (plans/13-ux-moderne.md, lot 4, question 3) : une adresse iCal privée, lue par le serveur.

Seuls l'heure et le titre des événements servent ; les événements d'une journée entière et ceux annulés sont
ignorés. L'adresse est un secret (qui la connaît lit l'agenda) : elle reste dans `clockifai_private`, n'est jamais
renvoyée en entier, et la lecture refuse tout ce qui n'est pas une adresse https publique (SSRF : pas d'adresse
interne, pas de redirection vers une).
"""

from __future__ import annotations

import hashlib
import ipaddress
import socket
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from urllib.parse import urlsplit, urlunsplit

import icalendar
import recurring_ical_events

MAX_BYTES = 5 * 1024 * 1024
TIMEOUT = 10
CACHE_SECONDS = 300


class CalendarError(Exception):
    """Adresse refusée ou agenda illisible ; `code` va tel quel dans la réponse de l'API."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Event:
    id: str
    start: datetime
    end: datetime
    title: str

    def as_json(self) -> dict:
        return {"id": self.id, "start": self.start.isoformat(), "end": self.end.isoformat(), "title": self.title}


def normalize_url(url: str) -> str:
    """`webcal://` devient `https://` ; seules les adresses https sont acceptées."""
    url = (url or "").strip()
    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme == "webcal":
        scheme = "https"
    if scheme != "https" or not parts.hostname:
        raise CalendarError("https_required")
    return urlunsplit((scheme, parts.netloc, parts.path, parts.query, ""))


def host_of(url: str) -> str:
    return urlsplit(url).hostname or ""


def _public(host: str) -> bool:
    """Toutes les adresses de [host] sont publiques (ni boucle locale, ni réseau privé, ni lien local…)."""
    try:
        infos = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
    except OSError:
        return False
    if not infos:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_global or ip.is_multicast:
            return False
    return True


def check_url(url: str) -> None:
    if not _public(host_of(url)):
        raise CalendarError("host_not_allowed")


class _SafeRedirects(urllib.request.HTTPRedirectHandler):
    """Une redirection n'a pas le droit de mener vers une adresse interne ou non https."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = normalize_url(newurl)
        check_url(url)
        return super().redirect_request(req, fp, code, msg, headers, url)


def fetch(url: str) -> bytes:
    url = normalize_url(url)
    check_url(url)
    opener = urllib.request.build_opener(_SafeRedirects)
    request = urllib.request.Request(url, headers={"User-Agent": "Clockifai/1 (agenda)", "Accept": "text/calendar"})
    try:
        with opener.open(request, timeout=TIMEOUT) as response:
            data = response.read(MAX_BYTES + 1)
    except CalendarError:
        raise
    except (urllib.error.URLError, TimeoutError, OSError):
        raise CalendarError("unreachable") from None
    if len(data) > MAX_BYTES:
        raise CalendarError("too_large")
    return data


def parse(data: bytes) -> icalendar.Calendar:
    try:
        cal = icalendar.Calendar.from_ical(data)
    except ValueError:
        raise CalendarError("not_a_calendar") from None
    if not isinstance(cal, icalendar.Calendar) or cal.name != "VCALENDAR":
        raise CalendarError("not_a_calendar")
    return cal


def _utc(value) -> datetime | None:
    if not isinstance(value, datetime):
        return None  # journée entière
    return (value if value.tzinfo else value.replace(tzinfo=UTC)).astimezone(UTC)


def events_between(cal: icalendar.Calendar, start: datetime, end: datetime) -> list[Event]:
    """Événements (récurrences dépliées) qui chevauchent [start, end), du plus tôt au plus tard."""
    out = []
    for component in recurring_ical_events.of(cal).between(start, end):
        if str(component.get("STATUS", "")).upper() == "CANCELLED":
            continue
        s = _utc(component.decoded("DTSTART"))
        e = _utc(component.decoded("DTEND")) if component.get("DTEND") else None
        if s is None:
            continue
        if e is None and component.get("DURATION"):
            e = s + component.decoded("DURATION")
        if e is None or e <= s:
            continue
        title = str(component.get("SUMMARY", "")).strip()[:200]
        uid = str(component.get("UID", ""))
        key = hashlib.sha1(f"{uid}|{s.isoformat()}".encode()).hexdigest()[:16]
        out.append(Event(key, s, e, title))
    return sorted(out, key=lambda ev: (ev.start, ev.end))


# Agenda lu récemment, par personne : la page « Aujourd'hui » le redemande à chaque jour affiché.
_cache: dict[str, tuple[str, float, icalendar.Calendar]] = {}


def calendar_for(user_id: str, url: str) -> icalendar.Calendar:
    hit = _cache.get(user_id)
    if hit and hit[0] == url and time.monotonic() - hit[1] < CACHE_SECONDS:
        return hit[2]
    cal = parse(fetch(url))
    _cache[user_id] = (url, time.monotonic(), cal)
    return cal


def forget(user_id: str) -> None:
    _cache.pop(user_id, None)
