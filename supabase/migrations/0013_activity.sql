-- 0013 — Suivi de Claude Code : agents membres de l'équipe (exécuté en tant que postgres).
-- Plan : plans/10-suivi-claude-code.md (D2, D7.8, D14, D15, D16, §4).
--
-- Le temps de Claude est celui d'un membre « agent », un par pilote. Ses entrées sont des time_entries
-- ordinaires, écrites par le serveur seulement (agent_entry_write). Le pilote les lit (team_scope) et les
-- corrige (pilots_agent), sans pouvoir en créer.

-- ===========================================================================
-- 1. Colonnes
-- ===========================================================================
alter table public.workspace_members
  add column if not exists kind text not null default 'human' check (kind in ('human', 'agent')),
  add column if not exists agent_owner_id uuid references auth.users(id) on delete cascade;
alter table public.workspace_members
  add constraint workspace_members_agent_owner_check check ((kind = 'agent') = (agent_owner_id is not null)),
  add constraint workspace_members_agent_role_check check (kind = 'human' or role = 'member');
create unique index if not exists workspace_members_agent_uq
  on public.workspace_members(workspace_id, agent_owner_id) where kind = 'agent' and deleted_at is null;

alter table public.workspaces add column if not exists agent_billing text not null default 'like_humans'
  check (agent_billing in ('like_humans', 'never'));
alter table public.projects add column if not exists agent_billable boolean; -- nul : comme le workspace (D16)

-- Origine d'une entrée. Nul = 'app' : pas de mise à jour des entrées existantes, donc pas de resynchronisation.
alter table public.time_entries add column if not exists source text
  check (source in ('app', 'kiosk', 'activity', 'agent'));

-- Les colonnes non nulles ne sont répliquées qu'au prochain changement de ligne (petites tables).
update public.workspace_members set kind = kind;
update public.workspaces set agent_billing = agent_billing;

-- ===========================================================================
-- 2. Dépôts, commits vus en local, règles de rattachement
-- ===========================================================================
create table if not exists public.code_repositories (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  remote_key text not null,      -- URL distante normalisée (hôte/chemin), ou local:<dossier>
  name text not null,
  project_id uuid references public.projects(id) on delete set null, -- règle de workspace (D9)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (workspace_id, remote_key)
);
create trigger code_repositories_updated_at before update on public.code_repositories
  for each row execute function public.set_updated_at();

create table if not exists public.code_commits (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  repository_id uuid not null references public.code_repositories(id) on delete cascade,
  sha text not null,
  branch text,
  subject text not null default '',
  author_email text,
  author_user_id uuid references auth.users(id) on delete set null,
  authored_at timestamptz,
  seen_locally_at timestamptz,
  session_id text,
  window_id text,
  time_entry_id uuid references public.time_entries(id) on delete set null, -- entrée d'agent de la session
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (repository_id, sha)
);
create index if not exists code_commits_entry_idx on public.code_commits(time_entry_id);
create trigger code_commits_updated_at before update on public.code_commits
  for each row execute function public.set_updated_at();

