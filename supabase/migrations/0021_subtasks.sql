-- Sous-tâches (plans/16-sous-taches.md) : Projet › Tâche › Sous-tâche, un seul niveau. Une entrée se range sur une
-- tâche ou sur une sous-tâche ; les totaux par tâche comptent ses sous-tâches (côté app et exports).

alter table public.tasks add column if not exists parent_id uuid references public.tasks(id) on delete cascade;
create index if not exists tasks_parent_idx on public.tasks(parent_id) where parent_id is not null;

-- Le parent est une tâche du même projet, sans parent lui-même ; une tâche qui a des sous-tâches n'en devient pas une.
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
  select project_id, workspace_id, parent_id into p from public.tasks where id = new.parent_id;
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
  return new;
end $$;

drop trigger if exists tasks_parent_guard on public.tasks;
create trigger tasks_parent_guard before insert or update of parent_id, project_id on public.tasks
  for each row execute function public.tasks_parent_guard();

-- Une tâche supprimée (suppression douce) emporte ses sous-tâches ; restaurée, elle les rend (même horodatage :
-- seules celles supprimées avec elle). Déplacée dans un autre projet, ses sous-tâches la suivent.
create or replace function public.tasks_cascade_children() returns trigger
language plpgsql as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.tasks set deleted_at = new.deleted_at where parent_id = new.id and deleted_at is null;
  elsif new.deleted_at is null and old.deleted_at is not null then
    update public.tasks set deleted_at = null where parent_id = new.id and deleted_at = old.deleted_at;
  end if;
  if new.project_id <> old.project_id then
    update public.tasks set project_id = new.project_id where parent_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists tasks_cascade_children on public.tasks;
create trigger tasks_cascade_children after update of deleted_at, project_id on public.tasks
  for each row when (old.deleted_at is distinct from new.deleted_at or old.project_id <> new.project_id)
  execute function public.tasks_cascade_children();
