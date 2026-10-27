"""Plugin Claude Code (plan 10, §6.1, D6, D13) : script de hook et marketplace de l'instance, sans base."""

import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from app import create_app
from app.config import TestConfig
from app.routes.claude import PLUGIN_FILES, build_plugin_zip

PLUGIN = Path(__file__).resolve().parents[2] / "integrations" / "claude-code"
SCRIPT = PLUGIN / "scripts" / "clockifai_hook.py"
# Le python3 de macOS (3.9) est celui que trouvent les hooks sur un poste sans Homebrew.
PYTHON = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable
WHITELIST = {"id", "kind", "occurred_at", "session_id", "remote_key", "git_branch", "cwd", "duration_ms", "payload"}


def _load():
    spec = importlib.util.spec_from_file_location("clockifai_hook", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hook = _load()


@pytest.fixture(autouse=True)
def isolated(tmp_path, monkeypatch):
    monkeypatch.setenv("CLOCKIFAI_CACHE_DIR", str(tmp_path / "cache"))
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)  # pas de signature ni d'alias du poste
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")


def sh(cwd, *args, env=None):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True, env=env)


def make_repo(path: Path, remote="git@github.com:Ysimonx/Clockifai.git") -> Path:
    path.mkdir(parents=True)
    sh(path, "git", "init", "-q", "-b", "main")
    sh(path, "git", "config", "user.email", "yannick@example.com")
    sh(path, "git", "config", "user.name", "Yannick")
    if remote:
        sh(path, "git", "remote", "add", "origin", remote)
    commit(path, "Premier commit", ago=3600)
    return path


def commit(path: Path, message: str, email="yannick@example.com", ago=0):
    (path / f"f{time.monotonic_ns()}.txt").write_text(message)
    sh(path, "git", "add", "-A")
    env = dict(os.environ, GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_EMAIL=email)
    if ago:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"@{int(time.time() - ago)} +0000"
    sh(path, "git", "commit", "-q", "-m", message, env=env)


def ev(name, cwd, session="s-a", **extra):
    return {"hook_event_name": name, "session_id": session, "cwd": str(cwd), "transcript_path": "/secret.jsonl",
            **extra}


def bash(cwd, command, session="s-a", duration_ms=1500):
    return ev("PostToolUse", cwd, session, tool_name="Bash", tool_input={"command": command},
              tool_response={"stdout": "secret"}, duration_ms=duration_ms)


def commits_of(events):
    return [e for e in events if e["kind"] == "commit"]


# ---------------------------------------------------------------- liste blanche et événements
def test_normalize_remote():
    n = hook.normalize_remote
    assert n("git@github.com:Ysimonx/Clockifai.git") == "github.com/ysimonx/clockifai"
    assert n("https://github.com/ysimonx/clockifai") == "github.com/ysimonx/clockifai"
    assert n("https://user:tok3n@github.com/ysimonx/clockifai.git/") == "github.com/ysimonx/clockifai"
    assert n("ssh://git@gitlab.exemple.fr:2222/groupe/sous-groupe/projet.git") == \
        "gitlab.exemple.fr/groupe/sous-groupe/projet"
    assert n("gitlab.exemple.fr:groupe/projet") == "gitlab.exemple.fr/groupe/projet"
    for local in ("/srv/git/projet.git", "../projet", "file:///srv/git/projet.git", "C:\\depots\\projet", "", None):
        assert n(local) is None


def test_git_commands_that_create_commits():
    w = hook.git_write_dirs
    assert w('git add -A && git commit -m "$(cat <<EOF\nmsg\nEOF\n)"', "/r") == ["/r"]
    assert w("git -C ../autre -c user.name=x commit -m m", "/r/app") == ["/r/autre"]
    assert w("git -C '/tmp/a b' rebase main", "/r") == ["/tmp/a b"]
    assert w("/usr/bin/git cherry-pick abc; git revert def", "/r") == ["/r"]
    for none in ("git merge-base HEAD main", "git status", "git log --grep commit", "git pull", "echo git",
                 "git commit-tree x", "legit commit"):
        assert w(none, "/r") == [], none


