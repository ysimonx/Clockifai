-- Données de démonstration pour le workspace par défaut d'un utilisateur existant.
--   make seed EMAIL=vous@exemple.fr
-- Crée : 2 clients, 4 projets avec tâches, des tags, 3 semaines d'entrées de temps,
-- une politique d'absence, des jours fériés et un peu de planning. Idempotent par nom de client.
\set ON_ERROR_STOP on
-- Les variables psql ne sont pas substituées dans un bloc $$ : on passe l'email par un réglage de session.
select set_config('clockifai.seed_email', :'email', false) \gset
do $$
declare
  uid uuid; wid uuid; c1 uuid; c2 uuid; p uuid[]; t1 uuid; t2 uuid; pol uuid; d date; i int; h int;
  descs text[] := array['Montage échafaudage', 'Réunion de chantier', 'Calorifugeage tuyauterie', 'Démontage', 'Préparation matériel', 'Rapport client'];
begin
  select id into uid from public.profiles where lower(email) = lower(current_setting('clockifai.seed_email'));
  if uid is null then raise exception 'utilisateur % introuvable', current_setting('clockifai.seed_email'); end if;
  select coalesce(default_workspace_id, (select workspace_id from public.workspace_members where user_id = uid limit 1)) into wid
    from public.profiles where id = uid;
  if exists (select 1 from public.clients where workspace_id = wid and name = 'Raffinerie Nord (démo)') then
    raise notice 'Données de démo déjà présentes.'; return;
  end if;

  insert into public.clients (workspace_id, name, address, email) values (wid, 'Raffinerie Nord (démo)', '1 route du Port\n59140 Dunkerque', 'achats@raffinerie.example') returning id into c1;
  insert into public.clients (workspace_id, name) values (wid, 'Centrale Sud (démo)') returning id into c2;
  insert into public.projects (workspace_id, client_id, name, color, hourly_rate_cents, budget_hours) values
    (wid, c1, 'Échafaudage unité 4', '#F97316', 4800, 120),
    (wid, c1, 'Calorifuge ligne vapeur', '#0EA5E9', 5200, 80),
    (wid, c2, 'Arrêt de tranche 2026', '#8B5CF6', 5500, 200);
  insert into public.projects (workspace_id, name, color, billable_default) values (wid, 'Interne', '#64748B', false);
  -- Ordre explicite (le tri alphabétique dépend de la collation et des accents).
  p := array[
    (select id from public.projects where workspace_id = wid and name = 'Échafaudage unité 4' and deleted_at is null),
    (select id from public.projects where workspace_id = wid and name = 'Calorifuge ligne vapeur' and deleted_at is null),
    (select id from public.projects where workspace_id = wid and name = 'Arrêt de tranche 2026' and deleted_at is null),
    (select id from public.projects where workspace_id = wid and name = 'Interne' and deleted_at is null)];
  insert into public.tasks (workspace_id, project_id, name) values (wid, p[1], 'Montage') returning id into t1;
  insert into public.tasks (workspace_id, project_id, name) values (wid, p[1], 'Démontage') returning id into t2;
  insert into public.tags (workspace_id, name, color) values (wid, 'Nuit', '#6366F1'), (wid, 'Astreinte', '#EF4444'), (wid, 'Déplacement', '#10B981');

  for i in 0..20 loop
    d := current_date - i;
    continue when extract(isodow from d) > 5;
    h := 7 + (i % 2);
    insert into public.time_entries (workspace_id, user_id, project_id, task_id, description, start_at, end_at, billable, hourly_rate_cents)
    select wid, uid, p[1 + (i % 4)], case when 1 + (i % 4) = 1 then t1 end, descs[1 + (i % 6)],
           d + make_time(h, 0, 0), d + make_time(h + 4, 0, 0),
           pr.billable_default, pr.hourly_rate_cents
      from public.projects pr where pr.id = p[1 + (i % 4)];
    insert into public.time_entries (workspace_id, user_id, project_id, description, start_at, end_at, billable, hourly_rate_cents)
    select wid, uid, p[1 + ((i + 1) % 4)], descs[1 + ((i + 3) % 6)],
           d + make_time(h + 5, 0, 0), d + make_time(h + 8, 30, 0),
           pr.billable_default, pr.hourly_rate_cents
      from public.projects pr where pr.id = p[1 + ((i + 1) % 4)];
  end loop;

  insert into public.time_off_policies (workspace_id, name, annual_allowance, color) values (wid, 'Congés payés', 25, '#10B981') returning id into pol;
  insert into public.time_off_policies (workspace_id, name, annual_allowance, unit, color, requires_approval) values (wid, 'RTT', 10, 'days', '#F59E0B', true);
  insert into public.holidays (workspace_id, name, date) values
    (wid, 'Armistice', make_date(extract(year from current_date)::int, 11, 11)),
    (wid, 'Noël', make_date(extract(year from current_date)::int, 12, 25));
  insert into public.schedule_assignments (workspace_id, user_id, project_id, start_date, end_date, hours_per_day, created_by)
    values (wid, uid, p[1], current_date, current_date + 4, 7, uid);
  raise notice 'Données de démo créées dans le workspace %', wid;
end $$;
