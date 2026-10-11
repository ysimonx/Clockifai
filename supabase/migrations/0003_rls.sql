-- 0003 — Row Level Security (exécuté en tant que postgres).
--
-- Rôles Supabase : anon (non connecté), authenticated (JWT utilisateur), service_role (Flask).
-- Les fonctions d'aide sont SECURITY DEFINER pour éviter la récursion RLS sur workspace_members.

-- ---------------------------------------------------------------------------
-- Fonctions d'aide
-- ---------------------------------------------------------------------------
create or replace function public.member_role(wid uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from public.workspace_members
   where workspace_id = wid and user_id = auth.uid() and status = 'active' and deleted_at is null
   limit 1
$$;

create or replace function public.is_member(wid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.member_role(wid) is not null
$$;

create or replace function public.is_manager(wid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.member_role(wid) in ('owner', 'admin', 'manager')
$$;

create or replace function public.is_admin(wid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.member_role(wid) in ('owner', 'admin')
$$;

revoke all on function public.member_role(uuid), public.is_member(uuid), public.is_manager(uuid), public.is_admin(uuid) from public;
grant execute on function public.member_role(uuid), public.is_member(uuid), public.is_manager(uuid), public.is_admin(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Droits de base (Supabase les pose aussi par défaut ; explicite = robuste)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated, service_role;
grant all on all sequences in schema public to authenticated, service_role;
revoke all on all tables in schema public from anon;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- workspaces
-- ---------------------------------------------------------------------------
alter table public.workspaces enable row level security;
drop policy if exists workspaces_select on public.workspaces;
create policy workspaces_select on public.workspaces for select to authenticated using (public.is_member(id));
drop policy if exists workspaces_insert on public.workspaces;
create policy workspaces_insert on public.workspaces for insert to authenticated with check (created_by = auth.uid());
drop policy if exists workspaces_update on public.workspaces;
create policy workspaces_update on public.workspaces for update to authenticated using (public.is_admin(id)) with check (public.is_admin(id));
drop policy if exists workspaces_delete on public.workspaces;
create policy workspaces_delete on public.workspaces for delete to authenticated using (public.member_role(id) = 'owner');

-- ---------------------------------------------------------------------------
-- workspace_members
-- ---------------------------------------------------------------------------
alter table public.workspace_members enable row level security;
drop policy if exists members_select on public.workspace_members;
create policy members_select on public.workspace_members for select to authenticated using (public.is_member(workspace_id));
drop policy if exists members_insert on public.workspace_members;
create policy members_insert on public.workspace_members for insert to authenticated with check (public.is_admin(workspace_id));
drop policy if exists members_update on public.workspace_members;
create policy members_update on public.workspace_members for update to authenticated
  using (public.is_admin(workspace_id) or user_id = auth.uid())
  with check (public.is_admin(workspace_id) or user_id = auth.uid());
drop policy if exists members_delete on public.workspace_members;
create policy members_delete on public.workspace_members for delete to authenticated using (public.is_admin(workspace_id));

-- Un membre non-admin ne peut modifier sur sa propre ligne que des champs anodins (PIN kiosque, nom affiché).
create or replace function public.workspace_members_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new; -- service_role / triggers internes
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
create trigger workspace_members_guard before update on public.workspace_members
  for each row execute function public.workspace_members_guard();

-- ---------------------------------------------------------------------------
-- clients / projects / tasks / tags : lecture membres, écriture admin (projets : manager aussi)
-- ---------------------------------------------------------------------------
alter table public.clients enable row level security;
drop policy if exists clients_select on public.clients;
create policy clients_select on public.clients for select to authenticated using (public.is_member(workspace_id));
drop policy if exists clients_write on public.clients;
create policy clients_write on public.clients for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

alter table public.projects enable row level security;
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to authenticated using (public.is_member(workspace_id));
drop policy if exists projects_write on public.projects;
create policy projects_write on public.projects for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

alter table public.tasks enable row level security;
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select to authenticated using (public.is_member(workspace_id));
drop policy if exists tasks_write on public.tasks;
create policy tasks_write on public.tasks for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

alter table public.tags enable row level security;
drop policy if exists tags_select on public.tags;
create policy tags_select on public.tags for select to authenticated using (public.is_member(workspace_id));
drop policy if exists tags_write on public.tags;
create policy tags_write on public.tags for all to authenticated
  using (public.is_manager(workspace_id)) with check (public.is_manager(workspace_id));

-- ---------------------------------------------------------------------------
-- time_entries : chacun gère les siennes ; manager+ voit celles de l'équipe ; admin+ modifie tout
-- ---------------------------------------------------------------------------
alter table public.time_entries enable row level security;
drop policy if exists time_entries_select on public.time_entries;
create policy time_entries_select on public.time_entries for select to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id));
drop policy if exists time_entries_insert on public.time_entries;
create policy time_entries_insert on public.time_entries for insert to authenticated
  with check ((user_id = auth.uid() and public.is_member(workspace_id)) or public.is_admin(workspace_id));
drop policy if exists time_entries_update on public.time_entries;
create policy time_entries_update on public.time_entries for update to authenticated
  using (user_id = auth.uid() or public.is_admin(workspace_id))
  with check (user_id = auth.uid() or public.is_admin(workspace_id));
drop policy if exists time_entries_delete on public.time_entries;
create policy time_entries_delete on public.time_entries for delete to authenticated
  using (user_id = auth.uid() or public.is_admin(workspace_id));

-- Verrouillage : une entrée verrouillée, ou antérieure à lock_entries_before, n'est modifiable que par un admin.
create or replace function public.time_entries_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  lock_date date;
  wid uuid;
  result public.time_entries;
begin
  if tg_op = 'DELETE' then
    result := old; wid := old.workspace_id;
  else
    result := new; wid := new.workspace_id;
  end if;

  -- service_role / triggers internes / admins : pas de restriction
  if auth.uid() is null or public.is_admin(wid) then
    return result;
  end if;

  if tg_op in ('UPDATE', 'DELETE') and old.locked then
    raise exception 'locked_entry: this time entry is locked' using errcode = '42501';
  end if;

  select lock_entries_before into lock_date from public.workspaces where id = wid;
  if lock_date is not null then
    if tg_op in ('UPDATE', 'DELETE') and old.start_at::date < lock_date then
      raise exception 'locked_period: entries before % are locked', lock_date using errcode = '42501';
    end if;
    if tg_op in ('INSERT', 'UPDATE') and new.start_at::date < lock_date then
      raise exception 'locked_period: entries before % are locked', lock_date using errcode = '42501';
    end if;
  end if;

  if tg_op = 'UPDATE' and new.locked and not old.locked then
    raise exception 'insufficient_privilege: only admins can lock entries' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and new.locked then
    raise exception 'insufficient_privilege: only admins can lock entries' using errcode = '42501';
  end if;
  return result;
end $$;
drop trigger if exists time_entries_guard on public.time_entries;
create trigger time_entries_guard before insert or update or delete on public.time_entries
  for each row execute function public.time_entries_guard();

-- ---------------------------------------------------------------------------
-- time_entry_tags
-- ---------------------------------------------------------------------------
alter table public.time_entry_tags enable row level security;
drop policy if exists time_entry_tags_select on public.time_entry_tags;
create policy time_entry_tags_select on public.time_entry_tags for select to authenticated
  using (user_id = auth.uid() or public.is_manager(workspace_id));
drop policy if exists time_entry_tags_write on public.time_entry_tags;
create policy time_entry_tags_write on public.time_entry_tags for all to authenticated
  using (user_id = auth.uid() or public.is_admin(workspace_id))
  with check (user_id = auth.uid() or public.is_admin(workspace_id));

-- ---------------------------------------------------------------------------
-- Tables techniques hors API : rien n'est exposé par PostgREST en dehors de public.
-- ---------------------------------------------------------------------------
