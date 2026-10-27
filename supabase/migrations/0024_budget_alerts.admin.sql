-- 0024 — Alertes de budget : journal des emails envoyés (exécuté en tant que supabase_admin).
-- Plan : plans/18-rapports-presence-alertes-partage.md (lot 2).
--
-- Une ligne par seuil franchi (80 ou 100 %) d'un budget de projet (heures, montant) ou de l'estimation d'une tâche :
-- le job Flask n'écrit qu'une fois chaque alerte. La valeur du budget fait partie de la clé : un budget relevé
-- réarme l'alerte.
create table if not exists clockifai_private.budget_alerts (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  target_id uuid not null,
  metric text not null check (metric in ('hours', 'amount', 'estimate')),
  threshold smallint not null check (threshold in (80, 100)),
  budget bigint not null,
  created_at timestamptz not null default now(),
  primary key (target_id, metric, threshold, budget)
);

alter table clockifai_private.budget_alerts owner to postgres;
revoke all on clockifai_private.budget_alerts from public, anon, authenticated, powersync_role;
