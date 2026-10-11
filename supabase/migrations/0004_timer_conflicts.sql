-- 0004 — Résolution serveur des conflits de chronomètre (exécuté en tant que postgres).
--
-- Cas typique offline-first : l'utilisateur démarre un chronomètre sur son téléphone hors ligne,
-- puis un autre sur le web. À la synchronisation, deux entrées « en cours » arrivent pour le
-- même (workspace, user). Plutôt que de rejeter la seconde (index unique → donnée perdue),
-- on applique la règle « le plus récent gagne » :
--   * si le chronomètre existant a démarré avant le nouveau : il est arrêté à l'heure de début du nouveau ;
--   * sinon (le nouveau est en fait plus ancien) : le nouveau est enregistré déjà terminé,
--     avec une fin égale au début de celui qui tourne.
-- Aucune donnée n'est perdue et l'invariant « un seul chronomètre en cours » est conservé.

create or replace function public.time_entries_single_running()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  other record;
begin
  if new.end_at is not null or new.deleted_at is not null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.end_at is null and old.deleted_at is null then
    return new; -- déjà en cours, rien ne change
  end if;

  select id, start_at into other
    from public.time_entries
   where workspace_id = new.workspace_id and user_id = new.user_id
     and end_at is null and deleted_at is null and id <> new.id
   for update
   limit 1;

  if not found then
    return new;
  end if;

  if other.start_at <= new.start_at then
    update public.time_entries set end_at = new.start_at where id = other.id;
  else
    new.end_at := other.start_at;
    new.duration_seconds := greatest(0, floor(extract(epoch from (new.end_at - new.start_at)))::integer);
  end if;
  return new;
end $$;

-- Le nom commence par « time_entries_a » pour s'exécuter avant time_entries_before_write
-- (les triggers BEFORE s'exécutent par ordre alphabétique) : la durée est recalculée ensuite.
drop trigger if exists time_entries_a_single_running on public.time_entries;
create trigger time_entries_a_single_running before insert or update on public.time_entries
  for each row execute function public.time_entries_single_running();
