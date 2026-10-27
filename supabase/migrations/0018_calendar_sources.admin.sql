-- 0018 — Agenda de chacun (exécuté en tant que supabase_admin).
-- Plan : plans/13-ux-moderne.md (lot 4, question 3).
--
-- L'adresse iCal privée d'un agenda (Google, Outlook, Apple…) : qui la connaît lit l'agenda. Elle est donc gardée
-- comme les autres secrets, hors API et hors réplication ; seul Flask la lit (services/app/services/calendar.py)
-- pour renvoyer l'heure et le titre des événements à son propriétaire. Une par personne, tous workspaces confondus.
create table if not exists clockifai_private.calendar_sources (
  user_id uuid primary key references auth.users(id) on delete cascade,
  url text not null,
  updated_at timestamptz not null default now()
);

alter table clockifai_private.calendar_sources owner to postgres;
revoke all on clockifai_private.calendar_sources from public, anon, authenticated, powersync_role;
