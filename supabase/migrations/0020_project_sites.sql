-- 0020 — Présence chantier (exécuté en tant que postgres).
-- Plan : plans/13-ux-moderne.md (lot 13).
--
-- Position et rayon du chantier d'un projet, saisis par un manager (projects_write) : le téléphone de qui a
-- activé « Présence chantier » compare sa propre position à ce périmètre, sur l'appareil, et n'en tire que des
-- heures d'arrivée et de départ, proposées dans « Aujourd'hui ». La position d'une personne n'est jamais envoyée.
--
-- Règle de l'entreprise pour ces heures (workspaces.presence_rounding) : null ou 'actual', heures détectées
-- (à 5 minutes près) ; 'planning', calées sur la journée type quand elles en sont à moins de 30 minutes.
-- Colonnes nulles par défaut : rien à « toucher » pour PowerSync.
alter table public.projects
  add column if not exists site_lat double precision,
  add column if not exists site_lng double precision,
  add column if not exists site_radius integer;

alter table public.projects drop constraint if exists projects_site_check;
alter table public.projects add constraint projects_site_check check (
  (site_lat is null) = (site_lng is null)
  and (site_lat is null or (site_lat between -90 and 90 and site_lng between -180 and 180))
  and (site_radius is null or site_radius between 30 and 5000)
);

alter table public.workspaces
  add column if not exists presence_rounding text;

alter table public.workspaces drop constraint if exists workspaces_presence_rounding_check;
alter table public.workspaces add constraint workspaces_presence_rounding_check check (
  presence_rounding is null or presence_rounding in ('actual', 'planning')
);
