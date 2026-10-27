"""Agenda de chacun (plans/13-ux-moderne.md, lot 4, question 3) : une adresse iCal privée, lue par le serveur.

Seuls l'heure et le titre des événements servent ; les événements d'une journée entière et ceux annulés sont
ignorés. L'adresse est un secret (qui la connaît lit l'agenda) : elle reste dans `clockifai_private`, n'est jamais
renvoyée en entier, et la lecture refuse tout ce qui n'est pas une adresse https publique (SSRF : pas d'adresse
interne, pas de redirection vers une, et la connexion vise l'adresse vérifiée : un DNS qui répondrait une adresse
publique puis une interne n'y change rien).
"""

from __future__ import annotations

import hashlib
import http.client
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


def public_addresses(host: str, port: int = 443) -> list[str]:
    """Adresses de [host], si toutes sont publiques (ni boucle locale, ni réseau privé, ni lien local…) ; sinon
    CalendarError."""
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except OSError:
        infos = []
    addresses = []
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.version == 6 and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if not ip.is_global or ip.is_multicast:
            raise CalendarError("host_not_allowed")
        addresses.append(info[4][0])
    if not addresses:
        raise CalendarError("host_not_allowed")
    return addresses


def check_url(url: str) -> None:
    public_addresses(host_of(url))


class _PinnedHTTPSConnection(http.client.HTTPSConnection):
    """Se connecte à une adresse que [public_addresses] vient de vérifier, sans résoudre le nom une seconde fois.
    Le certificat reste vérifié pour le nom (SNI et en-tête Host inchangés)."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._create_connection = self._connect_pinned  # attribut posé par HTTPConnection.__init__

    @staticmethod
    def _connect_pinned(address, timeout, source_address=None):
        host, port = address
        error: OSError | None = None
        for ip in public_addresses(host, port):
            try:
                return socket.create_connection((ip, port), timeout, source_address)
            except OSError as e:
                error = e
        raise error or OSError("unreachable")


class _PinnedHTTPS(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(_PinnedHTTPSConnection, req, context=self._context)


class _SafeRedirects(urllib.request.HTTPRedirectHandler):
    """Une redirection n'a pas le droit de mener vers une adresse interne ou non https."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = normalize_url(newurl)
        check_url(url)
        return super().redirect_request(req, fp, code, msg, headers, url)


def fetch(url: str) -> bytes:
    url = normalize_url(url)
    check_url(url)
    # Pas de proxy pris dans l'environnement : la connexion va droit à l'adresse vérifiée.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _PinnedHTTPS, _SafeRedirects)
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
