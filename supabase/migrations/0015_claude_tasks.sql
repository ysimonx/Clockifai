-- 0015 — Réglage « Tâches de Claude » de chaque pilote (exécuté en tant que postgres).
-- Plan : plans/10-suivi-claude-code.md (D18).
--
-- `subject` : une tâche par sujet nommé par Claude (même nom, même tâche) ; `session` : une tâche par session Claude
-- Code, toujours nouvelle ; `off` : le temps de Claude ne va qu'au projet. Réglage personnel : chacun modifie son
-- profil (profiles_update_own), Flask le lit au recalcul des sessions.
alter table public.profiles add column if not exists claude_tasks text not null default 'subject'
  check (claude_tasks in ('subject', 'session', 'off'));
-- Les colonnes ajoutées ne sont répliquées par PowerSync qu'au prochain changement de ligne.
update public.profiles set claude_tasks = claude_tasks;
