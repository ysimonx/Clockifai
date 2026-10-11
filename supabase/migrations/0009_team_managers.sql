-- 0009 — Chefs d'équipe : groupes, périmètre, saisie du temps pour autrui, approbations d'équipe.
-- (exécuté en tant que postgres) — plan : plans/03-saisie-pour-autrui.md
--
-- Un chef d'équipe n'est pas un rôle : c'est un membre à qui un admin confie des utilisateurs ou
-- des groupes. Le rôle `manager` garde sa portée « tout le workspace ».
-- Le périmètre effectif est matérialisé dans `team_scope` (une ligne par couple chef → collaborateur),
-- recalculé par trigger : la RLS, les Sync Streams et l'app le lisent tel quel.

-- ===========================================================================
-- 1. Paramètres et traçabilité
-- ===========================================================================
-- Qui peut saisir et modifier le temps des autres (Clockify : « Who can edit time for others »).
alter table public.workspaces add column if not exists time_for_others text not null default 'admins'
  check (time_for_others in ('admins', 'admins_and_team_managers'));
-- Qui approuve les absences d'une politique.
alter table public.time_off_policies add column if not exists approvers text not null default 'managers'
  check (approvers in ('managers', 'managers_and_team_managers'));
-- Auteur de la saisie et de la dernière modification (posés par trigger ; NULL = la personne elle-même).
alter table public.time_entries add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.time_entries add column if not exists updated_by uuid references auth.users(id) on delete set null;

-- Les colonnes ajoutées ne sont répliquées par PowerSync qu'au prochain changement de ligne.
update public.workspaces set time_for_others = time_for_others;
update public.time_off_policies set approvers = approvers;

-- ===========================================================================
-- 2. Groupes, affectations, périmètre
-- ===========================================================================
create table if not exists public.user_groups (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists user_groups_ws_idx on public.user_groups(workspace_id);
create trigger user_groups_updated_at before update on public.user_groups
  for each row execute function public.set_updated_at();

-- Lien n-n groupe ↔ utilisateur : suppression physique (comme time_entry_tags).
create table if not exists public.user_group_members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  group_id uuid not null references public.user_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, user_id)
);
create index if not exists user_group_members_ws_idx on public.user_group_members(workspace_id);
create trigger user_group_members_updated_at before update on public.user_group_members
  for each row execute function public.set_updated_at();

-- Un chef d'équipe encadre un utilisateur OU un groupe : suppression physique.
create table if not exists public.team_manager_assignments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  manager_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  group_id uuid references public.user_groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(user_id, group_id) = 1)
);
create index if not exists team_assignments_ws_idx on public.team_manager_assignments(workspace_id);
create unique index if not exists team_assignments_user_uq
  on public.team_manager_assignments(workspace_id, manager_id, user_id) where user_id is not null;
create unique index if not exists team_assignments_group_uq
  on public.team_manager_assignments(workspace_id, manager_id, group_id) where group_id is not null;
create trigger team_manager_assignments_updated_at before update on public.team_manager_assignments
  for each row execute function public.set_updated_at();

-- Périmètre effectif : table dérivée, écrite uniquement par refresh_team_scope().
create table if not exists public.team_scope (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  manager_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (workspace_id, manager_id, user_id)
);
create index if not exists team_scope_manager_idx on public.team_scope(manager_id);

-- Un groupe référencé doit appartenir au même workspace que la ligne.
create or replace function public.team_rows_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.group_id is not null and not exists (
    select 1 from public.user_groups g where g.id = new.group_id and g.workspace_id = new.workspace_id) then
    raise exception 'invalid_group: group does not belong to this workspace' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger user_group_members_check before insert or update on public.user_group_members
  for each row execute function public.team_rows_check();
create trigger team_manager_assignments_check before insert or update on public.team_manager_assignments
  for each row execute function public.team_rows_check();

