# Image du service `web` (profil prod) : build Flutter web de production servi par Caddy.
# Construite par `make prod-up` ; aucun SDK Flutter n'est nécessaire sur le serveur.
# Les URLs et la clé anon sont figées dans le bundle à la compilation (--dart-define) :
# toute modification de SUPABASE_PUBLIC_URL / POWERSYNC_PUBLIC_URL / ANON_KEY impose un rebuild.

# Même version que .fvmrc (les images Flutter publiques ne suivent pas toutes les versions).
ARG FLUTTER_VERSION=3.47.0
ARG FLUTTER_SHA256=26cd99d3d94b1367e6b50535a18aeef0282c10a535bbe3ec493534dcdab75296

FROM debian:bookworm-slim AS sdk
ARG FLUTTER_VERSION
ARG FLUTTER_SHA256
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSLo /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory /opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH
RUN flutter config --no-analytics --no-cli-animations --enable-web && flutter precache --web

FROM sdk AS build
WORKDIR /app
COPY . .
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY
ARG POWERSYNC_URL
# Vide : l'app web appelle Flask sur sa propre origine (/api proxifié par Caddy).
ARG SERVICES_URL=
# Mêmes étapes que `make app-get` + `make app-build-web`.
RUN flutter pub get \
 && dart run build_runner build --delete-conflicting-outputs \
 && dart run powersync:setup_web --no-worker \
 && dart compile js -O4 -o web/powersync_db.worker.js tool/powersync_worker.dart \
 && rm -f web/powersync_db.worker.js.deps web/powersync_db.worker.js.map \
 && flutter build web --release \
      --dart-define=SUPABASE_URL="$SUPABASE_URL" \
      --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
      --dart-define=POWERSYNC_URL="$POWERSYNC_URL" \
      --dart-define=SERVICES_URL="$SERVICES_URL"

FROM caddy:2-alpine
COPY --from=build /app/build/web /srv/web
