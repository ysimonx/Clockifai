-- 0017 — Journée type de chacun (exécuté en tant que postgres).
-- Plan : plans/13-ux-moderne.md (lot 2).
--
-- Arrivée, début et fin de pause, départ, à l'horloge (« 08:30 ») : la page « Aujourd'hui » en tire ses créneaux
-- vides et ses propositions. Nulles : Clockifai les déduit des semaines passées (app, features/today/day_plan.dart).
-- Réglage personnel : chacun modifie son profil (profiles_update_own). Colonnes nulles par défaut : rien à
-- « toucher » pour PowerSync.
alter table public.profiles
  add column if not exists day_start text,
  add column if not exists lunch_start text,
  add column if not exists lunch_end text,
  add column if not exists day_end text;

alter table public.profiles drop constraint if exists profiles_day_check;
alter table public.profiles add constraint profiles_day_check check (
  (day_start is null or day_start ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
  and (lunch_start is null or lunch_start ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
  and (lunch_end is null or lunch_end ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
  and (day_end is null or day_end ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
);