-- Couples (chef, collaborateur) attendus : affectations directes + membres des groupes encadrés,
-- membres actifs uniquement, jamais soi-même (un chef n'approuve pas sa propre feuille).
create or replace function public.team_scope_wanted(wid uuid)
returns table (w_manager uuid, w_user uuid) language sql stable security definer set search_path = public as $$
  select distinct a.manager_id, coalesce(a.user_id, gm.user_id)
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
$$;

-- Recalcul différentiel : les lignes inchangées gardent leur id (pas de resynchronisation inutile).
create or replace function public.refresh_team_scope(wid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.workspaces where id = wid) then
    return; -- workspace en cours de suppression (cascade)
  end if;
  -- Un recalcul à la fois par workspace : deux modifications simultanées (deux admins, deux appareils)
  -- ne laissent pas de ligne périmée. Chaque requête suivante voit ce que l'autre a validé.
  perform pg_advisory_xact_lock(hashtextextended('team_scope:' || wid::text, 0));
  delete from public.team_scope s
   where s.workspace_id = wid
     and not exists (select 1 from public.team_scope_wanted(wid) w
                      where w.w_manager = s.manager_id and w.w_user = s.user_id);
  insert into public.team_scope (workspace_id, manager_id, user_id)
  select wid, w.w_manager, w.w_user from public.team_scope_wanted(wid) w
  on conflict (workspace_id, manager_id, user_id) do nothing;
end $$;
revoke all on function public.team_scope_wanted(uuid), public.refresh_team_scope(uuid) from public;

create or replace function public.team_scope_on_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_team_scope(old.workspace_id);
  else
    perform public.refresh_team_scope(new.workspace_id);
    if tg_op = 'UPDATE' and new.workspace_id is distinct from old.workspace_id then
      perform public.refresh_team_scope(old.workspace_id);
    end if;
  end if;
  return null;
end $$;
create trigger team_manager_assignments_scope after insert or update or delete on public.team_manager_assignments
  for each row execute function public.team_scope_on_change();
create trigger user_group_members_scope after insert or update or delete on public.user_group_members
  for each row execute function public.team_scope_on_change();
create trigger user_groups_scope after update of deleted_at, workspace_id or delete on public.user_groups
  for each row execute function public.team_scope_on_change();
create trigger workspace_members_scope after insert or update of status, deleted_at, user_id, workspace_id or delete
  on public.workspace_members
  for each row execute function public.team_scope_on_change();

-- ===========================================================================
-- 3. Fonctions d'aide aux droits
-- ===========================================================================
-- Vrai si l'utilisateur connecté encadre `uid` : manager+ (tout le workspace) ou chef d'équipe.
create or replace function public.manages(wid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_manager(wid)
      or exists (select 1 from public.team_scope s
                  where s.workspace_id = wid and s.manager_id = auth.uid() and s.user_id = uid)
$$;

-- Vrai si l'utilisateur connecté peut saisir ou modifier le temps de `uid` (autre que lui-même).
create or replace function public.can_edit_others_time(wid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin(wid)
      or (exists (select 1 from public.workspaces w
                   where w.id = wid and w.time_for_others = 'admins_and_team_managers')
          and public.manages(wid, uid)
          and exists (select 1 from public.workspace_members m
                       where m.workspace_id = wid and m.user_id = uid and m.status = 'active' and m.deleted_at is null))
$$;

-- Vrai si l'utilisateur connecté peut approuver ou refuser une absence de `uid` sur la politique `pid`.
create or replace function public.can_decide_time_off(wid uuid, uid uuid, pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_manager(wid)
      or (exists (select 1 from public.time_off_policies p
                   where p.id = pid and p.approvers = 'managers_and_team_managers')
          and exists (select 1 from public.team_scope s
                       where s.workspace_id = wid and s.manager_id = auth.uid() and s.user_id = uid))
$$;

revoke all on function public.manages(uuid, uuid), public.can_edit_others_time(uuid, uuid),
  public.can_decide_time_off(uuid, uuid, uuid) from public;
grant execute on function public.manages(uuid, uuid), public.can_edit_others_time(uuid, uuid),
  public.can_decide_time_off(uuid, uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. RLS des nouvelles tables
-- ===========================================================================
alter table public.user_groups enable row level security;
create policy user_groups_select on public.user_groups for select to authenticated using (public.is_member(workspace_id));
create policy user_groups_write on public.user_groups for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

alter table public.user_group_members enable row level security;
create policy user_group_members_select on public.user_group_members for select to authenticated
  using (public.is_member(workspace_id));
create policy user_group_members_write on public.user_group_members for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

alter table public.team_manager_assignments enable row level security;
create policy team_assignments_select on public.team_manager_assignments for select to authenticated
  using (public.is_member(workspace_id));
create policy team_assignments_write on public.team_manager_assignments for all to authenticated
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

alter table public.team_scope enable row level security;
create policy team_scope_select on public.team_scope for select to authenticated using (public.is_member(workspace_id));

-- ===========================================================================
-- 5. Entrées de temps : lecture par le chef d'équipe, écriture selon le paramètre du workspace
-- ===========================================================================
drop policy if exists time_entries_select on public.time_entries;
create policy time_entries_select on public.time_entries for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));
drop policy if exists time_entries_insert on public.time_entries;
create policy time_entries_insert on public.time_entries for insert to authenticated
  with check ((user_id = auth.uid() and public.is_member(workspace_id)) or public.can_edit_others_time(workspace_id, user_id));
drop policy if exists time_entries_update on public.time_entries;
create policy time_entries_update on public.time_entries for update to authenticated
  using (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id))
  with check (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id));
drop policy if exists time_entries_delete on public.time_entries;
create policy time_entries_delete on public.time_entries for delete to authenticated
  using (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id));

