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
