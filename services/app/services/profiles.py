"""Préférences du profil que le serveur applique : le fuseau horaire (profiles.timezone)."""

from __future__ import annotations

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DEFAULT_TZ = ZoneInfo("Europe/Paris")


def zone(name: str | None) -> ZoneInfo:
    """Le fuseau nommé, Europe/Paris s'il manque ou n'existe pas."""
    try:
        return ZoneInfo(name) if name else DEFAULT_TZ
    except (ZoneInfoNotFoundError, ValueError):
        return DEFAULT_TZ


def user_tz(conn, user_id: str) -> ZoneInfo:
    row = conn.execute("select timezone from public.profiles where id = %s", (user_id,)).fetchone()
    return zone(row["timezone"] if row else None)
