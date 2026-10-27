"""Tickets des clients (plans/19-tickets-clients.md) : clé (« ENG-123 ») et URL d'un ticket Jira, Linear ou GitHub,
analysées comme dans l'app (app/lib/core/tickets.dart, mêmes cas de test). Les sessions de Claude Code les donnent par
`set_current_task` (`session_task` `{ticket, ticket_title}`) ou par le nom de la branche.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import parse_qs, urlsplit

URL_MAX = 500    # colonne tasks.ticket_url
TITLE_MAX = 80   # comme un nom de tâche donné par Claude

_KEY = re.compile(r"^[A-Za-z][A-Za-z0-9_]*-\d+$")
# Dans un nom de branche : « yannick/eng-123-formulaire », « feature/ENG-123 ».
_BRANCH_KEY = re.compile(r"(?<![A-Za-z0-9])([A-Za-z][A-Za-z0-9]+-\d+)(?!\d)")


@dataclass(frozen=True)
class Ticket:
    key: str | None
    url: str | None

    @property
    def label(self) -> str:
        """Ce qu'on montre : la clé, sinon l'URL."""
        return self.key or self.url or ""


def parse_ticket(text) -> Ticket | None:
    """Une URL http(s) (Jira `…/browse/ENG-123` ou `?selectedIssue=ENG-123`, Linear `…/issue/ENG-123/…`, GitHub
    `…/<org>/<dépôt>/issues/45` → `dépôt#45`, autre URL sans clé) ou une clé seule ; None sinon."""
    if not isinstance(text, str):
        return None
    text = text.strip()
    if not text or len(text) > URL_MAX:
        return None
    if _KEY.match(text):
        return Ticket(text.upper(), None)
    try:
        parts = urlsplit(text)
    except ValueError:
        return None
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return None
    return Ticket(_key_of(parts), text)


def _key_of(parts) -> str | None:
    segs = [s for s in parts.path.split("/") if s]
    selected = (parse_qs(parts.query).get("selectedIssue") or [None])[0]
    if selected and _KEY.match(selected):
        return selected.upper()
    if parts.hostname == "github.com":
        ok = len(segs) >= 4 and segs[2] in ("issues", "pull") and segs[3].isdigit()
        return f"{segs[1]}#{segs[3]}" if ok else None
    for marker in ("issue", "browse"):
        if marker in segs:
            i = segs.index(marker)
            if i + 1 < len(segs) and _KEY.match(segs[i + 1]):
                return segs[i + 1].upper()
    return None


def branch_key(branch: str | None) -> str | None:
    """Première clé de ticket du nom de la branche, en majuscules. À ne croire que si elle désigne un ticket connu ou
    que le projet est facturé par ticket : « plan-10-lot-1 » donnerait PLAN-10."""
    m = _BRANCH_KEY.search(branch or "")
    return m.group(1).upper() if m else None


def ticket_title(text) -> str | None:
    title = " ".join(str(text or "").split())[:TITLE_MAX]
    return title or None


def ticket_task_name(ticket: Ticket, title: str | None) -> str:
    """« ENG-123 · Titre », la clé seule, ou le titre (comme ticketTaskName dans l'app)."""
    t = (title or "").strip()
    if ticket.key is None:
        return t or ticket.url or ""
    return f"{ticket.key} · {t}" if t else ticket.key
