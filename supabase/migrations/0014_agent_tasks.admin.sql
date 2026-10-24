-- 0014 — Tâches créées par le serveur pour les sessions de Claude (exécuté en tant que supabase_admin).
-- Plan : plans/10-suivi-claude-code.md (D18, « préciser = renommer »).
--
-- Quand Claude précise le nom de son sujet, le serveur renomme la tâche qu'il a créée pour la session au lieu d'en
-- créer une autre ; en mode « une tâche par session », c'est aussi ainsi qu'il retrouve la tâche de la session.
-- `name` est le nom que le serveur a posé : s'il diffère de tasks.name, un humain l'a renommée et la tâche n'est
-- plus jamais touchée. Comme 0012 : table privée, donnée à postgres, hors API et hors réplication.
create table if not exists clockifai_private.agent_tasks (
  task_id uuid primary key references public.tasks(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  session_id text not null,
  name text not null,
  created_at timestamptz not null default now()
);
create index if not exists agent_tasks_session_idx on clockifai_private.agent_tasks(session_id);

alter table clockifai_private.agent_tasks owner to postgres;
revoke all on clockifai_private.agent_tasks from public, anon, authenticated, powersync_role;
