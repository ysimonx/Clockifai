#!/bin/sh
# Applique les migrations SQL de /migrations dans l'ordre lexical.
#
# - Les fichiers *.admin.sql sont exécutés en tant que supabase_admin (superuser) :
#   rôles, publication, base de stockage PowerSync, triggers sur auth.users.
# - Les autres fichiers sont exécutés en tant que postgres (propriétaire du schéma applicatif).
# - Les variables psql suivantes sont disponibles dans les migrations :
#     :'powersync_db_password'  :'powersync_storage_password'
# - Chaque fichier appliqué est mémorisé dans clockifai_meta.schema_migrations.
#
# Utilisé par le conteneur `migrate` (voir docker-compose.yml) ; utilisable aussi à la main :
#   PGHOST=localhost PGPASSWORD=... sh deploy/migrate.sh ../supabase/migrations
set -eu

MIGRATIONS_DIR="${1:-/migrations}"
ADMIN_USER="${ADMIN_USER:-supabase_admin}"
APP_USER="${APP_USER:-postgres}"

psql_as() {
  user="$1"; shift
  psql -X -v ON_ERROR_STOP=1 -U "$user" \
    -v powersync_db_password="${POWERSYNC_DB_PASSWORD:-}" \
    -v powersync_storage_password="${POWERSYNC_STORAGE_PASSWORD:-}" \
    "$@"
}

echo "[migrate] attente de Postgres ($PGHOST:$PGPORT)..."
i=0
until psql_as "$ADMIN_USER" -c 'select 1' >/dev/null 2>&1; do
  i=$((i+1)); [ "$i" -gt 60 ] && { echo "[migrate] Postgres injoignable"; exit 1; }
  sleep 2
done

psql_as "$ADMIN_USER" -q <<'SQL'
create schema if not exists clockifai_meta;
create table if not exists clockifai_meta.schema_migrations (
  filename text primary key,
  applied_at timestamptz not null default now()
);
grant usage on schema clockifai_meta to postgres;
grant all on clockifai_meta.schema_migrations to postgres;
SQL

applied=0
for f in $(ls "$MIGRATIONS_DIR"/*.sql | sort); do
  name=$(basename "$f")
  done_already=$(psql_as "$ADMIN_USER" -tA -c "select 1 from clockifai_meta.schema_migrations where filename = '$name'")
  if [ "$done_already" = "1" ]; then
    continue
  fi
  case "$name" in
    *.admin.sql) user="$ADMIN_USER" ;;
    *)           user="$APP_USER" ;;
  esac
  echo "[migrate] applique $name (en tant que $user)"
  psql_as "$user" -q -f "$f"
  psql_as "$ADMIN_USER" -q -c "insert into clockifai_meta.schema_migrations(filename) values ('$name')"
  applied=$((applied+1))
done

echo "[migrate] terminé : $applied migration(s) appliquée(s)."
