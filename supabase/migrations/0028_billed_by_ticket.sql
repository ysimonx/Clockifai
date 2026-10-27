-- 0028 — Projet « facturé par ticket » (exécuté en tant que postgres).
-- Plan : plans/19-tickets-clients.md (lot 2).
--
-- Dans les dépôts rattachés à un tel projet, le plugin Claude Code fait demander le ticket du client au début de
-- chaque session, s'il n'est ni dans le premier message ni dans le nom de la branche ; la clé trouvée dans le nom de
-- la branche y vaut ticket. Réglé par les managers (politiques des projets inchangées).
alter table public.projects add column if not exists billed_by_ticket boolean not null default false;
-- Les colonnes ajoutées ne sont répliquées par PowerSync qu'au prochain changement de ligne.
update public.projects set billed_by_ticket = billed_by_ticket;
