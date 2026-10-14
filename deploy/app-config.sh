#!/bin/sh
# Écrit sur la sortie standard la config Flutter (--dart-define-from-file) à partir de deploy/.env.
#   sh deploy/app-config.sh > app/config/local.json
# Variables surchargeables : SUPABASE_URL, POWERSYNC_URL, SERVICES_URL
#   (ex. pour un émulateur Android : SUPABASE_URL=http://10.0.2.2:8000),
#   ENV_FILE (chemin absolu d'un autre .env, ex. celui du serveur de prod : make app-config-prod).
set -eu
cd "$(dirname "$0")"
env_file=${ENV_FILE:-.env}
get() { grep -E "^$1=" "$env_file" | head -1 | cut -d= -f2-; }
anon=$(get ANON_KEY)
[ -n "$anon" ] || { echo "ANON_KEY introuvable dans $env_file" >&2; exit 1; }
supabase_url=${SUPABASE_URL:-$(get SUPABASE_PUBLIC_URL)}
powersync_url=${POWERSYNC_URL:-$(get POWERSYNC_PUBLIC_URL)}
services_url=${SERVICES_URL:-http://localhost:$(get SERVICES_PORT)}
cat <<JSON
{
  "SUPABASE_URL": "$supabase_url",
  "SUPABASE_ANON_KEY": "$anon",
  "POWERSYNC_URL": "$powersync_url",
  "SERVICES_URL": "$services_url"
}
JSON
