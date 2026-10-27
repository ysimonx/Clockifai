"""Agenda iCal (plans/13-ux-moderne.md, lot 4) : adresses acceptées, événements d'une journée."""

from __future__ import annotations

import socket
from datetime import UTC, datetime

import pytest

from app.services import calendar

ICS = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//FR
BEGIN:VTIMEZONE
TZID:Europe/Paris
BEGIN:STANDARD
DTSTART:19701025T030000
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:19700329T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:hebdo@test
SUMMARY:Point hebdo
DTSTART;TZID=Europe/Paris:20261005T100000
DTEND;TZID=Europe/Paris:20261005T110000
RRULE:FREQ=WEEKLY
END:VEVENT
BEGIN:VEVENT
UID:dupuis@test
SUMMARY:Client Dupuis
DTSTART:20261026T140000Z
DURATION:PT1H30M
END:VEVENT
BEGIN:VEVENT
UID:ferie@test
SUMMARY:Journée entière
DTSTART;VALUE=DATE:20261026
DTEND;VALUE=DATE:20261027
END:VEVENT
BEGIN:VEVENT
UID:annule@test
SUMMARY:Annulé
STATUS:CANCELLED
DTSTART:20261026T160000Z
DTEND:20261026T170000Z
END:VEVENT
END:VCALENDAR
""".encode()


def test_only_https_and_webcal():
    assert calendar.normalize_url(" webcal://calendar.example.com/x.ics ") == "https://calendar.example.com/x.ics"
    assert calendar.normalize_url("https://calendar.example.com/x.ics#frag") == "https://calendar.example.com/x.ics"
    for bad in ("http://calendar.example.com/x.ics", "file:///etc/passwd", "", "https://"):
        with pytest.raises(calendar.CalendarError) as err:
            calendar.normalize_url(bad)
        assert err.value.code == "https_required"


def _resolve_to(monkeypatch, ip: str):
    monkeypatch.setattr(socket, "getaddrinfo", lambda *a, **k: [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (ip, 443))])


@pytest.mark.parametrize("ip", ["127.0.0.1", "10.0.0.5", "172.18.0.3", "192.168.0.84", "169.254.169.254", "::1"])
def test_internal_addresses_refused(monkeypatch, ip):
    _resolve_to(monkeypatch, ip)
    with pytest.raises(calendar.CalendarError) as err:
        calendar.check_url("https://calendar.example.com/x.ics")
    assert err.value.code == "host_not_allowed"


def test_public_address_accepted(monkeypatch):
    _resolve_to(monkeypatch, "142.250.75.238")
    calendar.check_url("https://calendar.google.com/x.ics")


def test_redirect_to_internal_address_refused(monkeypatch):
    _resolve_to(monkeypatch, "10.0.0.5")
    with pytest.raises(calendar.CalendarError):
        calendar._SafeRedirects().redirect_request(None, None, 302, "Found", {}, "https://intranet.local/x.ics")


def test_the_connection_goes_to_the_checked_address(monkeypatch):
    calls = []
    monkeypatch.setattr(socket, "getaddrinfo", lambda *a, **k: [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))])

    def refuse(address, *a, **k):
        calls.append(address)
        raise ConnectionRefusedError

    monkeypatch.setattr(socket, "create_connection", refuse)
    with pytest.raises(calendar.CalendarError) as err:
        calendar.fetch("https://calendar.example.com/x.ics")
    assert err.value.code == "unreachable"
    assert calls == [("93.184.216.34", 443)], "l'adresse vérifiée, pas le nom résolu à nouveau"


def test_a_name_that_turns_internal_is_never_reached(monkeypatch):
    answers = iter(["93.184.216.34", "10.0.0.5", "10.0.0.5"])
    monkeypatch.setattr(socket, "getaddrinfo",
                        lambda *a, **k: [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (next(answers), 443))])
    calls = []
    monkeypatch.setattr(socket, "create_connection", lambda address, *a, **k: calls.append(address))
    with pytest.raises(calendar.CalendarError) as err:
        calendar.fetch("https://calendar.example.com/x.ics")
    assert err.value.code == "host_not_allowed" and calls == []


@pytest.mark.parametrize("ip", ["::ffff:10.0.0.5", "::ffff:127.0.0.1"])
def test_mapped_internal_addresses_refused(monkeypatch, ip):
    monkeypatch.setattr(socket, "getaddrinfo", lambda *a, **k: [(socket.AF_INET6, socket.SOCK_STREAM, 6, "", (ip, 443, 0, 0))])
    with pytest.raises(calendar.CalendarError):
        calendar.check_url("https://calendar.example.com/x.ics")


def test_events_of_a_day_heure_et_titre_seulement():
    cal = calendar.parse(ICS)
    events = calendar.events_between(cal, datetime(2026, 10, 26, tzinfo=UTC), datetime(2026, 10, 27, tzinfo=UTC))
    # Lundi 26 octobre, lendemain du passage à l'heure d'hiver : 10:00 à Paris = 09:00 UTC.
    assert [(e.title, e.start.isoformat(), e.end.isoformat()) for e in events] == [
        ("Point hebdo", "2026-10-26T09:00:00+00:00", "2026-10-26T10:00:00+00:00"),
        ("Client Dupuis", "2026-10-26T14:00:00+00:00", "2026-10-26T15:30:00+00:00"),
    ]
    assert len({e.id for e in events}) == 2
    # La semaine d'avant, encore à l'heure d'été : 08:00 UTC.
    before = calendar.events_between(cal, datetime(2026, 10, 19, tzinfo=UTC), datetime(2026, 10, 20, tzinfo=UTC))
    assert [(e.title, e.start.hour) for e in before] == [("Point hebdo", 8)]


def test_not_a_calendar():
    with pytest.raises(calendar.CalendarError) as err:
        calendar.parse(b"<html>Connexion requise</html>")
    assert err.value.code == "not_a_calendar"
