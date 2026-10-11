# Clockifai — raccourcis. Backend 100 % Docker ; Flutter via fvm ; Python via uv.
.DEFAULT_GOAL := help
COMPOSE := docker compose -f deploy/docker-compose.yml --env-file deploy/.env

help: ## Liste des commandes
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- backend
env: ## Génère deploy/.env avec des secrets aléatoires
	sh deploy/gen-env.sh

up: ## Démarre Supabase + PowerSync + Flask + migrations (dev)
	$(COMPOSE) up -d

prod-up: ## Démarre tout + Caddy HTTPS + sauvegardes (profil prod)
	$(COMPOSE) --profile prod up -d --build

down: ## Arrête les conteneurs (les données restent dans les volumes)
	$(COMPOSE) --profile prod down

logs: ## Suit les logs (SERVICE=powersync pour filtrer)
	$(COMPOSE) logs -f $(SERVICE)

ps: ## État des conteneurs
	$(COMPOSE) ps

migrate: ## Rejoue les migrations SQL (idempotent)
	$(COMPOSE) run --rm migrate

psql: ## Ouvre psql sur la base (rôle postgres)
	$(COMPOSE) exec db psql -U postgres

seed: ## Données de démo dans le workspace d'un utilisateur : make seed EMAIL=vous@exemple.fr
	@test -n "$(EMAIL)" || (echo "Usage : make seed EMAIL=vous@exemple.fr" && exit 1)
	$(COMPOSE) exec -T db psql -U postgres -v email="$(EMAIL)" < deploy/seed-demo.sql

backup: ## Sauvegarde immédiate de Postgres dans deploy/backups
	$(COMPOSE) --profile prod run --rm backup sh /backup.sh

reset: ## DÉTRUIT les données locales (volumes Postgres/stockage) et redémarre
	$(COMPOSE) --profile prod down -v
	rm -rf supabase/docker/volumes/db/data supabase/docker/volumes/storage
	$(COMPOSE) up -d

# ---------------------------------------------------------------- services (Flask, uv)
services-sync: ## Installe l'env Python (uv)
	cd services && uv sync

services-test: ## Tests Flask
	cd services && uv run pytest -q

test-integration: ## Tests d'intégration contre la pile Docker locale (make up d'abord)
	cd services && INTEGRATION=1 uv run pytest -q tests/integration

services-run: ## Flask en local (hors Docker), pointe sur le Postgres du compose
	cd services && set -a && . ../deploy/.env && set +a && \
	DATABASE_URL=postgresql://postgres:$$POSTGRES_PASSWORD@localhost:$$POSTGRES_PORT/$$POSTGRES_DB \
	SUPABASE_URL=http://localhost:8000 SUPABASE_JWT_SECRET=$$JWT_SECRET JOBS_ENABLED=false \
	uv run flask --app app run --debug -p 5050

# ---------------------------------------------------------------- app (Flutter, fvm)
DEFINES ?= --dart-define-from-file=config/local.json

app-config: ## Génère app/config/local.json (URLs + clé anon) depuis deploy/.env
	sh deploy/app-config.sh > app/config/local.json && cat app/config/local.json

app-get: ## pub get + assets web PowerSync + génération Drift
	cd app && fvm flutter pub get && fvm dart run build_runner build
	$(MAKE) app-web-assets

app-web-assets: ## sqlite3.wasm + worker PowerSync compilé avec les dépendances de l'app
	cd app && fvm dart run powersync:setup_web --no-worker && \
	fvm dart compile js -O4 -o web/powersync_db.worker.js tool/powersync_worker.dart && \
	rm -f web/powersync_db.worker.js.deps web/powersync_db.worker.js.map

app-gen: ## Régénère le code Drift / l10n
	cd app && fvm dart run build_runner build

app-web: ## Lance l'app web (Chrome) sur le backend local
	cd app && fvm flutter run -d chrome --web-port 3000 $(DEFINES)

app-build-web: ## Build web de production (servi par Caddy)
	cd app && fvm flutter build web --release $(DEFINES)

app-test: ## Tests Flutter
	cd app && fvm flutter test

app-analyze: ## Analyse statique Dart
	cd app && fvm flutter analyze
