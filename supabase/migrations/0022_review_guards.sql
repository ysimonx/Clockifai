-- Revue d'octobre 2026 (plans/17-revue-du-code.md) : règles que la base doit tenir elle-même, puisque chacun est
-- propriétaire de son « Espace de … » et peut y créer politiques, factures ou tâches, puis viser par PostgREST les
-- lignes d'un autre workspace.

-- 1. Absences : la politique d'une demande ou d'un solde appartient au workspace de la ligne. Sans cela, une
--    politique « sans approbation » de son propre espace faisait approuver d'office une demande dans l'entreprise.
create or replace function public.time_off_policy_same_workspace()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.time_off_policies p where p.id = new.policy_id and p.workspace_id = new.workspace_id) then
    raise exception 'invalid_policy: the policy belongs to another workspace' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists time_off_requests_policy on public.time_off_requests;
create trigger time_off_requests_policy before insert or update of policy_id, workspace_id on public.time_off_requests
  for each row execute function public.time_off_policy_same_workspace();
drop trigger if exists time_off_allowances_policy on public.time_off_allowances;
create trigger time_off_allowances_policy before insert or update of policy_id, workspace_id on public.time_off_allowances
  for each row execute function public.time_off_policy_same_workspace();

create or replace function public.can_decide_time_off(wid uuid, uid uuid, pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_manager(wid)
      or (exists (select 1 from public.time_off_policies p
                   where p.id = pid and p.workspace_id = wid and p.approvers = 'managers_and_team_managers')
          and exists (select 1 from public.team_scope s
                       where s.workspace_id = wid and s.manager_id = auth.uid() and s.user_id = uid))
$$;

-- 2. Factures et tags : l'entrée, la facture et le tag d'un lien sont du même workspace que lui, et le tag d'une
--    entrée porte la personne de l'entrée. Sinon le manager de son propre espace pouvait « facturer » (donc figer)
--    les entrées des collaborateurs qu'il encadre ailleurs.
create or replace function public.invoice_entries_same_workspace()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.invoices i where i.id = new.invoice_id and i.workspace_id = new.workspace_id)
     or not exists (select 1 from public.time_entries te
                     where te.id = new.time_entry_id and te.workspace_id = new.workspace_id) then
    raise exception 'invalid_link: invoice and entry belong to the workspace of the link' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists invoice_entries_same_workspace on public.invoice_entries;
create trigger invoice_entries_same_workspace before insert or update on public.invoice_entries
  for each row execute function public.invoice_entries_same_workspace();

create or replace function public.time_entry_tags_same_workspace()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.time_entries te where te.id = new.time_entry_id
                    and te.workspace_id = new.workspace_id and te.user_id = new.user_id)
     or not exists (select 1 from public.tags t where t.id = new.tag_id and t.workspace_id = new.workspace_id) then
    raise exception 'invalid_link: entry and tag belong to the workspace and person of the link' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists time_entry_tags_same_workspace on public.time_entry_tags;
create trigger time_entry_tags_same_workspace before insert or update on public.time_entry_tags
  for each row execute function public.time_entry_tags_same_workspace();

-- 3. Membres (remplace 0013) : seul un propriétaire donne ou retire le rôle de propriétaire (un admin promu owner
--    pouvait supprimer le workspace) ; hors admins, la capacité journalière ne change pas, et l'adresse ne suit que
--    celle du profil (profiles_after_update).
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
    -- Le premier membre d'un workspace en est le propriétaire (workspaces_after_insert).
    if new.role = 'owner' and public.member_role(new.workspace_id) is distinct from 'owner'
       and exists (select 1 from public.workspace_members m where m.workspace_id = new.workspace_id) then
      raise exception 'insufficient_privilege: only an owner can add an owner' using errcode = '42501';
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
       or new.capacity_hours_per_day is distinct from old.capacity_hours_per_day
       or new.workspace_id is distinct from old.workspace_id
       or new.user_id is distinct from old.user_id
       or new.deleted_at is distinct from old.deleted_at
       or (new.email is distinct from old.email
           and new.email is distinct from (select p.email from public.profiles p where p.id = new.user_id)) then
      raise exception 'insufficient_privilege: only admins can change role, status, rates, capacity or membership'
        using errcode = '42501';
    end if;
  end if;
  if (new.role = 'owner') is distinct from (old.role = 'owner')
     and public.member_role(new.workspace_id) is distinct from 'owner' then
    raise exception 'insufficient_privilege: only an owner can give or take the owner role' using errcode = '42501';
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

