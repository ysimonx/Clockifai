#!/bin/sh
# Crée deploy/.env à partir de .env.example et génère tous les secrets.
#   sh deploy/gen-env.sh            # crée .env (refuse d'écraser un .env existant)
#   sh deploy/gen-env.sh --force    # régénère (ATTENTION : invalide les sessions et la base existante)
set -eu
cd "$(dirname "$0")"

if [ -f .env ] && [ "${1:-}" != "--force" ]; then
  echo ".env existe déjà (utilisez --force pour le régénérer)."
  exit 1
fi
cp .env.example .env

gen_hex()    { openssl rand -hex "$1"; }
gen_base64() { openssl rand -base64 "$1" | tr -d '\n'; }
b64url()     { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
jwt_hs256() { # $1 = payload JSON, $2 = secret
  h=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '%s' "$1" | b64url)
  s=$(printf '%s' "$h.$p" | openssl dgst -binary -sha256 -hmac "$2" | b64url)
  printf '%s.%s.%s' "$h" "$p" "$s"
}
set_var() { # $1 = nom, $2 = valeur
  esc=$(printf '%s' "$2" | sed 's/[&|]/\\&/g')
  if grep -q "^$1=" .env; then
    sed -i.bak "s|^$1=.*|$1=$esc|" .env && rm -f .env.bak
  else
    printf '%s=%s\n' "$1" "$2" >> .env
  fi
}

jwt_secret=$(gen_base64 30)
iat=$(date +%s); exp=$((iat + 5 * 365 * 24 * 3600))
# Charges utiles construites dans des variables : le bash 3.2 de macOS (/bin/sh) casse
# les guillemets imbriqués dans "$(... "..." ...)" et applique l'expansion d'accolades.
anon_payload='{"role":"anon","iss":"supabase","iat":'"$iat"',"exp":'"$exp"'}'
service_payload='{"role":"service_role","iss":"supabase","iat":'"$iat"',"exp":'"$exp"'}'
anon_key=$(jwt_hs256 "$anon_payload" "$jwt_secret")
service_key=$(jwt_hs256 "$service_payload" "$jwt_secret")
set_var JWT_SECRET "$jwt_secret"
set_var ANON_KEY "$anon_key"
set_var SERVICE_ROLE_KEY "$service_key"
set_var POSTGRES_PASSWORD "$(gen_hex 16)"
set_var DASHBOARD_PASSWORD "$(gen_hex 12)"
set_var SECRET_KEY_BASE "$(gen_base64 48)"
set_var REALTIME_DB_ENC_KEY "$(gen_hex 8)"
set_var VAULT_ENC_KEY "$(gen_hex 16)"
set_var PG_META_CRYPTO_KEY "$(gen_base64 24)"
set_var LOGFLARE_PUBLIC_ACCESS_TOKEN "$(gen_base64 24)"
set_var LOGFLARE_PRIVATE_ACCESS_TOKEN "$(gen_base64 24)"
set_var S3_PROTOCOL_ACCESS_KEY_ID "$(gen_hex 16)"
set_var S3_PROTOCOL_ACCESS_KEY_SECRET "$(gen_hex 32)"
set_var MINIO_ROOT_PASSWORD "$(gen_hex 16)"
set_var POOLER_TENANT_ID "clockifai"
# Clockifai
set_var POWERSYNC_DB_PASSWORD "$(gen_hex 16)"
set_var POWERSYNC_STORAGE_PASSWORD "$(gen_hex 16)"
set_var POWERSYNC_ADMIN_TOKEN "$(gen_hex 24)"
set_var SERVICES_SECRET_KEY "$(gen_hex 24)"

echo ".env généré. Éditez ensuite les URLs (SITE_URL, SUPABASE_PUBLIC_URL, API_EXTERNAL_URL, *_DOMAIN) et le SMTP."