drop policy if exists time_entry_tags_select on public.time_entry_tags;
create policy time_entry_tags_select on public.time_entry_tags for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));
drop policy if exists time_entry_tags_write on public.time_entry_tags;
create policy time_entry_tags_write on public.time_entry_tags for all to authenticated
  using (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id))
  with check (user_id = auth.uid() or public.can_edit_others_time(workspace_id, user_id));

-- Traçabilité : created_by / updated_by viennent du JWT, jamais du client.
-- Sans JWT (kiosque, intégrations, cascades « on delete set null » à la suppression d'un compte),
-- les valeurs écrites sont conservées telles quelles.
create or replace function public.time_entries_before_write()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  if new.end_at is null then
    new.duration_seconds = null;
  else
    new.duration_seconds = greatest(0, floor(extract(epoch from (new.end_at - new.start_at)))::integer);
  end if;
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.created_by := auth.uid();
    else
      new.created_by := old.created_by;  -- l'auteur d'une saisie ne change jamais
    end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end $$;

-- Garde (remplace celle de 0007) : + pas de chronomètre démarré pour quelqu'un d'autre, admins compris.
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

-- ===========================================================================
-- 6. Approbations : feuilles de temps du périmètre, absences selon la politique
-- ===========================================================================
drop policy if exists submissions_select on public.timesheet_submissions;
create policy submissions_select on public.timesheet_submissions for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));
drop policy if exists submissions_update on public.timesheet_submissions;
create policy submissions_update on public.timesheet_submissions for update to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id))
  with check (user_id = auth.uid() or public.manages(workspace_id, user_id));

create or replace function public.timesheet_submissions_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  manager boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  -- manager+ : tout le workspace ; chef d'équipe : son périmètre (dont il est lui-même exclu).
  manager := public.manages(new.workspace_id, new.user_id);
  if tg_op = 'INSERT' then
    if new.status not in ('submitted') and not manager then
      raise exception 'invalid_status: a submission starts as submitted' using errcode = '42501';
    end if;
  else
    if new.user_id <> old.user_id or new.workspace_id <> old.workspace_id
       or new.period_start <> old.period_start or new.period_end <> old.period_end then
      raise exception 'immutable: period and owner cannot change' using errcode = '42501';
    end if;
    if not manager then
      if old.status = 'approved' then
        raise exception 'approved: an approved timesheet can only be reopened by a manager' using errcode = '42501';
      end if;
      if new.status not in ('submitted', 'withdrawn') then
        raise exception 'insufficient_privilege: only managers approve or reject' using errcode = '42501';
      end if;
    end if;
  end if;
  if new.status in ('approved', 'rejected') and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end $$;

drop policy if exists allowances_select on public.time_off_allowances;
create policy allowances_select on public.time_off_allowances for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));

drop policy if exists requests_select on public.time_off_requests;
create policy requests_select on public.time_off_requests for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));
drop policy if exists requests_update on public.time_off_requests;
create policy requests_update on public.time_off_requests for update to authenticated
  using (user_id = auth.uid() or public.can_decide_time_off(workspace_id, user_id, policy_id))
  with check (user_id = auth.uid() or public.can_decide_time_off(workspace_id, user_id, policy_id));

create or replace function public.time_off_requests_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  manager boolean;
  needs_approval boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  manager := public.can_decide_time_off(new.workspace_id, new.user_id, new.policy_id);
  select requires_approval into needs_approval from public.time_off_policies where id = new.policy_id;
  if tg_op = 'INSERT' then
    if not manager and new.status <> 'pending' then
      raise exception 'invalid_status: a request starts as pending' using errcode = '42501';
    end if;
    if not coalesce(needs_approval, true) and new.status = 'pending' then
      new.status := 'approved';   -- politique sans approbation
    end if;
  else
    if new.user_id <> old.user_id or new.workspace_id <> old.workspace_id then
      raise exception 'immutable: owner cannot change' using errcode = '42501';
    end if;
    if not manager then
      -- Le demandeur peut modifier une demande en attente, ou annuler.
      if new.status = 'cancelled' then
        null;
      elsif old.status <> 'pending' or new.status <> 'pending' then
        raise exception 'insufficient_privilege: only managers approve or reject' using errcode = '42501';
      end if;
    end if;
  end if;
  if new.status in ('approved', 'rejected') and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end $$;

-- ===========================================================================
-- 7. Droits de lecture pour la réplication PowerSync (tables créées dans cette migration)
-- ===========================================================================
grant select on public.user_groups, public.user_group_members, public.team_manager_assignments, public.team_scope
  to powersync_role;
grant all on public.user_groups, public.user_group_members, public.team_manager_assignments
  to authenticated, service_role;
grant all on public.team_scope to service_role;
-- Supabase pose des droits par défaut sur les nouvelles tables : on les retire explicitement.
revoke all on public.user_groups, public.user_group_members, public.team_manager_assignments, public.team_scope from anon;
revoke all on public.team_scope from authenticated;
grant select on public.team_scope to authenticated;
