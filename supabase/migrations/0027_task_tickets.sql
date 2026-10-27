-- 0027 — Tickets clients : une tâche porte l'URL d'un ticket (Jira, Linear, GitHub) et sa clé (« ENG-123 »).
-- Plan : plans/19-tickets-clients.md (lot 1).
--
-- La clé, tirée de l'URL par l'app (et par le serveur au lot 2), retrouve la tâche d'un ticket dans un projet. Pas
-- d'index unique : une écriture faite hors ligne puis refusée serait perdue ; l'app et le serveur cherchent la tâche
-- avant de la créer. Nullables : rien à « toucher » pour la réplication.
alter table public.tasks
  add column if not exists ticket_url text check (ticket_url is null or length(ticket_url) between 1 and 500),
  add column if not exists ticket_key text check (ticket_key is null or length(ticket_key) between 1 and 60);

create index if not exists tasks_ticket_key_idx on public.tasks (project_id, lower(ticket_key))
  where ticket_key is not null and deleted_at is null;
