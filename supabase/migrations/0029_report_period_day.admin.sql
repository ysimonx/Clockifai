-- 0029 — Rapports partagés sur un jour : « Aujourd'hui » et « Hier » (exécuté en tant que supabase_admin).
-- Calculés à l'ouverture, dans le fuseau du créateur, comme les autres périodes relatives.
alter table clockifai_private.saved_reports drop constraint if exists saved_reports_period_check;
alter table clockifai_private.saved_reports add constraint saved_reports_period_check
  check (period in ('today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'this_year', 'custom'));
