-- Revue du code, lot 4 (plans/17-revue-du-code.md) : taux des entrées posé par le serveur hors managers ; entrée en
-- cours d'un agent désactivé ou retiré fermée à sa dernière activité.

-- ===========================================================================
-- 1. Taux d'une entrée
-- ===========================================================================
-- Hors managers, le taux est celui du projet, sinon du membre, à la création comme au changement de projet, et ne
-- change pas sinon : un membre ne fixe plus le prix de son temps par l'API (exports et factures le prennent en
-- premier). L'app calcule le même (`CatalogController.rateFor`) ; il est remplacé plutôt que refusé, pour qu'une
-- entrée saisie hors ligne avec un référentiel en retard ne reste pas bloquée dans la file d'envoi.
create or replace function public.time_entries_rate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.guard_bypassed() or public.is_manager(new.workspace_id) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.project_id is not distinct from old.project_id then
    new.hourly_rate_cents := old.hourly_rate_cents;
  else
    new.hourly_rate_cents := coalesce(
      (select p.hourly_rate_cents from public.projects p
        where p.id = new.project_id and p.workspace_id = new.workspace_id),
      (select m.hourly_rate_cents from public.workspace_members m
        where m.workspace_id = new.workspace_id and m.user_id = new.user_id));
  end if;
  return new;
end $$;
drop trigger if exists time_entries_rate on public.time_entries;
create trigger time_entries_rate before insert or update on public.time_entries
  for each row execute function public.time_entries_rate();

-- ===========================================================================
-- 2. Agent désactivé ou retiré : son entrée en cours s'arrête
-- ===========================================================================
-- Le serveur ne recalcule plus ses sessions (process_session sort sans rien écrire) : l'entrée restait ouverte. Elle
-- s'arrête à sa dernière activité, comme après une inactivité (D7.4), et `server_end_at` suit : réactivé, l'agent
-- reprend la session là où le serveur l'avait laissée.
create or replace function public.stop_agent_entries(wid uuid, agent uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('clockifai.bypass_guard', 'on', true);
  with stopped as (
    update public.time_entries te
       set end_at = greatest(te.start_at, least(now(), coalesce(
             (select ae.last_activity_at from clockifai_private.agent_entries ae where ae.time_entry_id = te.id),
             now())))
     where te.workspace_id = wid and te.user_id = agent and te.end_at is null and te.deleted_at is null
    returning te.id, te.end_at)
  update clockifai_private.agent_entries ae
     set server_end_at = stopped.end_at, closed_by_idle = true
    from stopped
   where ae.time_entry_id = stopped.id;
  perform set_config('clockifai.bypass_guard', '', true);
end $$;
revoke all on function public.stop_agent_entries(uuid, uuid) from public, anon, authenticated;

create or replace function public.workspace_members_agent_stop()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'agent' and (new.status <> 'active' or new.deleted_at is not null) then
    perform public.stop_agent_entries(new.workspace_id, new.user_id);
  end if;
  return null;
end $$;
drop trigger if exists workspace_members_agent_stop on public.workspace_members;
create trigger workspace_members_agent_stop after update of status, deleted_at on public.workspace_members
  for each row execute function public.workspace_members_agent_stop();

-- Agents déjà désactivés ou retirés avant cette migration.
select public.stop_agent_entries(m.workspace_id, m.user_id)
  from public.workspace_members m
 where m.kind = 'agent' and (m.status <> 'active' or m.deleted_at is not null)
   and exists (select 1 from public.time_entries te
                where te.workspace_id = m.workspace_id and te.user_id = m.user_id
                  and te.end_at is null and te.deleted_at is null);