-- Règles personnelles : un dépôt (remote_key) ou un préfixe de chemin mène à un projet (D9).
-- Créées par Flask, qui réattribue les entrées concernées ; le client ne fait que les retirer.
create table if not exists public.activity_rules (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  match_kind text not null check (match_kind in ('repo', 'path_prefix')),
  pattern text not null,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists activity_rules_user_idx on public.activity_rules(workspace_id, user_id);
create trigger activity_rules_updated_at before update on public.activity_rules
  for each row execute function public.set_updated_at();

create or replace function public.activity_rules_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.workspace_id is distinct from old.workspace_id or new.user_id is distinct from old.user_id
     or new.match_kind is distinct from old.match_kind or new.pattern is distinct from old.pattern
     or new.project_id is distinct from old.project_id or new.task_id is distinct from old.task_id then
    raise exception 'insufficient_privilege: rules are created by the server; only their removal is allowed'
      using errcode = '42501';
  end if;
  return new;
end $$;
create trigger activity_rules_guard before update on public.activity_rules
  for each row execute function public.activity_rules_guard();

-- ===========================================================================
-- 3. Fonctions d'aide
-- ===========================================================================
-- Vrai si `uid` est un agent du workspace (actif ou non : un agent le reste).
create or replace function public.is_agent_member(wid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.workspace_members m
                  where m.workspace_id = wid and m.user_id = uid and m.kind = 'agent')
$$;

-- Vrai si l'utilisateur connecté est le pilote de l'agent `uid` (D15).
create or replace function public.pilots_agent(wid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member(wid)
     and exists (select 1 from public.workspace_members m
                  where m.workspace_id = wid and m.user_id = uid and m.kind = 'agent'
                    and m.agent_owner_id = auth.uid() and m.deleted_at is null)
$$;

revoke all on function public.is_agent_member(uuid, uuid), public.pilots_agent(uuid, uuid) from public;
grant execute on function public.is_agent_member(uuid, uuid), public.pilots_agent(uuid, uuid)
  to authenticated, service_role;

-- ===========================================================================
-- 4. Membres : agents créés par le serveur seulement, et qui suivent leur pilote (D14)
-- ===========================================================================
-- Remplace la garde de 0003, désormais aussi à l'insertion.
create or replace function public.workspace_members_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new; -- service_role / triggers internes
  end if;
  if tg_op = 'INSERT' then
    if new.kind = 'agent' or new.agent_owner_id is not null then
      raise exception 'insufficient_privilege: agents are created by the server only' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.kind is distinct from old.kind or new.agent_owner_id is distinct from old.agent_owner_id then
    raise exception 'insufficient_privilege: the kind of a member cannot change' using errcode = '42501';
  end if;
  if not public.is_admin(new.workspace_id) then
    if new.role is distinct from old.role
       or new.status is distinct from old.status
       or new.hourly_rate_cents is distinct from old.hourly_rate_cents
       or new.cost_rate_cents is distinct from old.cost_rate_cents
       or new.workspace_id is distinct from old.workspace_id
       or new.user_id is distinct from old.user_id
       or new.deleted_at is distinct from old.deleted_at then
      raise exception 'insufficient_privilege: only admins can change role, status, rates or membership'
        using errcode = '42501';
    end if;
  end if;
  -- Le dernier owner ne peut pas être rétrogradé.
  if old.role = 'owner' and new.role <> 'owner' then
    if not exists (select 1 from public.workspace_members m
                    where m.workspace_id = old.workspace_id and m.role = 'owner' and m.id <> old.id
                      and m.status = 'active' and m.deleted_at is null) then
      raise exception 'invalid_operation: a workspace needs at least one owner' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists workspace_members_guard on public.workspace_members;
create trigger workspace_members_guard before insert or update on public.workspace_members
  for each row execute function public.workspace_members_guard();

-- Pilote désactivé ou retiré → ses agents aussi. Jamais l'inverse : réactiver un agent reste un geste d'admin.
create or replace function public.workspace_members_agents_follow()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind <> 'human' then
    return null;
  end if;
  if new.deleted_at is not null and old.deleted_at is null then
    update public.workspace_members set deleted_at = new.deleted_at
     where workspace_id = new.workspace_id and agent_owner_id = new.user_id and kind = 'agent'
       and deleted_at is null;
  elsif new.status = 'inactive' and old.status is distinct from 'inactive' then
    update public.workspace_members set status = 'inactive'
     where workspace_id = new.workspace_id and agent_owner_id = new.user_id and kind = 'agent'
       and status = 'active';
  end if;
  return null;
end $$;
drop trigger if exists workspace_members_agents_follow on public.workspace_members;
create trigger workspace_members_agents_follow after update of status, deleted_at on public.workspace_members
  for each row execute function public.workspace_members_agents_follow();

-- Compte technique d'un agent : profil, mais pas d'espace personnel (remplace 0006).
-- GoTrue (admin/users) n'écrit les app_metadata qu'après l'insertion : le trigger lit donc aussi la marque
-- dans les user_metadata, posées dès l'insertion. Un utilisateur qui s'y marquerait « agent » n'y gagne que
-- l'absence d'espace personnel : ce qui fait un agent, c'est workspace_members.kind, posé par le serveur.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ws_id uuid;
  dname text;
begin
  dname := coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, ''), '@', 1));
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, dname)
  on conflict (id) do nothing;

  if 'agent' in (coalesce(new.raw_app_meta_data ->> 'kind', ''), coalesce(new.raw_user_meta_data ->> 'kind', '')) then
    return new;
  end if;

  insert into public.workspaces (name, created_by)
  values ('Espace de ' || coalesce(nullif(dname, ''), 'moi'), new.id)
  returning id into ws_id;

  update public.profiles set default_workspace_id = ws_id where id = new.id and default_workspace_id is null;
  return new;