def test_events_carry_only_the_whitelist(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    now = time.time()
    prompt = hook.collect(ev("UserPromptSubmit", repo, prompt="mon secret"), now)
    assert len(prompt) == 1 and prompt[0]["kind"] == "prompt"
    assert set(prompt[0]) <= WHITELIST and "mon secret" not in json.dumps(prompt)
    assert prompt[0]["remote_key"] == "github.com/ysimonx/clockifai" and prompt[0]["git_branch"] == "main"
    tool = hook.collect(bash(repo, "cat ~/.ssh/id_rsa", duration_ms=1200), now)
    assert [e["kind"] for e in tool] == ["agent_tool"] and tool[0]["duration_ms"] == 1200
    assert "id_rsa" not in json.dumps(tool) and "secret" not in json.dumps(tool)
    stop = hook.collect(ev("Stop", repo, last_assistant_message="réponse"), now)
    assert [e["kind"] for e in stop] == ["agent_stop"] and "réponse" not in json.dumps(stop)


def test_notifications_and_unknown_hooks(tmp_path):
    now = time.time()
    assert hook.collect(ev("Notification", tmp_path, notification_type="idle_prompt", message="m"), now) == []
    wait = hook.collect(ev("Notification", tmp_path, notification_type="permission_prompt", message="m"), now)
    assert [e["kind"] for e in wait] == ["agent_wait"] and "message" not in wait[0]
    assert hook.collect(ev("PreToolUse", tmp_path), now) == []
    assert hook.collect({"hook_event_name": "Stop"}, now) == []
    assert hook.collect(ev("SessionStart", tmp_path, source="resume"), now)[0]["payload"] == {"source": "resume"}
    assert hook.collect(ev("SessionEnd", tmp_path, reason="other"), now)[0]["payload"] == {"reason": "other"}


def test_folder_outside_git(tmp_path):
    folder = tmp_path / "notes"
    folder.mkdir()
    e = hook.collect(ev("UserPromptSubmit", folder), time.time())[0]
    assert e["remote_key"] == "local:notes" and e["git_branch"] is None


def test_tool_events_are_throttled_except_long_tools(tmp_path):
    now = time.time()
    tool = ev("PostToolUse", tmp_path, tool_name="Read", duration_ms=50)
    assert len(hook.collect(tool, now)) == 1
    assert hook.collect(tool, now + 30) == []
    assert len(hook.collect(dict(tool, duration_ms=900_000), now + 31)) == 1  # commande longue (D7.6)
    assert len(hook.collect(dict(tool, session_id="s-b"), now + 32)) == 1    # par session
    assert len(hook.collect(tool, now + 95)) == 1


# ---------------------------------------------------------------- commits (D13)
def test_commit_claimed_by_the_session_that_made_it(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    hook.collect(ev("SessionStart", repo), time.time())
    commit(repo, "Ajout de l'export")
    events = hook.collect(bash(repo, "git commit -m x"), time.time())
    [c] = commits_of(events)
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True,
                         text=True).stdout.strip()
    assert c["session_id"] == "s-a" and c["sha"] == sha and c["subject"] == "Ajout de l'export"
    assert c["remote_key"] == "github.com/ysimonx/clockifai" and c["author_email"] == "yannick@example.com"
    assert c["authored_at"] and c["git_branch"] == "main"
    assert commits_of(hook.collect(bash(repo, "git commit -m x"), time.time())) == []  # pas deux fois


def test_three_commits_in_one_command_then_amend(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    hook.collect(ev("SessionStart", repo), time.time())
    for i in range(3):
        commit(repo, f"Commit {i}")
    events = commits_of(hook.collect(bash(repo, "for i in 1 2 3; do git commit -am m; done"), time.time()))
    assert [c["subject"] for c in events] == ["Commit 0", "Commit 1", "Commit 2"]
    sh(repo, "git", "commit", "-q", "--amend", "-m", "Commit 2 corrigé")
    [amended] = commits_of(hook.collect(bash(repo, "git commit --amend -m m"), time.time()))
    assert amended["subject"] == "Commit 2 corrigé" and amended["sha"] != events[-1]["sha"]


def test_other_peoples_commits_and_branch_switch_produce_nothing(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    hook.collect(ev("SessionStart", repo), time.time())
    sh(repo, "git", "checkout", "-q", "-b", "autre")
    commit(repo, "Commit d'une collègue", email="collegue@example.com")
    assert commits_of(hook.collect(bash(repo, "git merge collegue/main"), time.time())) == []
    sh(repo, "git", "checkout", "-q", "main")
    assert commits_of(hook.collect(bash(repo, "git checkout main"), time.time())) == []
    assert commits_of(hook.collect(ev("Stop", repo), time.time() + 700)) == []


def test_two_sessions_in_the_same_folder(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    hook.collect(ev("SessionStart", repo, session="s-a"), time.time())
    commit(repo, "Travail de A")
    # B lance une commande juste avant que le hook de A ne vérifie : il ne prend rien.
    assert commits_of(hook.collect(bash(repo, "npm test", session="s-b"), time.time())) == []
    assert commits_of(hook.collect(ev("Stop", repo, session="s-b"), time.time())) == []
    [c] = commits_of(hook.collect(bash(repo, "git commit -m x", session="s-a"), time.time()))
    assert c["session_id"] == "s-a" and c["subject"] == "Travail de A"


def test_commit_made_outside_claude_leaves_without_session(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    now = time.time()
    hook.collect(ev("SessionStart", repo), now)
    commit(repo, "Commit à la main")
    assert commits_of(hook.collect(ev("Stop", repo), now + 1)) == []
    [c] = commits_of(hook.collect(ev("Stop", repo), now + hook.UNCLAIMED_AFTER + 2))
    assert c["session_id"] is None and c["subject"] == "Commit à la main"


def test_old_commit_is_not_claimed_by_a_later_command(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    hook.collect(ev("SessionStart", repo), time.time())
    commit(repo, "Commit à la main")
    hook.collect(bash(repo, "ls"), time.time())
    # Une commande git de la session, commencée après ce commit : il ne lui appartient pas.
    later = time.time() + 30
    assert commits_of(hook.collect(bash(repo, "git commit -m x", duration_ms=2000), later)) == []


def test_first_commit_in_a_folder_never_seen(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    commit(repo, "Premier vu")
    [c] = commits_of(hook.collect(bash(repo, "git commit -m x"), time.time()))
    assert c["subject"] == "Premier vu" and c["session_id"] == "s-a"


def test_worktrees_share_the_key_but_not_the_last_head(tmp_path):
    repo = make_repo(tmp_path / "clockifai", remote=None)
    wt = tmp_path / "clockifai-wt2"
    sh(repo, "git", "worktree", "add", "-q", "-b", "plan-10", str(wt))
    a = hook.collect(ev("SessionStart", repo), time.time())[0]
    b = hook.collect(ev("SessionStart", wt, session="s-b"), time.time())[0]
    assert a["remote_key"] == b["remote_key"] == "local:clockifai"
    assert b["git_branch"] == "plan-10"
    commit(wt, "Dans le worktree")
    assert commits_of(hook.collect(bash(repo, "git commit -m x"), time.time())) == []
    [c] = commits_of(hook.collect(bash(wt, "git commit -m x", session="s-b"), time.time()))
    assert c["subject"] == "Dans le worktree" and c["git_branch"] == "plan-10"


def test_commit_id_is_stable(tmp_path):
    repo = make_repo(tmp_path / "clockifai")
    commit(repo, "x")
    [c] = commits_of(hook.collect(bash(repo, "git commit -m x"), time.time()))
    import uuid
    assert c["id"] == str(uuid.uuid5(uuid.NAMESPACE_URL, f"clockifai:commit:github.com/ysimonx/clockifai:{c['sha']}"))


# ---------------------------------------------------------------- processus réel, serveur local
class _Server:
    def __init__(self):
        self.received, self.status, self.location = [], 202, None
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length)) if length else None
                outer.received.append((self.path, self.headers["Authorization"], body))
                self.send_response(outer.status)
                if outer.location:
                    self.send_header("Location", outer.location)
                self.end_headers()

            do_GET = do_POST

            def log_message(self, *args):
                pass

        self.httpd = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_port}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def run_hook(data, url, cache, token="clk_test", **extra_env):
    env = dict(os.environ, CLAUDE_PLUGIN_OPTION_URL=url, CLAUDE_PLUGIN_OPTION_TOKEN=token,
               CLOCKIFAI_CACHE_DIR=str(cache), **extra_env)
    stdin = data if isinstance(data, str) else json.dumps(data)
    return subprocess.run([PYTHON, str(SCRIPT)], input=stdin, check=False, capture_output=True, text=True, env=env,
                          timeout=20)


def test_script_posts_and_never_writes_on_stdout(tmp_path):
    server = _Server()
    try:
        out = run_hook(ev("UserPromptSubmit", tmp_path, prompt="secret"), server.url, tmp_path / "cache")
        assert out.returncode == 0 and out.stdout == "" and out.stderr == ""
        [(path, auth, body)] = server.received
        assert path == "/api/activity/events" and auth == "Bearer clk_test"
        assert [e["kind"] for e in body["events"]] == ["prompt"] and "secret" not in json.dumps(body)
        for junk in ("pas du json", "[]"):
            out = run_hook(junk, server.url, tmp_path / "cache")
            assert out.returncode == 0 and out.stdout == ""
        out = run_hook(ev("Stop", tmp_path), server.url, tmp_path / "cache", token="")  # jeton non réglé
        assert out.returncode == 0 and out.stdout == "" and len(server.received) == 1
        assert "réglage manquant : token" in (tmp_path / "cache" / "hook.log").read_text()
    finally:
        server.close()


def test_url_not_set_falls_back_to_the_instance_default(tmp_path):
    """Claude Code ne transmet pas la valeur par défaut d'un userConfig (« not set ») : le script la relit dans le
    plugin.json que l'instance a écrit, sans quoi un poste configuré avec son seul jeton n'enverrait rien."""
    server = _Server()
    try:
        root = tmp_path / "plugin"
        (root / ".claude-plugin").mkdir(parents=True)
        manifest = json.loads((PLUGIN / ".claude-plugin" / "plugin.json").read_text())
        manifest["userConfig"]["url"]["default"] = server.url
        (root / ".claude-plugin" / "plugin.json").write_text(json.dumps(manifest))
        out = run_hook(ev("UserPromptSubmit", tmp_path), "", tmp_path / "cache", CLAUDE_PLUGIN_ROOT=str(root))
        assert out.returncode == 0 and out.stdout == ""
        assert [path for path, _, _ in server.received] == ["/api/activity/events"]
    finally:
        server.close()


def test_spool_when_the_server_is_down(tmp_path):
    cache = tmp_path / "cache"
    server = _Server()
    url = server.url
    server.close()
    for name in ("UserPromptSubmit", "Stop"):
        assert run_hook(ev(name, tmp_path), url, cache).returncode == 0
    assert len((cache / "spool.jsonl").read_text().splitlines()) == 2
    assert "réseau" in (cache / "hook.log").read_text()

    server = _Server()
    try:
        run_hook(ev("UserPromptSubmit", tmp_path), server.url, cache)
        kinds = [e["kind"] for _, _, body in server.received for e in body["events"]]
        assert sorted(kinds) == ["agent_stop", "prompt", "prompt"]
        assert (cache / "spool.jsonl").read_text() == ""
        server.status = 401  # jeton révoqué : rien n'est gardé
        run_hook(ev("Stop", tmp_path), server.url, cache)
        assert (cache / "spool.jsonl").read_text() == ""
        assert "HTTP 401" in (cache / "hook.log").read_text()
    finally:
        server.close()


# ---------------------------------------------------------------- tâche nommée par Claude (D18)
TASK_TOOL = "mcp__plugin_clockifai_clockifai__set_current_task"


def test_mcp_server_names_the_task_without_any_network():
    lines = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "claude-code"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
         "params": {"name": "set_current_task", "arguments": {"name": "  Export   PDF  "}}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "set_current_task", "arguments": {}}},
        {"jsonrpc": "2.0", "id": 5, "method": "resources/list"},
        {"jsonrpc": "2.0", "id": 6, "method": "tools/call",
         "params": {"name": "set_current_task", "arguments": {"name": "Plan 16 · Sous-tâches", "step": " Migration "}}},
    ]
    stdin = "\n".join(json.dumps(x) for x in lines) + "\npas du json\n"
    out = subprocess.run([PYTHON, str(PLUGIN / "scripts" / "clockifai_mcp.py")], input=stdin, capture_output=True,
                         text=True, check=True, timeout=20, env={"PATH": os.environ.get("PATH", "")})
    replies = {r["id"]: r for r in map(json.loads, out.stdout.splitlines())}
    assert sorted(replies) == [1, 2, 3, 4, 5, 6] and out.stderr == "", "une réponse par requête, rien d'autre"
    init = replies[1]["result"]
    assert init["protocolVersion"] == "2025-11-25" and init["capabilities"] == {"tools": {}}
    assert "set_current_task" in init["instructions"] and "simple salutation" in init["instructions"]
    assert "`step`" in init["instructions"] and "plan numéroté" in init["instructions"], "l'objectif, puis l'étape"
    [tool] = replies[2]["result"]["tools"]
    assert tool["name"] == "set_current_task" and tool["inputSchema"]["required"] == ["name"]
    assert set(tool["inputSchema"]["properties"]) == {"name", "step"}
    assert replies[3]["result"]["content"][0]["text"].startswith("Tâche « Export PDF »")
    assert replies[3]["result"]["isError"] is False and replies[4]["result"]["isError"] is True
    assert replies[5]["error"]["code"] == -32601
    assert replies[6]["result"]["content"][0]["text"].startswith("Tâche « Plan 16 · Sous-tâches » › « Migration »")


def test_mcp_server_survives_an_ascii_locale_and_odd_requests():
    lines = [
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [1]},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
         "params": {"name": "set_current_task", "arguments": {"name": "Révision du thème"}}},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "set_current_task", "arguments": "x"}},
    ]
    stdin = ("\n".join(json.dumps(x, ensure_ascii=False) for x in lines) + "\n").encode("utf-8")
    out = subprocess.run([PYTHON, str(PLUGIN / "scripts" / "clockifai_mcp.py")], input=stdin, capture_output=True,
                         check=True, timeout=20, env={"PATH": os.environ.get("PATH", ""), "LC_ALL": "C", "LANG": "C"})
    replies = {r["id"]: r for r in map(json.loads, out.stdout.decode("utf-8").splitlines())}
    assert sorted(replies) == [1, 2, 3] and out.stderr == b""
    assert replies[2]["result"]["content"][0]["text"].startswith("Tâche « Révision du thème »")
    assert replies[3]["result"]["isError"] is True


