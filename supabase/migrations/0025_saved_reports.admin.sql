-- 0025 — Rapports enregistrés et lien public (exécuté en tant que supabase_admin).
-- Plan : plans/18-rapports-presence-alertes-partage.md (lot 3).
--
-- Un rapport enregistré par un manager : période (relative ou fixe), filtres et options d'affichage. Un jeton le rend
-- lisible sans compte (`/api/reports/public/<jeton>`) ; il reste lisible tant que son créateur est manager actif du
-- workspace. Géré par Flask seulement : hors API, hors réplication.
create table if not exists clockifai_private.saved_reports (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  period text not null check (period in ('this_week', 'last_week', 'this_month', 'last_month', 'this_year', 'custom')),
  date_from date,
  date_to date,
  filters jsonb not null default '{}'::jsonb,
  detailed boolean not null default false,
  show_amounts boolean not null default true,
  rounding boolean not null default false,
  public_token text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (period <> 'custom' or (date_from is not null and date_to is not null and date_from <= date_to))
);
create index if not exists saved_reports_workspace_idx on clockifai_private.saved_reports(workspace_id);

alter table clockifai_private.saved_reports owner to postgres;
revoke all on clockifai_private.saved_reports from public, anon, authenticated, powersync_role;