end $$;

-- ===========================================================================
-- 5. Périmètre : le pilote et les chefs du pilote voient l'agent (D15, remplace 0009)
-- ===========================================================================
create or replace function public.team_scope_wanted(wid uuid)
returns table (w_manager uuid, w_user uuid) language sql stable security definer set search_path = public as $$
  with base as (
    select distinct a.manager_id as w_manager, coalesce(a.user_id, gm.user_id) as w_user
      from public.team_manager_assignments a
      left join public.user_groups g on g.id = a.group_id and g.deleted_at is null
      left join public.user_group_members gm on gm.group_id = g.id
     where a.workspace_id = wid
       and coalesce(a.user_id, gm.user_id) is not null
       and coalesce(a.user_id, gm.user_id) <> a.manager_id
       and exists (select 1 from public.workspace_members m
                    where m.workspace_id = wid and m.user_id = a.manager_id and m.status = 'active' and m.deleted_at is null)
       and exists (select 1 from public.workspace_members m
                    where m.workspace_id = wid and m.user_id = coalesce(a.user_id, gm.user_id)
                      and m.status = 'active' and m.deleted_at is null)
  ),
  agents as (
    select a.agent_owner_id as pilot, a.user_id as agent
      from public.workspace_members a
     where a.workspace_id = wid and a.kind = 'agent' and a.status = 'active' and a.deleted_at is null
       and exists (select 1 from public.workspace_members p
                    where p.workspace_id = wid and p.user_id = a.agent_owner_id
                      and p.status = 'active' and p.deleted_at is null)
  )
  select w_manager, w_user from base
  union
  select pilot, agent from agents
  union
  select b.w_manager, ag.agent from base b join agents ag on ag.pilot = b.w_user
$$;
revoke all on function public.team_scope_wanted(uuid) from public;

-- Recalcul pour les workspaces qui auraient déjà des agents (aucun en principe à ce stade).
select public.refresh_team_scope(id) from public.workspaces;

-- ===========================================================================
-- 6. Entrées de temps : le pilote corrige, personne ne crée de temps d'agent (D15)
-- ===========================================================================
drop policy if exists time_entries_update on public.time_entries;
create policy time_entries_update on public.time_entries for update to authenticated
  using (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id)
         or public.pilots_agent(workspace_id, user_id))
  with check (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id)
              or public.pilots_agent(workspace_id, user_id));
drop policy if exists time_entries_delete on public.time_entries;
create policy time_entries_delete on public.time_entries for delete to authenticated
  using (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id)
         or public.pilots_agent(workspace_id, user_id));
drop policy if exists time_entry_tags_write on public.time_entry_tags;
create policy time_entry_tags_write on public.time_entry_tags for all to authenticated
  using (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id)
         or public.pilots_agent(workspace_id, user_id))
  with check (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id)
              or public.pilots_agent(workspace_id, user_id));

-- Garde (remplace 0009) : + personne et workspace immuables, pas de temps d'agent saisi, source posée une fois.
create or replace function public.time_entries_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lock_date date;
  wid uuid;
  uid uuid;
  result public.time_entries;
