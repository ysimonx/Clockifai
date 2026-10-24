#!/usr/bin/env python3
"""Hook Claude Code → Clockifai (plans/10-suivi-claude-code.md, §6.1, D6, D7, D13).

Lit l'événement du hook sur stdin et n'en garde que la liste blanche (D6) : session, dépôt, branche, dossier,
durée de l'outil. Jamais le prompt, les entrées ou sorties des outils, ni la transcription, sauf le nom de tâche
que Claude passe à l'outil `set_current_task` du plugin (D18). La commande d'un outil Bash est lue sur le poste pour
y repérer un `git commit` (D13), jamais envoyée.

N'écrit jamais sur stdout (Claude Code l'ajouterait au contexte) et sort toujours avec le code 0.
Réglages : CLAUDE_PLUGIN_OPTION_URL et CLAUDE_PLUGIN_OPTION_TOKEN (userConfig du plugin). Sans adresse réglée,
celle que l'instance a posée par défaut dans plugin.json : Claude Code ne transmet pas une valeur par défaut.
Python 3.9 et bibliothèque standard seulement : c'est le python3 livré avec macOS.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

try:
    import fcntl
except ImportError:  # Windows : pas de verrou, au mieux
    fcntl = None

HTTP_TIMEOUT = 2                 # secondes par requête : un hook asynchrone n'a pas de délai imposé
TOOL_EVERY = 60                  # un agent_tool par minute et par session (D7.3)
LONG_TOOL_MS = 60_000            # un outil long part toujours : il peut prolonger l'entrée (D7.6)
UNCLAIMED_AFTER = 600            # commits que nulle session ne revendique : envoyés sans session (D13)
CLAIM_SLACK = 5                  # secondes : horloge du commit arrondie, début de commande estimé
COMMITS_MAX = 20
SPOOL_MAX = 5000                 # lignes
SPOOL_MAX_AGE = 6.5 * 86400      # le serveur refuse au-delà de 7 jours
BATCH = 200
COMMIT_NS = uuid.NAMESPACE_URL   # id d'un commit : uuid5(NAMESPACE_URL, "clockifai:commit:<remote_key>:<sha>")

# Outil du serveur MCP du plugin (clockifai_mcp.py) : Claude y nomme la tâche du sujet en cours (D18).
# Claude Code le nomme mcp__plugin_<plugin>_<serveur>__set_current_task.
TASK_TOOL = re.compile(r"^mcp__plugin_clockifai_[\w-]+__set_current_task$")
TASK_NAME_MAX = 80

KINDS = {"SessionStart": "session_start", "UserPromptSubmit": "prompt", "PostToolUse": "agent_tool",
         "Stop": "agent_stop", "SubagentStop": "agent_stop", "Notification": "agent_wait",
         "SessionEnd": "session_end"}

# git [options] commit|merge|cherry-pick|revert|am|rebase : les commandes qui créent des commits (D13).
_GIT_OPT = r"""(?:\s+(?:-C\s+(?:"[^"]*"|'[^']*'|\S+)|-c\s+\S+|--[\w-]+(?:=\S+)?|-[A-Za-z]))"""
GIT_WRITE = re.compile(r"(?:^|[\s;&|(`/])git(" + _GIT_OPT + r"*)\s+(?:commit|merge|cherry-pick|revert|am|rebase)(?![\w-])")
_GIT_DIR = re.compile(r"""-C\s+("[^"]*"|'[^']*'|\S+)""")
_SCP = re.compile(r"^(?:[^@/:]+@)?([^/:]+):(?!//)(.+)$")


def cache_dir() -> Path:
    return Path(os.environ.get("CLOCKIFAI_CACHE_DIR") or Path.home() / ".cache" / "clockifai")


def log_error(message: str) -> None:
    """Journal local des échecs (jamais le contenu des événements)."""
    try:
        path = cache_dir() / "hook.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.stat().st_size > 100_000:
            path.write_text("")
        with path.open("a", encoding="utf-8") as f:
            f.write(f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} {message}\n")
    except OSError:
        pass


def default_url() -> str | None:
    """Adresse par défaut du plugin, que l'instance qui le distribue écrit dans plugin.json. Claude Code la montre
    « not set » et ne la passe pas au hook tant qu'elle n'est pas réglée (vérifié avec la v2.1.309)."""
    root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    base = Path(root) if root else Path(__file__).resolve().parent.parent
    try:
        manifest = json.loads((base / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
        return manifest["userConfig"]["url"].get("default") or None
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return None


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).isoformat(timespec="milliseconds")


def _key(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()[:20]


class _Locked:
    """Fichier JSON d'état, verrouillé le temps de le lire et de le réécrire."""

    def __init__(self, path: Path):
        self.path = path

    def __enter__(self) -> dict:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.f = open(self.path, "a+", encoding="utf-8")
        if fcntl:
            fcntl.flock(self.f, fcntl.LOCK_EX)
        self.f.seek(0)
        try:
            self.state = json.loads(self.f.read() or "{}")
        except ValueError:
            self.state = {}
        return self.state

    def __exit__(self, *exc) -> None:
        if exc[0] is None:
            self.f.seek(0)
            self.f.truncate()
            self.f.write(json.dumps(self.state))
            self.f.flush()
        self.f.close()


# ---------------------------------------------------------------- git
def git(cwd: str, *args: str) -> str | None:
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0", LC_ALL="C")
    try:
        out = subprocess.run(["git", "-C", cwd, *args], check=False, capture_output=True, encoding="utf-8",
                             errors="replace", timeout=3, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def normalize_remote(url: str | None) -> str | None:
    """URL distante → `hôte/chemin` sans protocole, utilisateur, port ni `.git`, en minuscules (D9, plan 09 P3)."""
    url = (url or "").strip()
    if not url:
        return None
    if "://" in url:
        parts = urllib.parse.urlsplit(url)
        if parts.scheme == "file" or not parts.hostname:
            return None
        host, path = parts.hostname, parts.path
    else:
        m = _SCP.match(url)
        if not m or len(m.group(1)) == 1:  # chemin local, ou lecteur Windows « C: »
            return None
        host, path = m.group(1), m.group(2)
    path = path.strip("/")
    if path.endswith(".git"):
        path = path[:-4].rstrip("/")
    return f"{host}/{path}".lower() if path else None


def repo_info(cwd: str) -> dict:
    """Racine du dossier de travail, clé du dépôt et branche. Les worktrees d'un dépôt partagent la clé."""
    out = git(cwd, "rev-parse", "--show-toplevel", "--git-common-dir")
    if not out or len(out.splitlines()) < 2:
        return {"root": None, "remote_key": "local:" + (Path(cwd).name or "racine"), "branch": None}
    root, common = out.splitlines()[:2]
    common = os.path.normpath(os.path.join(cwd, common))
    main = Path(common).parent.name if Path(common).name == ".git" else Path(common).name.removesuffix(".git")
    remote = git(cwd, "config", "--get", "remote.origin.url")
    if remote is None:
        first = (git(cwd, "remote") or "").splitlines()
        remote = git(cwd, "config", "--get", f"remote.{first[0]}.url") if first else None
    return {"root": root, "remote_key": normalize_remote(remote) or f"local:{main}",
            "branch": git(cwd, "symbolic-ref", "--short", "-q", "HEAD")}


def git_write_dirs(command: str, cwd: str) -> list[str]:
    """Dossiers où la commande crée des commits (`git -C …` compris) ; liste vide si elle n'en crée pas."""
    dirs = []
    for m in GIT_WRITE.finditer(command or ""):
        targets = [t.strip("'\"") for t in _GIT_DIR.findall(m.group(1))]
        path = cwd
        for t in targets:
            path = os.path.join(path, os.path.expanduser(t))
        dirs.append(os.path.normpath(path))
    return list(dict.fromkeys(dirs))


def _log_commits(root: str, since_head: str | None) -> list[dict]:
    fmt = "--format=%H%x1f%ct%x1f%aI%x1f%ae%x1f%s%x1e"
    out = git(root, "log", fmt, "-n", "100", f"{since_head}..HEAD") if since_head else None
    if out is None:  # premier commit vu, ou dernier HEAD disparu (gc) : on s'en remet au filtre de date
        out = git(root, "log", fmt, "-n", "100", "HEAD")
    commits = []
    for record in (out or "").split("\x1e"):
        fields = record.strip("\n").split("\x1f")
        if len(fields) == 5 and fields[0]:
            commits.append({"sha": fields[0], "ct": int(fields[1]), "authored_at": fields[2],
                            "email": fields[3], "subject": fields[4][:200]})
    return commits


def commit_events(cwd: str, info: dict, session_id: str | None, claim: bool, cmd_started: float | None,
                  now: float) -> list[dict]:
    """Commits nouveaux du dossier de travail (D13).

    Seule une session dont la commande crée des commits (claim) les revendique : ceux faits pendant sa commande.
    Les autres restent « non revendiqués » et partent sans session après UNCLAIMED_AFTER. Le dernier HEAD vu
    est conservé par dossier de travail (un par worktree).
    """
    root = info["root"]
    if not root:
        return []
    head = git(root, "rev-parse", "-q", "--verify", "HEAD")
    email = (git(root, "config", "--get", "user.email") or "").lower()
    events = []
    with _Locked(cache_dir() / "heads" / f"{_key(root)}.json") as st:
        if "checked_at" not in st:
            if not claim:  # premier passage : point de départ, rien à envoyer
                st.update(head=head, checked_at=now, unclaimed={})
                return []
            # dossier jamais vu, et une commande qui vient d'y commiter : on part du début de la commande
            st.update(head=None, checked_at=(cmd_started or now) - CLAIM_SLACK, unclaimed={})
        unclaimed = st.setdefault("unclaimed", {})
        if head != st.get("head") and email:
            for c in reversed(_log_commits(root, st.get("head"))):  # du plus ancien au plus récent
                if c["email"].lower() == email and c["ct"] >= st["checked_at"] - 60 and c["sha"] not in unclaimed:
                    unclaimed[c["sha"]] = dict(c, first_seen=now, branch=info["branch"])
            if len(unclaimed) > COMMITS_MAX * 5:  # garde-fou : on garde les plus récents
                keep = sorted(unclaimed.items(), key=lambda kv: kv[1]["ct"])[-COMMITS_MAX * 5:]
                st["unclaimed"] = unclaimed = dict(keep)
        st["head"], st["checked_at"] = head, now

        for sha, c in sorted(unclaimed.items(), key=lambda kv: kv[1]["ct"]):
            mine = claim and (cmd_started is None or c["ct"] >= cmd_started - CLAIM_SLACK)
            if mine or now - c["first_seen"] >= UNCLAIMED_AFTER:
                events.append(_commit_event(info, c, session_id if mine else None, cwd, now))
                del unclaimed[sha]
    return events[-COMMITS_MAX:]


def _commit_event(info: dict, c: dict, session_id: str | None, cwd: str, now: float) -> dict:
    return {"id": str(uuid.uuid5(COMMIT_NS, f"clockifai:commit:{info['remote_key']}:{c['sha']}")),
            "kind": "commit", "occurred_at": iso(now), "session_id": session_id, "remote_key": info["remote_key"],
            "git_branch": c.get("branch"), "cwd": cwd, "sha": c["sha"], "subject": c["subject"],
            "author_email": c["email"], "authored_at": c["authored_at"]}


# ---------------------------------------------------------------- événements
def _tool_due(session_id: str, duration_ms, now: float) -> bool:
    """Au plus un agent_tool par minute et par session, sauf un outil long (D7.3, D7.6)."""
    path = cache_dir() / "tools" / _key(session_id)
    try:
        last = float(path.read_text())
    except (OSError, ValueError):
        last = 0.0
    if now - last < TOOL_EVERY and not (isinstance(duration_ms, int) and duration_ms >= LONG_TOOL_MS):
        return False
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(now))
    except OSError:
        pass
    return True


def collect(data: dict, now: float) -> list[dict]:
    """Événements à envoyer pour cet appel du hook."""
    hook = data.get("hook_event_name")
    session_id = data.get("session_id")
    kind = KINDS.get(hook)
    if not kind or not session_id:
        return []
    if hook == "Notification" and data.get("notification_type") != "permission_prompt":
        return []
    duration_ms = data.get("duration_ms")
    if not isinstance(duration_ms, (int, float)) or isinstance(duration_ms, bool) or duration_ms < 0:
        duration_ms = None
    else:
        duration_ms = int(duration_ms)
    tool_due = hook == "PostToolUse" and _tool_due(session_id, duration_ms, now)
    task_tool = hook == "PostToolUse" and isinstance(data.get("tool_name"), str) and bool(
        TASK_TOOL.match(data["tool_name"]))
    if hook == "PostToolUse" and not tool_due and not task_tool and data.get("tool_name") != "Bash":
        return []  # outil fréquent (Read, Edit…) déjà signalé dans la minute : pas même un appel à git

    cwd = data.get("cwd") or os.getcwd()
    info = repo_info(cwd)
    base = {"session_id": session_id, "remote_key": info["remote_key"], "git_branch": info["branch"], "cwd": cwd}
    events = []
    if hook == "PostToolUse":
        if tool_due:
            event = dict(base, id=str(uuid.uuid4()), kind=kind, occurred_at=iso(now))
            if duration_ms is not None:
                event["duration_ms"] = duration_ms
            events.append(event)
        if task_tool:
            # Seule exception à la liste blanche pour tool_input : le nom de tâche que Claude a choisi d'envoyer.
            name = " ".join(str((data.get("tool_input") or {}).get("name") or "").split())[:TASK_NAME_MAX]
            if name:
                events.append(dict(base, id=str(uuid.uuid4()), kind="session_task", occurred_at=iso(now),
                                   payload={"task_name": name}))
    else:
        event = dict(base, id=str(uuid.uuid4()), kind=kind, occurred_at=iso(now))
        if hook == "SessionStart" and data.get("source"):
            event["payload"] = {"source": str(data["source"])[:20]}
        elif hook == "SessionEnd" and data.get("reason"):
            event["payload"] = {"reason": str(data["reason"])[:40]}
        events.append(event)

    # Commits (D13) : après une commande Bash et au Stop. Une commande git qui en crée les revendique.
    # SessionStart pose le point de départ du dossier.
    if hook in ("SessionStart", "Stop") or (hook == "PostToolUse" and data.get("tool_name") == "Bash"):
        command = (data.get("tool_input") or {}).get("command") if hook == "PostToolUse" else None
        claimed = git_write_dirs(command, cwd) if isinstance(command, str) else []
        started = now - duration_ms / 1000 if duration_ms is not None else None
        here = os.path.normpath(cwd)
        for path in claimed:
            target = info if path == here else repo_info(path)
            events += commit_events(path, target, session_id, True, started, now)
        if here not in claimed:
            events += commit_events(cwd, info, session_id, False, None, now)
    return events


# ---------------------------------------------------------------- envoi
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Une redirection ne doit pas emporter le jeton ailleurs : elle est traitée comme une erreur."""

    def redirect_request(self, *args, **kwargs):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def post(url: str, token: str, events: list[dict]) -> bool | None:
    """True : reçu. False : à réessayer (réseau, 5xx, 429, adresse erronée). None : refusé (400, 401, 403)."""
    request = urllib.request.Request(
        url.rstrip("/") + "/api/activity/events", data=json.dumps({"events": events}).encode(), method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                 "User-Agent": "clockifai-claude-code"})
    try:
        with _OPENER.open(request, timeout=HTTP_TIMEOUT):
            return True
    except urllib.error.HTTPError as e:
        hint = " : vérifier l'adresse (https://…, sans /api)" if e.code < 400 or e.code in (404, 405) else ""
        log_error(f"HTTP {e.code} sur {len(events)} événement(s){hint}")
        # Une adresse erronée se corrige : les événements attendent dans la file locale. Un refus est définitif.
        return None if e.code in (400, 401, 403, 413, 422) else False
    except (urllib.error.URLError, OSError, ValueError) as e:
        log_error(f"réseau : {type(e).__name__}")
        return False


def _spool_path() -> Path:
    return cache_dir() / "spool.jsonl"


def spool(events: list[dict]) -> None:
    path = _spool_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            if fcntl:
                fcntl.flock(f, fcntl.LOCK_EX)
            for e in events:
                f.write(json.dumps(e) + "\n")
    except OSError as e:
        log_error(f"file locale : {type(e).__name__}")


def take_spool(now: float) -> list[dict]:
    """Vide la file locale (sans attendre si un autre hook la vide déjà). Événements trop vieux écartés."""
    path = _spool_path()
    if not path.exists():
        return []
    try:
        with path.open("r+", encoding="utf-8") as f:
            if fcntl:
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except OSError:
                    return []
            lines = f.read().splitlines()
            f.seek(0)
            f.truncate()
    except OSError:
        return []
    events = []
    for line in lines[-SPOOL_MAX:]:
        try:
            e = json.loads(line)
            if now - datetime.fromisoformat(e["occurred_at"]).timestamp() < SPOOL_MAX_AGE:
                events.append(e)
        except (ValueError, KeyError, TypeError):
            continue
    return events


def deliver(url: str, token: str, events: list[dict], now: float) -> None:
    if events:
        sent = post(url, token, events)
        if sent is False:
            spool(events)
            return
    pending = take_spool(now)
    for i in range(0, len(pending), BATCH):
        if post(url, token, pending[i:i + BATCH]) is False:
            spool(pending[i:])
            return


def main() -> None:
    try:
        data = json.loads(sys.stdin.buffer.read())  # octets : un prompt accentué ne dépend pas de la locale
    except ValueError:
        return
    url = os.environ.get("CLAUDE_PLUGIN_OPTION_URL") or os.environ.get("CLOCKIFAI_URL") or default_url()
    token = os.environ.get("CLAUDE_PLUGIN_OPTION_TOKEN") or os.environ.get("CLOCKIFAI_TOKEN")
    if not isinstance(data, dict):
        return
    if not url or not token:
        # Sinon le poste n'envoie rien sans laisser de trace : `claude plugin configure clockifai@…` le corrige.
        log_error("réglage manquant : " + ", ".join(n for n, v in (("url", url), ("token", token)) if not v))
        return
    now = time.time()
    deliver(url, token, collect(data, now), now)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 - un hook ne doit jamais gêner Claude
        log_error(f"erreur : {type(e).__name__}")
    sys.exit(0)
