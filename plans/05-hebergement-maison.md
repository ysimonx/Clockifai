# Plan 05 — Hébergement de production à la maison (clockifai.kysoe.com)

## Contexte

- Serveur : PC Ubuntu `pcyannick` (192.168.0.84, 8 cœurs, 31 Go, Docker), accès SSH `ysimonx`.
- Réseau : Internet → **Freebox Pro** (IPv4 fixe Free Pro) → **routeur Wi-Fi** (NAT, LAN 192.168.0.0/24, passerelle 192.168.0.1) → PC. Double NAT.
- Le PC héberge **plusieurs applications Docker** (soclea, cvad-audit, Portainer…) ; d'autres passeront en production.
- Ports déjà pris sur l'hôte : 5432, 8000, 8025, 8080, 8443, 9000, 9001, 9443, 4443… (80 et 443 libres).

## Décisions

1. **Reverse proxy partagé** (`~/edge`, modèle dans `deploy/edge/`) : un seul Caddy détient 80/443 et obtient
   les certificats Let's Encrypt de toutes les applications ; chacune s'y raccorde par le réseau Docker externe `edge`
   et un fichier `sites/<app>.caddy`.
2. **Aucun port publié par la pile Clockifai** : `deploy/docker-compose.edge.yml`, copié sur le serveur en
   `deploy/docker-compose.override.yml` (non versionné, pris en compte par le Makefile), retire les ports de Kong,
   Supavisor, PowerSync, Flask et du Caddy interne. Plus de conflit avec les autres piles et rien d'exposé sur le LAN.
3. **Caddy interne en HTTP** (`SITE_SCHEME=http`) : il garde le routage par nom d'hôte (app → web + /api, supabase →
   Kong/Studio, sync → PowerSync) ; le proxy partagé ne fait que le TLS et transmet les trois noms à `clockifai-web:80`.
   Sans surcharge, le profil prod reste autonome (HTTPS direct sur 80/443).
4. **Trois noms sous `kysoe.com`** (DNS chez OVH ; `clockif.ai` n'est pas enregistré) : `clockifai.kysoe.com`
   (application + /api), `supabase.clockifai.kysoe.com` (Auth/REST/Realtime/Storage, Studio sous mot de passe),
   `sync.clockifai.kysoe.com` (PowerSync). Deux enregistrements DNS suffisent (le nom + un joker `*.clockifai`).
   Les URLs sont figées dans le bundle web : tout changement de nom dans `deploy/.env` impose `make prod-up`.
5. **Build Flutter web dans Docker** (`app/Dockerfile`, SDK officiel 3.47.0 vérifié par SHA-256 — les images
   Flutter publiques ne vont pas jusqu'à 3.47) : `make prod-up` compile l'app avec les URLs publiques et la clé anon
   du `.env` du serveur. Aucun SDK Flutter sur le serveur ni sur le poste qui déploie.
6. **Déploiement par rsync** (`make deploy HOST=ysimonx@192.168.0.84`) : le dépôt GitHub est privé et le serveur n'a
   pas d'identifiants ; on copie les fichiers suivis (jamais `deploy/.env` ni les données), puis `make prod-up`.
   Les secrets de production sont générés sur le serveur (`make env`) et n'en sortent pas.

## Mise en place sur le serveur (fait le 2026-10-13)

```bash
make deploy HOST=ysimonx@192.168.0.84            # depuis le Mac ; la 1re fois, prod-up échoue faute de .env
cd ~/Clockifai && make env                         # secrets neufs
# deploy/.env : SITE_URL, SUPABASE_PUBLIC_URL, API_EXTERNAL_URL (/auth/v1), POWERSYNC_PUBLIC_URL,
#               ADDITIONAL_REDIRECT_URLS, CORS_ORIGINS, APP_DOMAIN, SUPABASE_DOMAIN, SYNC_DOMAIN
cp deploy/docker-compose.edge.yml deploy/docker-compose.override.yml
docker network create edge
cp -r deploy/edge ~/edge                           # puis noms réels dans ~/edge/sites/clockifai.caddy
make prod-up
cd ~/edge && docker compose up -d
```

## Reste à faire hors serveur

1. **Zone DNS `kysoe.com` chez OVH** (Web Cloud → Noms de domaine → kysoe.com → Zone DNS → Ajouter une entrée) :
   `clockifai` en A vers l'IPv4 publique de la Freebox, et `*.clockifai` en CNAME vers `clockifai.kysoe.com.`
   (ou en A vers la même IP).
2. Contrôle : `dig +short sync.clockifai.kysoe.com` doit renvoyer l'IP publique.
3. **Freebox Pro** (Freebox OS → Paramètres → Mode avancé) : bail DHCP fixe pour le routeur Wi-Fi, puis redirection
   des ports TCP 80 et 443 (et UDP 443 pour HTTP/3) vers l'IP WAN du routeur, ou DMZ vers cette IP. Vérifier que
   l'accès distant à Freebox OS n'utilise pas 80/443.
4. **Routeur Wi-Fi** : réservation DHCP 192.168.0.84 pour le PC, redirection TCP 80/443 (+ UDP 443) vers 192.168.0.84.
5. Dès que le DNS et les ports sont en place, le proxy obtient les certificats seul ; ses tentatives s'espaçant après
   des échecs, `docker restart edge-caddy` déclenche un nouvel essai immédiat.
   Depuis le LAN, si `clockifai.kysoe.com` ne répond pas (pas de NAT loopback à travers le double NAT), surcharger le DNS
   local vers 192.168.0.84.

## Exploitation

- Mises à jour : `make deploy HOST=ysimonx@192.168.0.84` (rebuild de l'image web, migrations rejouées au démarrage).
- Logs : `make logs SERVICE=…` sur le serveur ; proxy : `cd ~/edge && docker compose logs -f`.
- Sauvegardes : `~/Clockifai/deploy/backups/` chaque nuit à 3 h, 14 jours ; **à copier hors du PC** (disque, NAS, cloud).
- Studio Supabase : `https://supabase.clockifai.kysoe.com`, identifiants `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` du `.env`.
- Autre application derrière le proxy : la raccorder au réseau `edge` sans publier 80/443, ajouter
  `~/edge/sites/<app>.caddy`, puis `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`.

## Points ouverts

- **Inscriptions** : `DISABLE_SIGNUP=false` et `ENABLE_EMAIL_AUTOCONFIRM=true` (pas de SMTP) : n'importe qui peut créer
  un compte. Une fois le compte administrateur créé, passer `DISABLE_SIGNUP=true` (les invitations passent par l'API
  d'administration GoTrue), ou configurer un SMTP et `ENABLE_EMAIL_AUTOCONFIRM=false`.
- **SMTP** : sans lui, pas d'email de récupération de mot de passe ; les invitations renvoient le lien à l'admin.
- **Studio** exposé sur Internet (protégé par mot de passe) : le restreindre au LAN si inutile à distance.
- Applications mobiles : construire avec `SUPABASE_URL=https://supabase.clockifai.kysoe.com`,
  `POWERSYNC_URL=https://sync.clockifai.kysoe.com`, `SERVICES_URL=https://clockifai.kysoe.com`.