begin
  if tg_op = 'DELETE' then
    result := old; wid := old.workspace_id; uid := old.user_id;
  else
    result := new; wid := new.workspace_id; uid := new.user_id;
  end if;

  if auth.uid() is null or public.guard_bypassed() then
    return result;
  end if;

  if tg_op = 'UPDATE' and (new.user_id is distinct from old.user_id or new.workspace_id is distinct from old.workspace_id) then
    raise exception 'invalid_operation: an entry cannot move to another person or workspace' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and public.is_agent_member(new.workspace_id, new.user_id) then
    raise exception 'insufficient_privilege: agent time is recorded by the server only' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and new.source is not null and new.source not in ('app', 'activity') then
    raise exception 'insufficient_privilege: source % is set by the server only', new.source using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.source is distinct from old.source then
    raise exception 'insufficient_privilege: the source of an entry cannot change' using errcode = '42501';
  end if;

  if tg_op in ('INSERT', 'UPDATE') and new.user_id <> auth.uid()
     and new.end_at is null and new.deleted_at is null
     and (tg_op = 'INSERT' or old.end_at is not null) then
    raise exception 'timer_for_others: a timer cannot be started for someone else' using errcode = '42501';
  end if;

  if public.is_admin(wid) then
    return result;
  end if;

  if tg_op in ('UPDATE', 'DELETE') and old.locked then
    raise exception 'locked_entry: this time entry is locked' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.locked is distinct from old.locked then
    raise exception 'insufficient_privilege: only admins can lock entries' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and new.locked then
    raise exception 'insufficient_privilege: only admins can lock entries' using errcode = '42501';
  end if;

  select lock_entries_before into lock_date from public.workspaces where id = wid;
  if lock_date is not null then
    if tg_op in ('UPDATE', 'DELETE') and public.user_local_date(old.start_at, old.user_id) < lock_date then
      raise exception 'locked_period: entries before % are locked', lock_date using errcode = '42501';
    end if;
    if tg_op in ('INSERT', 'UPDATE') and public.user_local_date(new.start_at, new.user_id) < lock_date then
      raise exception 'locked_period: entries before % are locked', lock_date using errcode = '42501';
    end if;
  end if;

  -- Pas d'ajout ni de déplacement d'entrée dans une période déjà approuvée (de la personne visée).
  if tg_op in ('INSERT', 'UPDATE') and exists (
    select 1 from public.timesheet_submissions s
     where s.workspace_id = wid and s.user_id = uid and s.status = 'approved' and s.deleted_at is null
       and public.user_local_date(new.start_at, uid) between s.period_start and s.period_end) then
    raise exception 'approved_period: this period has been approved' using errcode = '42501';
  end if;

  -- Une entrée facturée (facture non annulée) n'est plus modifiable.
  if tg_op in ('UPDATE', 'DELETE') and exists (
    select 1 from public.invoice_entries ie join public.invoices i on i.id = ie.invoice_id
     where ie.time_entry_id = old.id and i.status <> 'void' and i.deleted_at is null) then
    raise exception 'invoiced_entry: this entry has been invoiced' using errcode = '42501';
  end if;

  return result;
end $$;

-- Les chronomètres d'un agent ne sont pas limités (D2) : une session, un chronomètre (remplace 0011).
create or replace function public.time_entries_running_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lim integer;
  kept integer := 0;          -- chronomètres qui continuent de tourner (le nouveau compris s'il est classé)
  new_kept boolean := false;
  oldest_kept timestamptz;    -- début du plus ancien chronomètre existant qui continue de tourner
  other record;
begin
  if new.end_at is not null or new.deleted_at is not null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.end_at is null and old.deleted_at is null then
    return new; -- déjà en cours, rien ne change
  end if;
  if public.is_agent_member(new.workspace_id, new.user_id) then
    return new;
  end if;

  select max_running_timers into lim from public.workspaces where id = new.workspace_id;
  lim := coalesce(lim, 1);
  if lim = 0 then
    return new; -- illimité
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.workspace_id::text || ':' || new.user_id::text, 0));

  -- Classement du plus récent au plus ancien ; le nouveau y prend sa place selon son début.
  for other in
    select id, start_at from public.time_entries
     where workspace_id = new.workspace_id and user_id = new.user_id
       and end_at is null and deleted_at is null and id <> new.id
     order by start_at desc, id desc
     for update
  loop
    if not new_kept and kept < lim and new.start_at >= other.start_at then
      new_kept := true;
      kept := kept + 1;
    end if;
    if kept < lim then
      kept := kept + 1;
      oldest_kept := other.start_at;
    elsif new_kept then
      update public.time_entries set end_at = new.start_at where id = other.id;
    end if;
  end loop;

  if not new_kept and kept >= lim then
    new.end_at := oldest_kept;
    new.duration_seconds := greatest(0, floor(extract(epoch from (new.end_at - new.start_at)))::integer);
  end if;
  return new;
end $$;

