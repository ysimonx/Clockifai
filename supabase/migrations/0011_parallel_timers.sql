-- 0011 — Chronomètres simultanés (exécuté en tant que postgres). Plan : plans/05-chronometres-paralleles.md
--
-- `workspaces.max_running_timers` : nombre de chronomètres qu'un membre peut faire tourner en même
-- temps (1 = comportement d'origine, 0 = illimité). Utile quand on mène plusieurs chantiers en
-- parallèle (agents IA sur plusieurs postes, par exemple).
--
-- La règle de 0004 (« le plus récent gagne ») est généralisée : les `lim` chronomètres les plus
-- récents tournent, les plus anciens sont arrêtés au début du nouveau. Un chronomètre arrivé en
-- retard (créé hors ligne) et plus ancien que les `lim` en cours est enregistré déjà terminé, au
-- début du plus ancien de ceux qui restent. Avec `lim = 1`, le comportement est celui de 0004.

alter table public.workspaces add column if not exists max_running_timers smallint not null default 1
  check (max_running_timers >= 0);
-- Les colonnes ajoutées ne sont répliquées par PowerSync qu'au prochain changement de ligne.
update public.workspaces set max_running_timers = max_running_timers;

-- L'index unique ne peut pas dépendre d'un réglage : la limite passe dans le trigger, et un verrou
-- consultatif par (workspace, user) remplace sa garantie face aux démarrages concurrents.
drop index if exists public.time_entries_one_running_idx;
create index if not exists time_entries_running_idx
  on public.time_entries(workspace_id, user_id)
  where end_at is null and deleted_at is null;

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

-- Le nom commence par « time_entries_a » pour s'exécuter avant time_entries_before_write
-- (les triggers BEFORE s'exécutent par ordre alphabétique) : la durée est recalculée ensuite.
drop trigger if exists time_entries_a_single_running on public.time_entries;
drop function if exists public.time_entries_single_running();
drop trigger if exists time_entries_a_running_limit on public.time_entries;
create trigger time_entries_a_running_limit before insert or update on public.time_entries
  for each row execute function public.time_entries_running_limit();
