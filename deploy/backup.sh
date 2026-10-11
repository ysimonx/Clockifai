#!/bin/sh
# Sauvegarde Postgres (pg_dump format custom, compressé) avec rétention.
#
#   sh backup.sh          # une sauvegarde immédiate
#   sh backup.sh loop     # boucle : une sauvegarde par jour à BACKUP_HOUR (conteneur `backup`)
#
# Restauration (base vide, stack arrêtée sauf db) :
#   docker compose exec -T db pg_restore -U supabase_admin -d postgres --clean --if-exists < backups/clockifai-YYYYMMDD-HHMMSS.dump
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
HOUR="${BACKUP_HOUR:-03}"

do_backup() {
  mkdir -p "$BACKUP_DIR"
  stamp=$(date +%Y%m%d-%H%M%S)
  out="$BACKUP_DIR/clockifai-$stamp.dump"
  echo "[backup] $out"
  pg_dump --format=custom --compress=6 --no-owner --no-privileges \
    --exclude-schema='_realtime' --exclude-schema='_analytics' \
    --file="$out" "$PGDATABASE"
  # Base de stockage PowerSync : inutile à sauvegarder (reconstruite par réplication).
  find "$BACKUP_DIR" -name 'clockifai-*.dump' -mtime +"$KEEP_DAYS" -delete
  echo "[backup] ok, rétention $KEEP_DAYS jours"
}

if [ "${1:-}" = "loop" ]; then
  while true; do
    if [ "$(date +%H)" = "$HOUR" ]; then
      do_backup || echo "[backup] ECHEC"
      sleep 3600
    fi
    sleep 300
  done
else
  do_backup
fi
