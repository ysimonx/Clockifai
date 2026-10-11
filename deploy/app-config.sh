#!/bin/sh
# Écrit sur la sortie standard la config Flutter (--dart-define-from-file) à partir de deploy/.env.
#   sh deploy/app-config.sh > app/config/local.json
# Variables surchargeables : SUPABASE_URL, POWERSYNC_URL, SERVICES_URL
#   (ex. pour un émulateur Android : SUPABASE_URL=http://10.0.2.2:8000).
set -eu
cd "$(dirname "$0")"
get() { grep -E "^$1=" .env | head -1 | cut -d= -f2-; }
anon=$(get ANON_KEY)
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
