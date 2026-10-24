-- 0012 — Suivi de Claude Code : tables privées (exécuté en tant que supabase_admin).
-- Plan : plans/10-suivi-claude-code.md (§4).
--
-- `postgres` n'a que `usage` sur clockifai_private (0008) : les tables s'y créent ici, puis sont données à
-- postgres (Flask s'y connecte ainsi) et retirées de l'API comme de la réplication.

-- Jetons d'API personnels (D5) : un par poste, pour un utilisateur et un workspace.
create table if not exists clockifai_private.api_tokens (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  token_hash text not null unique,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index if not exists api_tokens_user_idx on clockifai_private.api_tokens(user_id);

-- Événements bruts des hooks et de l'extension VSCode (D6), purgés après 30 jours.
-- `id` est la clé d'idempotence : event_id du hook, ou uuid5(remote_key, sha) pour un commit.
create table if not exists clockifai_private.activity_events (
  id uuid primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  token_id uuid references clockifai_private.api_tokens(id) on delete set null,
  actor text not null check (actor in ('agent', 'human')),
  kind text not null check (kind in (
    'prompt', 'agent_tool', 'agent_stop', 'agent_wait', 'session_start', 'session_end',
    'session_task', 'session_description',
    'focus_start', 'focus_alive', 'focus_end', 'edit', 'terminal', 'commit', 'presence')),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  session_id text,
  window_id text,
  remote_key text,
  cwd text,
  git_branch text,
  sha text,
  subject text,
  author_email text,
  authored_at timestamptz,
  editor text,
  machine text,
  active boolean,
  payload jsonb,
  excerpt text
);
create index if not exists activity_events_user_idx on clockifai_private.activity_events(user_id, occurred_at);
create index if not exists activity_events_session_idx on clockifai_private.activity_events(session_id, occurred_at)
  where session_id is not null;

-- État de chaque entrée d'agent (D7) : sa session, son dépôt, et les valeurs écrites par le serveur. Une
-- valeur de l'entrée qui en diffère a été retouchée par un humain, et le serveur n'y touche plus (D7.8).
create table if not exists clockifai_private.agent_entries (
  time_entry_id uuid primary key references public.time_entries(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  agent_user_id uuid not null references auth.users(id) on delete cascade,
  session_id text not null,
  remote_key text,
  git_branch text,
  cwd text,
  last_activity_at timestamptz not null,
  waiting_since timestamptz,
  closed_by_idle boolean not null default false,
  server_start_at timestamptz not null,
  server_end_at timestamptz,
  server_project_id uuid,
  server_task_id uuid,
  server_description text not null default '',
  description_source text not null default 'auto' check (description_source in ('auto', 'claude')),
  prompt_count integer not null default 0,
  commit_count integer not null default 0
);
create index if not exists agent_entries_session_idx on clockifai_private.agent_entries(session_id);

alter table clockifai_private.api_tokens owner to postgres;
alter table clockifai_private.activity_events owner to postgres;
alter table clockifai_private.agent_entries owner to postgres;
revoke all on clockifai_private.api_tokens, clockifai_private.activity_events, clockifai_private.agent_entries
  from public, anon, authenticated, powersync_role;