def test_hook_relays_the_task_name_and_nothing_else(tmp_path):
    server = _Server()
    try:
        call = ev("PostToolUse", tmp_path, tool_name=TASK_TOOL, tool_input={"name": " Export  PDF ", "autre": "secret"},
                  tool_response={"content": [{"type": "text", "text": "secret"}]})
        for _ in range(2):  # le second appel tombe dans la minute des outils : le nom part quand même
            assert run_hook(call, server.url, tmp_path / "cache").returncode == 0
        named = [e for _, _, body in server.received for e in body["events"] if e["kind"] == "session_task"]
        assert [e["payload"] for e in named] == [{"task_name": "Export PDF"}] * 2
        assert "secret" not in json.dumps([body for _, _, body in server.received])
        step = ev("PostToolUse", tmp_path, tool_name=TASK_TOOL, tool_input={"name": "Plan 16", "step": " Migration  SQL "})
        run_hook(step, server.url, tmp_path / "cache")
        named = [e for _, _, body in server.received for e in body["events"] if e["kind"] == "session_task"]
        assert named[-1]["payload"] == {"task_name": "Plan 16", "step_name": "Migration SQL"}, "l'étape suit l'objectif"
        other = ev("PostToolUse", tmp_path, tool_name="mcp__autre__set_current_task", tool_input={"name": "X"})
        run_hook(other, server.url, tmp_path / "cache")
        kinds = [e["kind"] for _, _, body in server.received for e in body["events"]]
        assert kinds.count("session_task") == 3, "seul l'outil du plugin Clockifai nomme la tâche"
    finally:
        server.close()