-- 4. Tâches (remplace 0010) : ranger une tâche sous une autre, ou l'en sortir, est réservé aux managers comme la
--    déplacer ; le créateur ne fait que renommer.
create or replace function public.tasks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_manager(new.workspace_id) then
    return new; -- service_role / triggers internes / managers
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'active' or new.estimate_seconds is not null or new.deleted_at is not null then
      raise exception 'insufficient_privilege: members create active tasks without estimate'
        using errcode = '42501';
    end if;
  elsif new.workspace_id is distinct from old.workspace_id
     or new.project_id is distinct from old.project_id
     or new.parent_id is distinct from old.parent_id
     or new.estimate_seconds is distinct from old.estimate_seconds
     or new.status is distinct from old.status
     or new.deleted_at is distinct from old.deleted_at
     or new.created_by is distinct from old.created_by then
    raise exception 'insufficient_privilege: only managers can move, estimate, close or delete a task'
      using errcode = '42501';
  end if;
  return new;
end $$;

-- Sous-tâche créée hors ligne sous une tâche supprimée entre-temps : supprimée avec elle (la purge du parent
-- l'emporterait sinon, encore active et invisible). Remplace 0021.
create or replace function public.tasks_parent_guard() returns trigger
language plpgsql as $$
declare
  p record;
begin
  if new.parent_id is null then
    return new;
  end if;
  if new.parent_id = new.id then
    raise exception 'a task cannot be its own parent' using errcode = '23514';
  end if;
  select project_id, workspace_id, parent_id, deleted_at into p from public.tasks where id = new.parent_id;
  if not found then
    raise exception 'parent task not found' using errcode = '23503';
  end if;
  if p.workspace_id <> new.workspace_id or p.project_id <> new.project_id then
    raise exception 'a subtask belongs to the project of its parent' using errcode = '23514';
  end if;
  if p.parent_id is not null then
    raise exception 'subtasks have one level only' using errcode = '23514';
  end if;
  if exists (select 1 from public.tasks c where c.parent_id = new.id and c.deleted_at is null) then
    raise exception 'a task with subtasks cannot become a subtask' using errcode = '23514';
  end if;
  if p.deleted_at is not null and new.deleted_at is null then
    new.deleted_at := p.deleted_at;
  end if;
  return new;
end $$;

-- 5. Relances (remplace 0019) : la personne relancée ne fait que marquer la relance vue ; la supprimer la retirait
--    du tableau des retards de son chef.
create or replace function public.reminders_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    return new;
  end if;
  if new.user_id is distinct from old.user_id or new.workspace_id is distinct from old.workspace_id
     or new.period_start is distinct from old.period_start or new.created_by is distinct from old.created_by then
    raise exception 'invalid_operation: a reminder cannot change person, period or author' using errcode = '42501';
  end if;
  if auth.uid() = old.user_id and auth.uid() is distinct from old.created_by
     and (to_jsonb(new) - '{seen_at,updated_at}'::text[]) is distinct from (to_jsonb(old) - '{seen_at,updated_at}'::text[]) then
    raise exception 'insufficient_privilege: the reminded person can only mark it seen' using errcode = '42501';
  end if;
  return new;
end $$;

-- 6. Chronomètres (remplace 0013) : arrêter l'ancien chronomètre (« le plus récent gagne ») passe la garde des
--    entrées. Verrouillé par une approbation ou antérieur au verrou, il faisait échouer le nouveau (42501), que le
--    connecteur abandonne.
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
      perform set_config('clockifai.bypass_guard', 'on', true);
      update public.time_entries set end_at = new.start_at where id = other.id;
      perform set_config('clockifai.bypass_guard', '', true);
    end if;
  end loop;

  if not new_kept and kept >= lim then
    new.end_at := oldest_kept;
    new.duration_seconds := greatest(0, floor(extract(epoch from (new.end_at - new.start_at)))::integer);
  end if;
  return new;
end $$;

-- 7. Fonctions internes appelées seulement par des fonctions security definer : pas d'appel RPC (elles lisaient les
--    équipes ou le fuseau de n'importe quel workspace).
revoke execute on function public.team_scope_wanted(uuid), public.refresh_team_scope(uuid),
  public.user_local_date(timestamptz, uuid) from anon, authenticated;

-- 8. Index : tâches d'une entrée (Claude, purge des tâches), tags (purge), commits du journal du jour.
create index if not exists time_entries_task_idx on public.time_entries(task_id) where task_id is not null;
create index if not exists time_entry_tags_tag_idx on public.time_entry_tags(tag_id);
create index if not exists code_commits_author_idx on public.code_commits(workspace_id, author_user_id, authored_at);
