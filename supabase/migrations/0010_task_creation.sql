-- 0010 — Création de tâches par les membres (Clockify : « Who can create tasks »).
-- (exécuté en tant que postgres)
--
-- `workspaces.task_creation` : 'everyone' (défaut) ou 'managers' (comportement d'origine).
-- Avec 'everyone', un membre crée une tâche sur un projet actif de son workspace depuis le
-- sélecteur de projet (chronomètre, saisie, feuille de temps). Il ne peut ensuite que la renommer :
-- estimation, statut, déplacement et suppression restent aux managers (`tasks_write`, 0003).
-- La politique de mise à jour rend aussi idempotent le rejeu d'un upsert du connecteur.

alter table public.workspaces add column if not exists task_creation text not null default 'everyone'
  check (task_creation in ('managers', 'everyone'));
-- Les colonnes ajoutées ne sont répliquées par PowerSync qu'au prochain changement de ligne.
update public.workspaces set task_creation = task_creation;

-- Auteur de la tâche : posé par défaut côté serveur, non synchronisé vers l'app.
alter table public.tasks add column if not exists created_by uuid default auth.uid()
  references auth.users(id) on delete set null;

-- Vrai si l'utilisateur connecté peut créer une tâche sur le projet `pid` du workspace `wid`.
create or replace function public.can_create_task(wid uuid, pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member(wid)
     and exists (select 1 from public.workspaces w where w.id = wid and w.task_creation = 'everyone')
     and exists (select 1 from public.projects p
                  where p.id = pid and p.workspace_id = wid and not p.archived and p.deleted_at is null)
$$;
revoke all on function public.can_create_task(uuid, uuid) from public;
grant execute on function public.can_create_task(uuid, uuid) to authenticated, service_role;

drop policy if exists tasks_insert_members on public.tasks;
create policy tasks_insert_members on public.tasks for insert to authenticated
  with check (created_by = auth.uid() and public.can_create_task(workspace_id, project_id));
drop policy if exists tasks_update_creator on public.tasks;
create policy tasks_update_creator on public.tasks for update to authenticated
  using (created_by = auth.uid() and public.can_create_task(workspace_id, project_id))
  with check (created_by = auth.uid() and public.can_create_task(workspace_id, project_id));

-- Hors managers : création d'une tâche active nue, puis renommage seulement.
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
     or new.estimate_seconds is distinct from old.estimate_seconds
     or new.status is distinct from old.status
     or new.deleted_at is distinct from old.deleted_at
     or new.created_by is distinct from old.created_by then
    raise exception 'insufficient_privilege: only managers can move, estimate, close or delete a task'
      using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists tasks_guard on public.tasks;
create trigger tasks_guard before insert or update on public.tasks
  for each row execute function public.tasks_guard();
