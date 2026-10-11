-- 0001 — Schéma cœur Clockifai (exécuté en tant que postgres).
--
-- Conventions :
--   * id uuid (générés côté client par PowerSync, ou gen_random_uuid() côté serveur)
--   * workspace_id sur chaque table métier (multi-tenant, RLS dans 0003)
--   * created_at / updated_at (updated_at posé par trigger, horloge serveur)
--   * deleted_at : soft delete → la ligne sort des sync streams et disparaît des clients
--   * timestamps en timestamptz ; PowerSync les transmet en texte ISO-8601

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Fonctions utilitaires
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- profiles : miroir public de auth.users
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null default '',
  avatar_url text,
  timezone text not null default 'Europe/Paris',
  locale text not null default 'fr',
  default_workspace_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- workspaces
-- ---------------------------------------------------------------------------
create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency text not null default 'EUR',
  week_start smallint not null default 1 check (week_start between 1 and 7), -- 1 = lundi (ISO)
  time_format text not null default '24h' check (time_format in ('24h', '12h')),
  rounding_minutes smallint not null default 0 check (rounding_minutes in (0, 5, 6, 10, 12, 15, 30, 60)),
  require_project boolean not null default false,
  require_description boolean not null default false,
  lock_entries_before date,
  auto_stop_after_hours smallint not null default 0, -- 0 = jamais
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger workspaces_updated_at before update on public.workspaces
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- workspace_members (display_name / email dénormalisés depuis profiles pour l'équipe)
-- ---------------------------------------------------------------------------
create table if not exists public.workspace_members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'manager', 'member')),
  status text not null default 'active' check (status in ('active', 'inactive')),
  display_name text not null default '',
  email text,
  hourly_rate_cents integer,
  cost_rate_cents integer,
  kiosk_pin_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (workspace_id, user_id)
);
create index if not exists workspace_members_user_idx on public.workspace_members(user_id);
create trigger workspace_members_updated_at before update on public.workspace_members
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- clients
-- ---------------------------------------------------------------------------
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  note text,
  currency_override text,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists clients_workspace_idx on public.clients(workspace_id);
create trigger clients_updated_at before update on public.clients
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  name text not null,
  color text not null default '#3B82F6',
  billable_default boolean not null default true,
  hourly_rate_cents integer,
  budget_hours integer,
  budget_amount_cents integer,
  is_public boolean not null default true,
  archived boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists projects_workspace_idx on public.projects(workspace_id);
create index if not exists projects_client_idx on public.projects(client_id);
create trigger projects_updated_at before update on public.projects
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tasks (sous-découpage d'un projet)
-- ---------------------------------------------------------------------------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null,
  estimate_seconds integer,
  status text not null default 'active' check (status in ('active', 'done')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists tasks_project_idx on public.tasks(project_id);
create trigger tasks_updated_at before update on public.tasks
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tags
-- ---------------------------------------------------------------------------
create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  color text not null default '#6B7280',
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists tags_workspace_idx on public.tags(workspace_id);
create trigger tags_updated_at before update on public.tags
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- time_entries : une entrée = un intervalle ; end_at NULL = chronomètre en cours
-- ---------------------------------------------------------------------------
create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  task_id uuid references public.tasks(id) on delete set null,
  description text not null default '',
  start_at timestamptz not null,
  end_at timestamptz,
  duration_seconds integer, -- maintenu par trigger (end_at - start_at) ; NULL tant que le timer tourne
  billable boolean not null default true,
  hourly_rate_cents integer, -- instantané du taux applicable au moment de la saisie
  locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (end_at is null or end_at >= start_at)
);
create index if not exists time_entries_user_start_idx on public.time_entries(user_id, start_at desc);
create index if not exists time_entries_workspace_start_idx on public.time_entries(workspace_id, start_at desc);
create index if not exists time_entries_project_idx on public.time_entries(project_id);
-- Un seul chronomètre en cours par utilisateur et par workspace.
create unique index if not exists time_entries_one_running_idx
  on public.time_entries(workspace_id, user_id)
  where end_at is null and deleted_at is null;

create or replace function public.time_entries_before_write()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  if new.end_at is null then
    new.duration_seconds = null;
  else
    new.duration_seconds = greatest(0, floor(extract(epoch from (new.end_at - new.start_at)))::integer);
  end if;
  return new;
end $$;
create trigger time_entries_before_write before insert or update on public.time_entries
  for each row execute function public.time_entries_before_write();

-- ---------------------------------------------------------------------------
-- time_entry_tags (workspace_id et user_id dénormalisés pour les streams et la RLS)
-- ---------------------------------------------------------------------------
create table if not exists public.time_entry_tags (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  time_entry_id uuid not null references public.time_entries(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (time_entry_id, tag_id)
);
create index if not exists time_entry_tags_entry_idx on public.time_entry_tags(time_entry_id);
create trigger time_entry_tags_updated_at before update on public.time_entry_tags
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Création d'un workspace : l'auteur devient owner (security definer : contourne la RLS)
-- ---------------------------------------------------------------------------
create or replace function public.workspaces_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p record;
begin
  if new.created_by is null then
    return new;
  end if;
  select display_name, email into p from public.profiles where id = new.created_by;
  insert into public.workspace_members (workspace_id, user_id, role, display_name, email)
  values (new.id, new.created_by, 'owner', coalesce(p.display_name, ''), p.email)
  on conflict (workspace_id, user_id) do nothing;
  return new;
end $$;
create trigger workspaces_after_insert after insert on public.workspaces
  for each row execute function public.workspaces_after_insert();

-- Propagation des changements de profil vers les memberships
create or replace function public.profiles_after_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.display_name is distinct from old.display_name or new.email is distinct from old.email then
    update public.workspace_members
       set display_name = new.display_name, email = new.email
     where user_id = new.id;
  end if;
  return new;
end $$;
create trigger profiles_after_update after update on public.profiles
  for each row execute function public.profiles_after_update();

-- ---------------------------------------------------------------------------
-- Nouvel utilisateur : profil + workspace personnel (déclenché depuis auth.users, cf. 0002)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ws_id uuid;
  dname text;
begin
  dname := coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, ''), '@', 1));
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, dname)
  on conflict (id) do nothing;

  insert into public.workspaces (name, created_by)
  values (coalesce(nullif(dname, ''), 'Mon espace') || ' — espace', new.id)
  returning id into ws_id;

  update public.profiles set default_workspace_id = ws_id where id = new.id and default_workspace_id is null;
  return new;
end $$;
