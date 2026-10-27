#!/bin/sh
# Prépare les données des vidéos de démonstration (pile locale démarrée : make up).
# Rejouable : supprime puis recrée les comptes *@demo.clockifai.fr et leurs données.
#
#   sh demo/prepare-demo.sh                        # données de démo
#   sh demo/prepare-demo.sh --clean-test-accounts  # supprime aussi les comptes *test.local des tests automatiques
#
# Entreprise « Échafaudages du Nord » :
#   Sophie Laurent   owner   gère le workspace (réglages, équipe, facturation)
#   Julien Moreau    manager conducteur de travaux : voit toute l'entreprise, valide, planifie, facture
#   Karim Haddad     member  chef de l'équipe « Unité 4 » (Camille, Léo, Hugo) : saisit et valide leur temps
#   Camille Martin   member  compagnon de l'équipe Unité 4
#   Léo Dubois, Hugo Petit   membres de l'équipe Unité 4
#   Nadia Rahmani    member  équipe « Calorifuge », hors du périmètre de Karim
# Studio « Studio Alex » (vidéo 6, Claude Code) :
#   Alex Girard      owner   développeur indépendant ; son agent « Claude · Alex Girard » travaille dans ses dépôts
# Mot de passe commun : Demo-2026-clockifai · PIN kiosque : 1234 (Camille), 2468 (Léo)
set -eu
cd "$(dirname "$0")/.."
ANON=$(grep '^ANON_KEY=' deploy/.env | cut -d= -f2)
SUPABASE=${SUPABASE_URL:-http://localhost:8000}
PSQL="docker exec -i -e PGTZ=Europe/Paris supabase-db psql -U postgres -v ON_ERROR_STOP=1 -q"

if [ "${1:-}" = "--clean-test-accounts" ]; then
  echo "[demo] suppression des comptes de test automatiques (*@test.local, agents *@agents.test.local, demo@clockifai.local)"
  $PSQL <<'SQL'
delete from public.workspaces where created_by in (select id from auth.users where email like '%test.local' or email = 'demo@clockifai.local');
delete from auth.users where email like '%test.local' or email = 'demo@clockifai.local';
-- Comptes techniques d'agents Claude dont le pilote n'existe plus (comptes de test supprimés).
delete from auth.users a where a.raw_app_meta_data ->> 'kind' = 'agent'
   and not exists (select 1 from auth.users o where o.id::text = a.raw_app_meta_data ->> 'owner_id');
-- Workspaces orphelins et vides laissés par la suppression de comptes de test.
delete from public.workspaces w where w.created_by is null
   and not exists (select 1 from public.workspace_members m where m.workspace_id = w.id)
   and not exists (select 1 from public.time_entries t where t.workspace_id = w.id);
SQL
fi

echo "[demo] nettoyage des comptes de démo précédents"
$PSQL <<'SQL'
delete from public.workspaces where created_by in (select id from auth.users where email like '%@demo.clockifai.fr');
-- Comptes techniques des agents Claude des comptes de démo (agent-<id>@agents.clockifai.invalid).
delete from auth.users where raw_app_meta_data ->> 'kind' = 'agent'
   and raw_app_meta_data ->> 'owner_id' in (select id::text from auth.users where email like '%@demo.clockifai.fr');
delete from auth.users where email like '%@demo.clockifai.fr';
SQL

signup() {
  curl -sf -X POST "$SUPABASE/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"Demo-2026-clockifai\",\"data\":{\"display_name\":\"$2\"}}" >/dev/null
  echo "[demo] compte $1"
}
signup sophie@demo.clockifai.fr "Sophie Laurent"
signup julien@demo.clockifai.fr "Julien Moreau"
signup karim@demo.clockifai.fr "Karim Haddad"
signup camille@demo.clockifai.fr "Camille Martin"
signup leo@demo.clockifai.fr "Léo Dubois"
signup hugo@demo.clockifai.fr "Hugo Petit"
signup nadia@demo.clockifai.fr "Nadia Rahmani"
signup alex@demo.clockifai.fr "Alex Girard"

echo "[demo] entreprise et équipe"
$PSQL <<'SQL'
do $$
declare
  sophie uuid := (select id from auth.users where email = 'sophie@demo.clockifai.fr');
  wid uuid := (select default_workspace_id from public.profiles where id = (select id from auth.users where email = 'sophie@demo.clockifai.fr'));
  r record;
begin
  update public.workspaces set
    name = 'Échafaudages du Nord',
    company_name = 'Échafaudages du Nord SAS',
    company_details = E'14 rue des Forges\n59000 Lille\nSIRET 123 456 789 00012 · TVA FR12 123456789',
    rounding_minutes = 15, auto_stop_after_hours = 12,
    time_for_others = 'admins_and_team_managers', task_creation = 'everyone'
  where id = wid;
  update public.workspace_members set hourly_rate_cents = 6500 where workspace_id = wid and user_id = sophie;
  for r in select u.id, u.email, p.display_name from auth.users u join public.profiles p on p.id = u.id
            where u.email like '%@demo.clockifai.fr' and u.id <> sophie and u.email <> 'alex@demo.clockifai.fr' loop
    insert into public.workspace_members (workspace_id, user_id, role, display_name, email, hourly_rate_cents, capacity_hours_per_day)
    values (wid, r.id, case r.email when 'julien@demo.clockifai.fr' then 'manager' else 'member' end, r.display_name, r.email,
            case r.email when 'julien@demo.clockifai.fr' then 6000 when 'karim@demo.clockifai.fr' then 5000
                         when 'nadia@demo.clockifai.fr' then 4500 else 4200 end, 7);
    -- Chacun travaille uniquement dans l'entreprise : on retire l'espace personnel créé à l'inscription.
    delete from public.workspaces where created_by = r.id;
    update public.profiles set default_workspace_id = wid where id = r.id;
  end loop;
end $$;
SQL
docker exec -i -e PGTZ=Europe/Paris supabase-db psql -U postgres -q -v email=sophie@demo.clockifai.fr < deploy/seed-demo.sql

echo "[demo] groupes, chef d'équipe, heures, approbations, absences, planning, kiosque"
$PSQL <<'SQL'
do $$
declare
  u_sophie uuid := (select id from auth.users where email = 'sophie@demo.clockifai.fr');
  u_karim uuid := (select id from auth.users where email = 'karim@demo.clockifai.fr');
  u_camille uuid := (select id from auth.users where email = 'camille@demo.clockifai.fr');
  u_leo uuid := (select id from auth.users where email = 'leo@demo.clockifai.fr');
  u_hugo uuid := (select id from auth.users where email = 'hugo@demo.clockifai.fr');
  u_nadia uuid := (select id from auth.users where email = 'nadia@demo.clockifai.fr');
  u_julien uuid := (select id from auth.users where email = 'julien@demo.clockifai.fr');
  wid uuid := (select default_workspace_id from public.profiles where id = (select id from auth.users where email = 'sophie@demo.clockifai.fr'));
  g_u4 uuid; g_calo uuid; scaf uuid; calo uuid; arret uuid; montage uuid; demontage uuid; cp uuid; rtt uuid;
  d date; mon date := date_trunc('week', current_date)::date; i int; who uuid;
begin
  insert into public.user_groups (workspace_id, name) values (wid, 'Équipe Unité 4') returning id into g_u4;
  insert into public.user_groups (workspace_id, name) values (wid, 'Équipe Calorifuge') returning id into g_calo;
  insert into public.user_group_members (workspace_id, group_id, user_id) values
    (wid, g_u4, u_camille), (wid, g_u4, u_leo), (wid, g_u4, u_hugo), (wid, g_calo, u_nadia);
  insert into public.team_manager_assignments (workspace_id, manager_id, group_id) values (wid, u_karim, g_u4);

  select id into scaf from public.projects where workspace_id = wid and name = 'Échafaudage unité 4';
  select id into calo from public.projects where workspace_id = wid and name = 'Calorifuge ligne vapeur';
  select id into arret from public.projects where workspace_id = wid and name = 'Arrêt de tranche 2026';
  select id into montage from public.tasks where project_id = scaf and name = 'Montage';
  select id into demontage from public.tasks where project_id = scaf and name = 'Démontage';
  select id into cp from public.time_off_policies where workspace_id = wid and name = 'Congés payés';
  select id into rtt from public.time_off_policies where workspace_id = wid and name = 'RTT';
  update public.time_off_policies set approvers = 'managers_and_team_managers' where workspace_id = wid;

  -- Trois semaines d'heures (jours ouvrés passés). Le jeudi, Karim a pointé toute l'équipe :
  -- ces entrées portent « saisi par Karim Haddad ».
  for i in 1..21 loop
    d := current_date - i;
    continue when extract(isodow from d) > 5;
    foreach who in array array[u_camille, u_leo, u_hugo, u_karim] loop
      insert into public.time_entries (workspace_id, user_id, project_id, task_id, description, start_at, end_at, billable, hourly_rate_cents, created_by) values
        (wid, who, scaf, case when i % 2 = 0 then montage else demontage end,
         case when i % 2 = 0 then 'Montage niveaux 3 et 4' else 'Démontage façade nord' end,
         (d + time '07:30') at time zone 'Europe/Paris', (d + time '12:00') at time zone 'Europe/Paris', true, 4800,
         case when extract(isodow from d) = 4 and who <> u_karim then u_karim end),
        (wid, who, scaf, montage, 'Pose garde-corps',
         (d + time '13:00') at time zone 'Europe/Paris', (d + time '16:00') at time zone 'Europe/Paris', true, 4800,
         case when extract(isodow from d) = 4 and who <> u_karim then u_karim end);
    end loop;
    insert into public.time_entries (workspace_id, user_id, project_id, description, start_at, end_at, billable, hourly_rate_cents) values
      (wid, u_nadia, calo, 'Calorifugeage ligne vapeur', (d + time '08:00') at time zone 'Europe/Paris', (d + time '12:00') at time zone 'Europe/Paris', true, 5200),
      (wid, u_nadia, arret, 'Préparation arrêt de tranche', (d + time '13:00') at time zone 'Europe/Paris', (d + time '16:30') at time zone 'Europe/Paris', true, 5500),
      -- Julien, conducteur de travaux : coordination (non facturée) et préparation de l'arrêt.
      (wid, u_julien, scaf, 'Coordination chantier unité 4', (d + time '07:30') at time zone 'Europe/Paris', (d + time '11:30') at time zone 'Europe/Paris', false, 6000),
      (wid, u_julien, arret, 'Préparation arrêt de tranche', (d + time '13:00') at time zone 'Europe/Paris', (d + time '16:00') at time zone 'Europe/Paris', true, 6000);
  end loop;

  -- La facture de la vidéo 4 porte par défaut sur le mois précédent, que les trois semaines ci-dessus ne couvrent
  -- pas toujours (selon le jour du tournage) : quelques jours facturables de plus, juste avant elles.
  for d in select generate_series(date_trunc('month', current_date) - interval '1 month', current_date - 22, interval '1 day')::date loop
    continue when extract(isodow from d) > 5;
    insert into public.time_entries (workspace_id, user_id, project_id, task_id, description, start_at, end_at, billable, hourly_rate_cents) values
      (wid, u_camille, scaf, case when extract(isodow from d) = 5 then demontage else montage end,
       case when extract(isodow from d) = 5 then 'Démontage niveau 1' else 'Montage niveaux 1 et 2' end,
       (d + time '07:30') at time zone 'Europe/Paris', (d + time '12:00') at time zone 'Europe/Paris', true, 4800),
      (wid, u_nadia, calo, null, 'Calorifugeage ligne vapeur', (d + time '08:00') at time zone 'Europe/Paris', (d + time '12:00') at time zone 'Europe/Paris', true, 5200),
      (wid, u_julien, arret, null, 'Préparation arrêt de tranche', (d + time '13:00') at time zone 'Europe/Paris', (d + time '16:00') at time zone 'Europe/Paris', true, 6000);
  end loop;

  -- Léo a soumis sa semaine dernière : Karim (ou Sophie) l'approuvera.
  insert into public.timesheet_submissions (workspace_id, user_id, period_start, period_end, total_seconds, note, status)
  values (wid, u_leo, mon - 7, mon - 1, 5 * 7.5 * 3600, 'Semaine complète sur l''unité 4', 'submitted');
  -- Nadia aussi, hors du périmètre de Karim : c'est Julien (manager) ou Sophie qui l'approuvera.
  insert into public.timesheet_submissions (workspace_id, user_id, period_start, period_end, total_seconds, note, status)
  values (wid, u_nadia, mon - 7, mon - 1, 5 * 7.5 * 3600, 'Calorifuge et préparation de l''arrêt', 'submitted');

  -- Absences : Hugo (équipe de Karim) et Nadia (hors équipe) en attente ; RTT de Camille validée.
  insert into public.time_off_requests (workspace_id, user_id, policy_id, start_date, end_date, amount, note, status) values
    (wid, u_hugo, cp, mon + 21, mon + 25, 5, 'Vacances de la Toussaint', 'pending'),
    (wid, u_nadia, cp, mon + 14, mon + 15, 2, null, 'pending'),
    (wid, u_camille, rtt, mon + 4, mon + 4, 1, 'Pont', 'approved');

  -- Planning des deux prochaines semaines (Karim volontairement en surcharge : 8 h pour 7 h).
  insert into public.schedule_assignments (workspace_id, user_id, project_id, start_date, end_date, hours_per_day, note, created_by) values
    (wid, u_camille, scaf, mon, mon + 3, 7, 'Unité 4 – niveaux 5 à 7', u_sophie),
    (wid, u_leo, scaf, mon, mon + 4, 7, 'Unité 4 – niveaux 5 à 7', u_sophie),
    (wid, u_hugo, scaf, mon, mon + 4, 7, null, u_sophie),
    (wid, u_karim, scaf, mon, mon + 9, 8, 'Chef d''équipe unité 4', u_sophie),
    (wid, u_nadia, calo, mon, mon + 9, 7, null, u_sophie);

  -- Codes PIN kiosque et tablette de la base vie (jeton connu pour le tournage).
  insert into clockifai_private.member_pins (workspace_id, user_id, pin_hash) values
    (wid, u_camille, extensions.crypt('1234', extensions.gen_salt('bf', 8))),
    (wid, u_leo, extensions.crypt('2468', extensions.gen_salt('bf', 8)));
  insert into public.kiosk_devices (workspace_id, name, token_hash, created_by)
  values (wid, 'Tablette base vie', encode(extensions.digest('kio_demo_tablette_base_vie_2026', 'sha256'), 'hex'), u_sophie);
end $$;
SQL

echo "[demo] studio d'Alex (vidéo 6, Claude Code)"
$PSQL <<'SQL'
do $$
declare
  u_alex uuid := (select id from auth.users where email = 'alex@demo.clockifai.fr');
  wid uuid := (select default_workspace_id from public.profiles where id = (select id from auth.users where email = 'alex@demo.clockifai.fr'));
  c_boul uuid; c_cab uuid; p_site uuid; p_rdv uuid; p_int uuid; t_maq uuid; t_reu uuid; t_rec uuid;
  d date; i int;
begin
  update public.workspaces set name = 'Studio Alex', task_creation = 'everyone' where id = wid;
  update public.workspace_members set hourly_rate_cents = 6000 where workspace_id = wid and user_id = u_alex;
  insert into public.clients (workspace_id, name) values (wid, 'Boulangerie Martin (démo)') returning id into c_boul;
  insert into public.clients (workspace_id, name) values (wid, 'Cabinet Dupuis (démo)') returning id into c_cab;
  insert into public.projects (workspace_id, client_id, name, color, hourly_rate_cents) values
    (wid, c_boul, 'Site de la boulangerie', '#F97316', 6500) returning id into p_site;
  insert into public.projects (workspace_id, client_id, name, color, hourly_rate_cents) values
    (wid, c_cab, 'Appli de rendez-vous', '#0EA5E9', 7000) returning id into p_rdv;
  insert into public.projects (workspace_id, name, color, billable_default) values (wid, 'Interne', '#64748B', false)
    returning id into p_int;
  insert into public.tasks (workspace_id, project_id, name) values (wid, p_site, 'Maquettes') returning id into t_maq;
  insert into public.tasks (workspace_id, project_id, name) values (wid, p_site, 'Réunion client') returning id into t_reu;
  insert into public.tasks (workspace_id, project_id, name) values (wid, p_rdv, 'Recette') returning id into t_rec;
  -- Dépôts rattachés à leur projet (« Toujours rattacher ce dépôt à ce projet ») : les sessions de Claude y arrivent.
  insert into public.activity_rules (workspace_id, user_id, match_kind, pattern, project_id) values
    (wid, u_alex, 'repo', 'github.com/studio-alex/site-boulangerie', p_site),
    (wid, u_alex, 'repo', 'github.com/studio-alex/appli-rdv', p_rdv);

  -- Les heures d'Alex, jours ouvrés des deux dernières semaines (celles de Claude : demo/claude-history.mjs).
  for i in 1..13 loop
    d := current_date - i;
    continue when extract(isodow from d) > 5;
    insert into public.time_entries (workspace_id, user_id, project_id, task_id, description, start_at, end_at, billable, hourly_rate_cents) values
      (wid, u_alex, p_int, null, 'Courriels et devis',
       (d + time '08:30') at time zone 'Europe/Paris', (d + time '09:00') at time zone 'Europe/Paris', false, 6000),
      (wid, u_alex, case when i % 2 = 0 then p_site else p_rdv end, case when i % 2 = 0 then t_maq else t_rec end,
       case when i % 2 = 0 then 'Maquettes de la page d''accueil' else 'Recette de la prise de rendez-vous' end,
       (d + time '09:00') at time zone 'Europe/Paris', (d + time '12:00') at time zone 'Europe/Paris', true,
       case when i % 2 = 0 then 6500 else 7000 end);
    if extract(isodow from d) = 2 then
      insert into public.time_entries (workspace_id, user_id, project_id, task_id, description, start_at, end_at, billable, hourly_rate_cents)
      values (wid, u_alex, p_site, t_reu, 'Point avec Mme Martin',
              (d + time '14:00') at time zone 'Europe/Paris', (d + time '15:00') at time zone 'Europe/Paris', true, 6500);
    end if;
  end loop;
end $$;
SQL
node demo/claude-history.mjs
echo "[demo] prêt"
