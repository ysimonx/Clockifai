# Clockifai — raccourcis. Backend 100 % Docker ; Flutter via fvm ; Python via uv.
.DEFAULT_GOAL := help
# deploy/docker-compose.override.yml (non versionné) : réglages propres au serveur,
# ex. copie de docker-compose.edge.yml derrière un reverse proxy partagé.
COMPOSE := docker compose -f deploy/docker-compose.yml $(if $(wildcard deploy/docker-compose.override.yml),-f deploy/docker-compose.override.yml) --env-file deploy/.env

help: ## Liste des commandes
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-27s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- backend
env: ## Génère deploy/.env avec des secrets aléatoires
	sh deploy/gen-env.sh

up: ## Démarre Supabase + PowerSync + Flask + migrations (dev)
	$(COMPOSE) up -d

prod-up: ## Démarre tout + Caddy HTTPS + sauvegardes (profil prod, compile l'app web)
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
	$(COMPOSE) --profile prod run --rm --entrypoint sh backup /backup.sh

reset: ## DÉTRUIT les données locales (volumes Postgres/stockage) et redémarre
	$(COMPOSE) --profile prod down -v
	rm -rf supabase/docker/volumes/db/data supabase/docker/volumes/storage
	$(COMPOSE) up -d

DEPLOY_DIR ?= Clockifai
.PHONY: deploy   # homonyme du dossier deploy/
deploy: ## Copie le dépôt (sans .env ni données) sur un serveur et relance la prod : make deploy HOST=user@ip
	@test -n "$(HOST)" || (echo "Usage : make deploy HOST=user@ip [DEPLOY_DIR=Clockifai]" && exit 1)
	git ls-files -co --exclude-standard | while read -r f; do [ -e "$$f" ] && echo "$$f"; done \
	  | rsync -az --files-from=- . $(HOST):$(DEPLOY_DIR)/
	ssh $(HOST) 'cd $(DEPLOY_DIR) && make prod-up'

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
	@mkdir -p app/config
	sh deploy/app-config.sh > app/config/local.json && cat app/config/local.json

app-config-prod: ## Génère app/config/prod.json depuis le .env du serveur : make app-config-prod HOST=user@ip
	@test -n "$(HOST)" || (echo "Usage : make app-config-prod HOST=user@ip [DEPLOY_DIR=Clockifai]" && exit 1)
	@mkdir -p app/config
	@# Seules les valeurs publiques quittent le serveur (la clé anon est déjà dans le bundle web).
	@tmp=$$(mktemp) && trap 'rm -f "$$tmp" "$$tmp.json"' EXIT && \
	  ssh $(HOST) "grep -E '^(ANON_KEY|SUPABASE_PUBLIC_URL|POWERSYNC_PUBLIC_URL|APP_DOMAIN)=' $(DEPLOY_DIR)/deploy/.env" > "$$tmp" && \
	  ENV_FILE="$$tmp" SERVICES_URL="https://$$(grep '^APP_DOMAIN=' "$$tmp" | cut -d= -f2-)" \
	  sh deploy/app-config.sh > "$$tmp.json" && mv "$$tmp.json" app/config/prod.json
	cat app/config/prod.json

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

app-macos: ## Lance « Clockifai Dev » sur macOS (pile locale, icône dans la barre de menus)
	cd app && fvm flutter run -d macos $(DEFINES)

app-build-macos: ## Construit « Clockifai » pour macOS, branchée sur la prod (app/config/prod.json)
	@test -f app/config/prod.json || (echo "app/config/prod.json manquant : make app-config-prod HOST=user@ip" && exit 1)
	cd app && fvm flutter build macos --release --dart-define-from-file=config/prod.json
	@echo "→ app/build/macos/Build/Products/Release/Clockifai.app (make app-install-macos pour l'installer)"

APPLE_TEAM ?= 9SGKL7VUD3
app-dist-macos: ## « Clockifai » signée Developer ID et notarisée : zip pour d'autres Mac (compte Xcode ou clé d'API)
	APPLE_TEAM=$(APPLE_TEAM) sh app/tool/macos_dist.sh notarize

app-dist-macos-testflight: ## « Clockifai » pour Mac : envoi à App Store Connect puis TestFlight (compte Xcode ou clé d'API)
	APPLE_TEAM=$(APPLE_TEAM) sh app/tool/macos_dist.sh testflight

