-- 0016 — Usage IA des entrées d'agent : tokens, modèle, effort et coût estimé (exécuté en tant que postgres).
-- Plan : plans/10-suivi-claude-code.md (D17, lot 7).
--
-- Le plugin lit la transcription de Claude Code sur le poste et n'envoie que des totaux (événements `agent_usage`) ;
-- Flask les rattache à l'entrée d'agent qui couvre leur heure et tient ici un cumul par (entrée, modèle, effort,
-- vitesse), recalculé à chaque événement de la session. Visible de ceux qui voient l'entrée, synchronisé avec elle.

-- ===========================================================================
-- 0. Nouveau type d'événement d'activité (table privée de 0012, dont postgres est propriétaire)
-- ===========================================================================
alter table clockifai_private.activity_events drop constraint if exists activity_events_kind_check;
alter table clockifai_private.activity_events add constraint activity_events_kind_check check (kind in (
  'prompt', 'agent_tool', 'agent_stop', 'agent_wait', 'session_start', 'session_end', 'session_task',
  'session_description', 'agent_usage', 'focus_start', 'focus_alive', 'focus_end', 'edit', 'terminal', 'commit',
  'presence'));

-- ===========================================================================
-- 1. Tarifs publics de l'API Anthropic, en dollars US par million de tokens
-- ===========================================================================
-- Données de référence, sans workspace : mises à jour avec Clockifai (nouvelle migration), lues par Flask seulement.
-- Un modèle daté (claude-haiku-4-5-20251001) prend le tarif de son nom sans date.
create table if not exists public.ai_model_prices (
  model text primary key,
  input_per_mtok numeric(12, 4) not null,
  output_per_mtok numeric(12, 4) not null,
  cache_write_5m_per_mtok numeric(12, 4) not null,
  cache_write_1h_per_mtok numeric(12, 4) not null,
  cache_read_per_mtok numeric(12, 4) not null,
  fast_multiplier numeric(6, 3),           -- mode rapide (speed = fast) : tout le tarif multiplié ; null = sans
  priced_on date not null,                 -- date du relevé sur platform.claude.com/docs/en/about-claude/pricing
  updated_at timestamptz not null default now()
);
create trigger ai_model_prices_updated_at before update on public.ai_model_prices
  for each row execute function public.set_updated_at();

-- Relevé du 26 octobre 2026. Claude Haiku 5.5 : tarif des prompts jusqu'à 100 000 tokens (au-delà, ×5, non
-- distingué ici) ; l'inférence limitée aux États-Unis (×1,1) n'est pas distinguée non plus.
insert into public.ai_model_prices
  (model, input_per_mtok, output_per_mtok, cache_write_5m_per_mtok, cache_write_1h_per_mtok, cache_read_per_mtok,
   fast_multiplier, priced_on)
values
  ('claude-fable-5-1',  10, 50, 12.5,  20, 0.25, null, '2026-10-26'),
  ('claude-mythos-5-1', 10, 50, 12.5,  20, 0.25, null, '2026-10-26'),
  ('claude-fable-5',    10, 50, 12.5,  20, 1,    null, '2026-10-26'),
  ('claude-mythos-5',   10, 50, 12.5,  20, 1,    null, '2026-10-26'),
  ('claude-opus-5-5',    4, 20, 5,      8, 0.20, 2,    '2026-10-26'),
  ('claude-opus-5',      5, 25, 6.25,  10, 0.50, 2,    '2026-10-26'),
  ('claude-opus-4-8',    5, 25, 6.25,  10, 0.50, 2,    '2026-10-26'),
  ('claude-opus-4-7',    5, 25, 6.25,  10, 0.50, null, '2026-10-26'),
  ('claude-opus-4-6',    5, 25, 6.25,  10, 0.50, null, '2026-10-26'),
  ('claude-opus-4-5',    5, 25, 6.25,  10, 0.50, null, '2026-10-26'),
  ('claude-opus-4-1',   15, 75, 18.75, 30, 1.50, null, '2026-10-26'),
  ('claude-opus-4',     15, 75, 18.75, 30, 1.50, null, '2026-10-26'),
  ('claude-sonnet-5-5',  2, 10, 2.5,    4, 0.10, null, '2026-10-26'),
  ('claude-sonnet-5',    2, 10, 2.5,    4, 0.20, null, '2026-10-26'),
  ('claude-sonnet-4-6',  3, 15, 3.75,   6, 0.30, null, '2026-10-26'),
  ('claude-sonnet-4-5',  3, 15, 3.75,   6, 0.30, null, '2026-10-26'),
  ('claude-sonnet-4',    3, 15, 3.75,   6, 0.30, null, '2026-10-26'),
  ('claude-haiku-5-5',   0.10, 0.50, 0.125, 0.20, 0.01, null, '2026-10-26'),
  ('claude-haiku-4-5',   1,  5, 1.25,   2, 0.10, null, '2026-10-26')
on conflict (model) do update set
  input_per_mtok = excluded.input_per_mtok, output_per_mtok = excluded.output_per_mtok,
  cache_write_5m_per_mtok = excluded.cache_write_5m_per_mtok, cache_write_1h_per_mtok = excluded.cache_write_1h_per_mtok,
  cache_read_per_mtok = excluded.cache_read_per_mtok, fast_multiplier = excluded.fast_multiplier,
  priced_on = excluded.priced_on;

-- ===========================================================================
-- 2. Usage cumulé par entrée d'agent
-- ===========================================================================
create table if not exists public.agent_usage (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  time_entry_id uuid not null references public.time_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, -- l'agent, comme time_entries.user_id
  model text not null,
  effort text,                             -- low … max, null si la transcription ne le dit pas
  speed text not null default 'standard',  -- standard ou fast
  requests integer not null default 0,     -- appels à l'API
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  cache_write_5m_tokens bigint not null default 0,
  cache_write_1h_tokens bigint not null default 0,
  cache_read_tokens bigint not null default 0,
  cost_micros bigint,                      -- coût estimé au tarif de l'API, en millionièmes de dollar ; null : tarif inconnu
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint agent_usage_entry_key unique nulls not distinct (time_entry_id, model, effort, speed)
);
create index if not exists agent_usage_workspace_user_idx on public.agent_usage(workspace_id, user_id);
create trigger agent_usage_updated_at before update on public.agent_usage
  for each row execute function public.set_updated_at();

-- ===========================================================================
-- 3. RLS et droits : lecture comme l'entrée (le pilote et ceux qui l'encadrent), écriture par Flask seulement
-- ===========================================================================
alter table public.agent_usage enable row level security;
create policy agent_usage_select on public.agent_usage for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));

alter table public.ai_model_prices enable row level security;

grant select on public.agent_usage, public.ai_model_prices to powersync_role;
grant all on public.agent_usage, public.ai_model_prices to service_role;
-- Supabase pose des droits par défaut sur les nouvelles tables : on les retire explicitement.
revoke all on public.agent_usage, public.ai_model_prices from anon, authenticated;
grant select on public.agent_usage to authenticated;