# ---------------------------------------------------------------- usage IA lu dans la transcription (D17)
SLOT = 300


def assistant(message_id, at, model="claude-opus-5-5", effort="xhigh", speed="standard", **usage):
    counts = {"input_tokens": 2, "output_tokens": 100, "cache_creation_input_tokens": 1000,
              "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 1000},
              "cache_read_input_tokens": 5000, "speed": speed, "service_tier": "standard", **usage}
    return {"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(at)),
            "effort": effort, "sessionId": "s-a", "cwd": "/secret/dossier",
            "message": {"id": message_id, "model": model, "role": "assistant",
                        "content": [{"type": "text", "text": "réponse secrète"}], "usage": counts}}


def write_lines(path: Path, lines, end="\n"):
    with path.open("a", encoding="utf-8") as f:
        f.write("\n".join(line if isinstance(line, str) else json.dumps(line) for line in lines) + end)


def usage_of(events):
    return [e for e in events if e["kind"] == "agent_usage"]


def test_usage_totals_leave_without_any_text(tmp_path):
    transcript = tmp_path / "s-a.jsonl"
    base = (time.time() // SLOT - 2) * SLOT  # début d'une tranche de 5 minutes, il y a 10 minutes
    write_lines(transcript, [
        {"type": "user", "message": {"role": "user", "content": "mon prompt secret"}},
        assistant("m1", base + 10), assistant("m1", base + 11),  # une réponse sur deux lignes : comptée une fois
        assistant("m2", base + 20, cache_creation=None),  # sans détail : écriture au tarif de 5 minutes
        assistant("m3", base + 30, model="<synthetic>"),  # message de Claude Code, pas un appel à l'API
        assistant("m4", base + SLOT + 5, effort="high"),
        "pas du json", {"type": "assistant", "message": "format inconnu"},
    ])
    write_lines(transcript, [assistant("m5", base + SLOT + 6)], end="")  # ligne en cours d'écriture
    events = hook.collect(ev("Stop", tmp_path, transcript_path=str(transcript)), time.time())
    usage = usage_of(events)
    assert all(set(e) <= WHITELIST for e in events)
    text = json.dumps(events)
    assert "secret" not in text and "réponse" not in text and "dossier" not in text.replace(str(tmp_path), "")
    assert [(e["payload"]["effort"], e["payload"]["requests"]) for e in usage] == [("xhigh", 2), ("high", 1)]
    first = usage[0]["payload"]
    assert first == {"model": "claude-opus-5-5", "effort": "xhigh", "speed": "standard", "requests": 2,
                     "input_tokens": 4, "output_tokens": 200, "cache_write_5m_tokens": 1000,
                     "cache_write_1h_tokens": 1000, "cache_read_tokens": 10000}
    assert usage[0]["occurred_at"].startswith(time.strftime("%Y-%m-%dT%H:%M:20", time.gmtime(base)))

    # La suite de la transcription : seule la ligne terminée depuis est lue, rien n'est recompté.
    write_lines(transcript, ["", assistant("m6", base + SLOT + 7, speed="fast")], end="\n")
    later = usage_of(hook.collect(ev("Stop", tmp_path, transcript_path=str(transcript)), time.time()))
    assert sorted((e["payload"]["speed"], e["payload"]["requests"]) for e in later) == [("fast", 1), ("standard", 1)]
    assert usage_of(hook.collect(ev("Stop", tmp_path, transcript_path=str(transcript)), time.time())) == []


def test_usage_ids_are_stable_and_subagents_are_read_once(tmp_path, monkeypatch):
    transcript = tmp_path / "s-a.jsonl"
    subagents = tmp_path / "s-a" / "subagents"
    subagents.mkdir(parents=True)
    now = time.time()
    write_lines(transcript, [assistant("m1", now - 60)])
    write_lines(subagents / "agent-x.jsonl", [assistant("h1", now - 50, model="claude-haiku-5-5", effort="medium")])
    stop = ev("Stop", tmp_path, transcript_path=str(transcript))
    first = usage_of(hook.collect(stop, now))
    assert sorted(e["payload"]["model"] for e in first) == ["claude-haiku-5-5", "claude-opus-5-5"]
    # Même contenu relu ailleurs (file locale perdue, autre cache) : mêmes id, le serveur ne compte qu'une fois.
    monkeypatch.setenv("CLOCKIFAI_CACHE_DIR", str(tmp_path / "autre-cache"))
    assert sorted(e["id"] for e in usage_of(hook.collect(stop, now))) == sorted(e["id"] for e in first)

    write_lines(subagents / "agent-x.jsonl", [assistant("h2", now - 10, model="claude-haiku-5-5", effort="medium")])
    sub = ev("SubagentStop", tmp_path, transcript_path=str(transcript),
             agent_transcript_path=str(subagents / "agent-x.jsonl"))
    assert [e["payload"]["requests"] for e in usage_of(hook.collect(sub, now))] == [1]
    assert usage_of(hook.collect(stop, now)) == [], "le Stop suivant ne recompte pas le sous-agent"


def test_rewritten_transcript_is_not_counted_again(tmp_path):
    transcript = tmp_path / "s-a.jsonl"
    write_lines(transcript, [assistant(f"m{i}", time.time() - 60) for i in range(3)])
    stop = ev("Stop", tmp_path, transcript_path=str(transcript))
    assert [e["payload"]["requests"] for e in usage_of(hook.collect(stop, time.time()))] == [3]
    transcript.write_text("")  # réécrite plus courte
    write_lines(transcript, [assistant("m9", time.time() - 30)])
    assert usage_of(hook.collect(stop, time.time())) == [], "position au-delà de la fin : on repart de la fin"


# ---------------------------------------------------------------- marketplace de l'instance
@pytest.fixture
def client():
    with create_app(TestConfig).test_client() as c:
        yield c


def test_marketplace_points_to_a_reproducible_archive(client):
    headers = {"Host": "clockifai.example.com", "X-Forwarded-Proto": "https"}
    market = client.get("/api/claude/marketplace.json", headers=headers).get_json()
    assert market["name"] == "clockifai" and market["owner"]["name"]
    [plugin] = market["plugins"]
    assert plugin["name"] == "clockifai"
    source = plugin["source"]
    assert source["source"] == "archive"
    assert source["url"] == "https://clockifai.example.com/api/claude/clockifai-plugin.zip"

    rv = client.get("/api/claude/clockifai-plugin.zip", headers=headers)
    assert rv.status_code == 200 and rv.mimetype == "application/zip"
    assert hashlib.sha256(rv.data).hexdigest() == source["sha256"]
    with zipfile.ZipFile(io.BytesIO(rv.data)) as z:
        assert sorted(z.namelist()) == sorted(PLUGIN_FILES)
        manifest = json.loads(z.read(".claude-plugin/plugin.json"))
        assert manifest["userConfig"]["url"]["default"] == "https://clockifai.example.com"
        assert manifest["userConfig"]["token"]["sensitive"] is True
        assert z.getinfo("scripts/clockifai_hook.py").external_attr >> 16 & 0o111
        assert z.getinfo("scripts/clockifai_mcp.py").external_attr >> 16 & 0o111
        server = json.loads(z.read(".mcp.json"))["mcpServers"]["clockifai"]
        assert server["args"] == ["${CLAUDE_PLUGIN_ROOT}/scripts/clockifai_mcp.py"]
        assert json.loads(z.read("hooks/hooks.json"))["hooks"]["Notification"][0]["matcher"] == "permission_prompt"
    assert build_plugin_zip(PLUGIN, "https://a") == build_plugin_zip(PLUGIN, "https://a") != \
        build_plugin_zip(PLUGIN, "https://b")


def test_marketplace_without_plugin_files(client, tmp_path):
    client.application.config["CLAUDE_PLUGIN_DIR"] = str(tmp_path)
    assert client.get("/api/claude/marketplace.json").status_code == 404


def test_hooks_json_runs_the_script_asynchronously():
    hooks = json.loads((PLUGIN / "hooks" / "hooks.json").read_text())["hooks"]
    assert set(hooks) == set(hook.KINDS)
    for groups in hooks.values():
        for h in groups[0]["hooks"]:
            assert h["async"] is True and "${CLAUDE_PLUGIN_ROOT}/scripts/clockifai_hook.py" in h["command"]
    assert shutil.which("git")


def test_accented_prompt_whatever_the_locale(tmp_path):
    server = _Server()
    try:
        out = run_hook(ev("UserPromptSubmit", tmp_path, prompt="déjà réglé, café ☕"), server.url, tmp_path / "cache",
                       PYTHONIOENCODING="ascii", LC_ALL="C", LANG="C")
        assert out.returncode == 0 and out.stdout == ""
        assert [e["kind"] for _, _, body in server.received for e in body["events"]] == ["prompt"]
    finally:
        server.close()


def test_redirects_keep_the_token_and_wrong_addresses_keep_the_events(tmp_path):
    cache = tmp_path / "cache"
    elsewhere, server = _Server(), _Server()
    try:
        server.location = f"{elsewhere.url}/api/activity/events"
        for status in (302, 308):  # une 302 changerait le POST en GET, en-tête Authorization compris
            server.status = status
            run_hook(ev("UserPromptSubmit", tmp_path), server.url, cache)
            assert f"HTTP {status}" in (cache / "hook.log").read_text()
        assert elsewhere.received == [] and "vérifier l'adresse" in (cache / "hook.log").read_text()
        server.status, server.location = 404, None
        run_hook(ev("Stop", tmp_path), server.url, cache)
        assert len((cache / "spool.jsonl").read_text().splitlines()) == 3  # gardés jusqu'à l'adresse corrigée
        server.status = 202
        run_hook(ev("Stop", tmp_path), server.url, cache)
        assert (cache / "spool.jsonl").read_text() == ""
    finally:
        elsewhere.close()
        server.close()


def test_command_parsing_stays_fast_on_huge_commands():
    command = " ".join(["git -C a -c b=c --no-pager -P status;"] * 5000) + " echo " + "-x " * 20000
    started = time.monotonic()
    assert hook.git_write_dirs(command, "/r") == []
    assert time.monotonic() - started < 1