# iOS et Android : Debug = « Clockifai Dev » (pile locale), Release = « Clockifai » (prod). plans/07-ios-android.md
IOS_SIMULATOR ?= iPhone 18 Pro
app-ios: ## Lance « Clockifai Dev » sur le simulateur iOS (IOS_SIMULATOR=…), pile locale
	xcrun simctl boot "$(IOS_SIMULATOR)" 2>/dev/null || true
	open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true   # Xcode 27 : DeviceHub
	cd app && fvm flutter run -d "$(IOS_SIMULATOR)" $(DEFINES)

app-dist-ios: ## « Clockifai » pour iPhone : envoi à App Store Connect puis TestFlight (compte Xcode ou clé d'API)
	APPLE_TEAM=$(APPLE_TEAM) sh app/tool/ios_dist.sh

app-dist-testflight: app-dist-ios app-dist-macos-testflight ## iPhone puis Mac vers TestFlight, en une commande

ANDROID_HOME ?= $(HOME)/Library/Android/sdk
ADB := $(ANDROID_HOME)/platform-tools/adb
ANDROID_AVD ?= $(shell $(ANDROID_HOME)/emulator/emulator -list-avds 2>/dev/null | grep -v '|' | head -1)
app-android-emulator: ## Démarre l'émulateur Android (ANDROID_AVD=…)
	$(ANDROID_HOME)/emulator/emulator -avd $(ANDROID_AVD) >/dev/null 2>&1 &
	$(ADB) wait-for-device

app-android: ## Lance « Clockifai Dev » sur Android (émulateur ou téléphone branché), pile locale via adb reverse
	@$(ADB) get-state >/dev/null 2>&1 || (echo "Aucun appareil : make app-android-emulator, ou branchez un téléphone" && exit 1)
	@# localhost:8000/8080/5050 (et 3200, guide de make docs-serve) de l'appareil = ceux du Mac : la même config locale que le web et macOS.
	for p in 8000 8080 5050 3200; do $(ADB) reverse tcp:$$p tcp:$$p; done
	cd app && fvm flutter run -d $$($(ADB) get-serialno) $(DEFINES)

app-android-keystore: ## Crée la clé d'envoi Google Play (une fois, hors dépôt ; à sauvegarder)
	sh app/tool/android_keystore.sh

app-dist-android: ## « Clockifai » pour Google Play : app bundle (.aab) de production signé
	sh app/tool/android_dist.sh

app-install-macos: ## Copie « Clockifai » (prod) dans /Applications
	@test -d app/build/macos/Build/Products/Release/Clockifai.app || (echo "Lancer d'abord make app-build-macos" && exit 1)
	rm -rf /Applications/Clockifai.app
	ditto app/build/macos/Build/Products/Release/Clockifai.app /Applications/Clockifai.app

app-build-web: ## Build web local (en prod, l'image du service web le compile elle-même)
	cd app && fvm flutter build web --release $(DEFINES)

app-test: ## Tests Flutter
	cd app && fvm flutter test

app-analyze: ## Analyse statique Dart
	cd app && fvm flutter analyze

# ---------------------------------------------------------------- documentation
docs-check: ## Contrôle la doc : routes Flask ↔ docs/api/openapi.yaml, liens et scènes vidéo du guide, statuts des plans
	cd services && uv run pytest -q tests/test_openapi.py
	uv run --no-project python docs/check.py

docs-serve: ## Sert le guide comme en prod (Caddy, saut dans les vidéos) : http://localhost:3200/guide/
	docker run --rm -p 3200:80 -v "$(CURDIR)/docs/guide:/srv/guide:ro" caddy:2-alpine caddy file-server --root /srv --listen :80

guide-videos: ## Copie les vidéos tournées (demo/out) et leurs chapitres dans docs/guide/videos
	mkdir -p docs/guide/videos
	cp demo/out/*.mp4 docs/guide/videos/
	for f in demo/out/*.chapters.json; do [ ! -e "$$f" ] || cp "$$f" docs/guide/videos/; done

guide-publish: ## Envoie les vidéos du guide sur le serveur : make guide-publish HOST=user@ip
	@test -n "$(HOST)" || (echo "Usage : make guide-publish HOST=user@ip [DEPLOY_DIR=Clockifai]" && exit 1)
	@ls docs/guide/videos/*.mp4 >/dev/null 2>&1 || (echo "Aucune vidéo dans docs/guide/videos : make guide-videos d'abord" && exit 1)
	ssh $(HOST) 'mkdir -p $(DEPLOY_DIR)/docs/guide/videos'
	rsync -az --delete docs/guide/videos/ $(HOST):$(DEPLOY_DIR)/docs/guide/videos/
