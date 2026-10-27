-- 0026 — Envoi planifié des rapports partagés (exécuté en tant que supabase_admin).
-- Plan : plans/18-rapports-presence-alertes-partage.md (lot 4).
--
-- `schedule` : chaque semaine (la semaine passée, le premier jour de la semaine du workspace) ou chaque mois (le mois
-- passé, le 1er), à 8 h dans le fuseau du créateur. `last_sent_period` : premier jour de la dernière période envoyée,
-- pour ne jamais l'envoyer deux fois ; posé à la dernière période terminée quand l'envoi est réglé : le premier
-- email couvre la période en cours, une fois finie, et pas celle d'avant.
alter table clockifai_private.saved_reports
  add column if not exists schedule text check (schedule in ('weekly', 'monthly')),
  add column if not exists recipients text[] not null default '{}',
  add column if not exists last_sent_period date,
  add column if not exists last_sent_at timestamptz;
