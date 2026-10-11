-- 0000 — Bootstrap (exécuté en tant que supabase_admin, superuser).
-- Idempotent. Variables psql : :'powersync_db_password', :'powersync_storage_password'.
--
-- 1. Rôle de réplication PowerSync (BYPASSRLS : il lit tout, le filtrage se fait dans sync-config.yaml)
-- 2. Publication logique `powersync` sur toutes les tables du schéma public
-- 3. Base + rôle de stockage des buckets PowerSync
-- 4. Schéma technique clockifai_meta (déjà créé par migrate.sh, redit ici pour usage manuel)

create schema if not exists clockifai_meta;

-- 1. Rôle de réplication ------------------------------------------------------
select format('create role powersync_role with replication bypassrls login password %L', :'powersync_db_password')
where not exists (select 1 from pg_roles where rolname = 'powersync_role')
\gexec

select format('alter role powersync_role with password %L', :'powersync_db_password')
\gexec

grant usage on schema public to powersync_role;
grant select on all tables in schema public to powersync_role;
alter default privileges for role postgres in schema public grant select on tables to powersync_role;
alter default privileges for role supabase_admin in schema public grant select on tables to powersync_role;

-- 2. Publication ---------------------------------------------------------------
select 'create publication powersync for tables in schema public'
where not exists (select 1 from pg_publication where pubname = 'powersync')
\gexec

-- 3. Stockage des buckets -------------------------------------------------------
select format('create role powersync_storage with login password %L', :'powersync_storage_password')
where not exists (select 1 from pg_roles where rolname = 'powersync_storage')
\gexec

select format('alter role powersync_storage with password %L', :'powersync_storage_password')
\gexec

select 'create database powersync_storage owner powersync_storage'
where not exists (select 1 from pg_database where datname = 'powersync_storage')
\gexec

-- Vérification : la réplication logique doit être active (image supabase/postgres : oui par défaut).
do $$
begin
  if current_setting('wal_level') <> 'logical' then
    raise exception 'wal_level doit valoir "logical" pour PowerSync (actuel : %)', current_setting('wal_level');
  end if;
end $$;
