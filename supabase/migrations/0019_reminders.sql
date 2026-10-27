-- 0019 — Relances de feuille de temps (exécuté en tant que postgres).
-- Plan : plans/13-ux-moderne.md (lot 8).
--
-- Un chef d'équipe ou un manager relance un membre qui n'a pas soumis sa semaine : une ligne par relance, que l'app
-- du membre affiche (bandeau, notification) jusqu'à ce qu'il la marque vue. Droits par la RLS : relancer ceux qu'on
-- encadre (manages) ; lire les siennes, ou celles de son équipe ; marquer vue la sienne, annuler celle qu'on a faite.
create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, -- la personne relancée
  kind text not null default 'timesheet' check (kind in ('timesheet')),
  period_start date not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists reminders_user_idx on public.reminders(workspace_id, user_id, period_start);
create trigger reminders_updated_at before update on public.reminders
  for each row execute function public.set_updated_at();

-- L'auteur est celui qui écrit (le client n'en décide pas), et une relance ne change ni de personne ni de semaine.
create or replace function public.reminders_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
  elsif new.user_id is distinct from old.user_id or new.workspace_id is distinct from old.workspace_id
        or new.period_start is distinct from old.period_start or new.created_by is distinct from old.created_by then
    raise exception 'invalid_operation: a reminder cannot change person, period or author' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists reminders_a_guard on public.reminders;
create trigger reminders_a_guard before insert or update on public.reminders
  for each row execute function public.reminders_guard();

alter table public.reminders enable row level security;
drop policy if exists reminders_select on public.reminders;
create policy reminders_select on public.reminders for select to authenticated
  using (user_id = auth.uid() or public.manages(workspace_id, user_id));
drop policy if exists reminders_insert on public.reminders;
create policy reminders_insert on public.reminders for insert to authenticated
  with check (user_id <> auth.uid() and public.manages(workspace_id, user_id));
drop policy if exists reminders_update on public.reminders;
create policy reminders_update on public.reminders for update to authenticated
  using (user_id = auth.uid() or created_by = auth.uid())
  with check (user_id = auth.uid() or created_by = auth.uid());

grant select, insert, update on public.reminders to authenticated;
grant select on public.reminders to powersync_role;
grant all on public.reminders to service_role;