-- ===========================================================================
-- 7. Écriture d'une entrée d'agent par le serveur (D7.8)
-- ===========================================================================
-- Flask écrit sans JWT, donc sans garde : cette fonction reprend les contrôles de time_entries_guard.
-- Renvoie 'ok', ou la raison du refus (rien n'est écrit) : not_agent, deleted, locked, invoiced,
-- locked_period, approved_period.
create or replace function public.agent_entry_write(
  p_id uuid, p_workspace_id uuid, p_agent_id uuid, p_pilot_id uuid,
  p_start_at timestamptz, p_end_at timestamptz,
  p_project_id uuid, p_task_id uuid, p_description text,
  p_billable boolean, p_hourly_rate_cents integer)
returns text language plpgsql security definer set search_path = public as $$
declare
  cur public.time_entries;
  existed boolean;
  lock_date date;
  starts date[];
begin
  if not public.is_agent_member(p_workspace_id, p_agent_id) then
    return 'not_agent';
  end if;
  select * into cur from public.time_entries where id = p_id for update;
  existed := found;
  if existed then
    if cur.workspace_id <> p_workspace_id or cur.user_id <> p_agent_id then
      return 'not_agent';
    end if;
    if cur.deleted_at is not null then
      return 'deleted';
    end if;
    if cur.locked then
      return 'locked';
    end if;
    if exists (select 1 from public.invoice_entries ie join public.invoices i on i.id = ie.invoice_id
                where ie.time_entry_id = p_id and i.status <> 'void' and i.deleted_at is null) then
      return 'invoiced';
    end if;
  end if;

  starts := array[public.user_local_date(p_start_at, p_agent_id)];
  if existed then
    starts := starts || public.user_local_date(cur.start_at, p_agent_id);
  end if;
  select lock_entries_before into lock_date from public.workspaces where id = p_workspace_id;
  if lock_date is not null and exists (select 1 from unnest(starts) d where d < lock_date) then
    return 'locked_period';
  end if;
  if exists (select 1 from public.timesheet_submissions s, unnest(starts) d
              where s.workspace_id = p_workspace_id and s.user_id = p_agent_id and s.status = 'approved'
                and s.deleted_at is null and d between s.period_start and s.period_end) then
    return 'approved_period';
  end if;

  if existed then
    update public.time_entries
       set start_at = p_start_at, end_at = p_end_at, project_id = p_project_id, task_id = p_task_id,
           description = coalesce(p_description, ''), billable = p_billable, hourly_rate_cents = p_hourly_rate_cents
     where id = p_id;
  else
    insert into public.time_entries (id, workspace_id, user_id, project_id, task_id, description, start_at, end_at,
                                     billable, hourly_rate_cents, source, created_by)
    values (p_id, p_workspace_id, p_agent_id, p_project_id, p_task_id, coalesce(p_description, ''), p_start_at, p_end_at,
            p_billable, p_hourly_rate_cents, 'agent', p_pilot_id);
  end if;
  return 'ok';
end $$;
revoke all on function public.agent_entry_write(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid, text,
  boolean, integer) from public, anon, authenticated;
grant execute on function public.agent_entry_write(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid, text,
  boolean, integer) to service_role;

-- ===========================================================================
-- 8. RLS et droits des nouvelles tables
-- ===========================================================================
alter table public.code_repositories enable row level security;
create policy code_repositories_select on public.code_repositories for select to authenticated
  using (public.is_member(workspace_id));

alter table public.code_commits enable row level security;
create policy code_commits_select on public.code_commits for select to authenticated
  using (public.is_member(workspace_id));

alter table public.activity_rules enable row level security;
create policy activity_rules_select on public.activity_rules for select to authenticated
  using (user_id = auth.uid() and public.is_member(workspace_id));
create policy activity_rules_update on public.activity_rules for update to authenticated
  using (user_id = auth.uid() and public.is_member(workspace_id))
  with check (user_id = auth.uid() and public.is_member(workspace_id));

grant select on public.code_repositories, public.code_commits, public.activity_rules to powersync_role;
grant all on public.code_repositories, public.code_commits, public.activity_rules to service_role;
-- Supabase pose des droits par défaut sur les nouvelles tables : on les retire explicitement.
revoke all on public.code_repositories, public.code_commits, public.activity_rules from anon, authenticated;
grant select on public.code_repositories, public.code_commits to authenticated;
grant select, update on public.activity_rules to authenticated;
