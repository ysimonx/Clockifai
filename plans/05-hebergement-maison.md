# Plan 05 — Hébergement de production à la maison (clockifai.kysoe.com)

> Statut : **fait** (en production depuis le 13 octobre 2026). Restent les « Points ouverts ».

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

## Réseau et DNS (fait le 2026-10-13, certificats Let's Encrypt obtenus)

- **Réseau de la Freebox** : `192.168.10.0/24`, Freebox en `192.168.10.254` ; le TP-Link (WAN) y est en `192.168.10.100`.
- **Freebox Pro** (Freebox OS → pare-feu, flux Internet (WAN) → Réseau local (LAN), règle par défaut « Bloquer ») :
  deux règles « Autoriser », TCP, *Port de destination sur la Freebox* 80 (resp. 443), redirection vers
  `192.168.10.100`, *Port de la redirection* 80 (resp. 443). **Laisser vide le « Port source d'origine »** : c'est le
  port aléatoire du client ; le remplir avec 80/443 bloque tout (symptôme : délai dépassé vu d'Internet).
- **TP-Link** (NAT Forwarding → Serveurs virtuels) : TCP 80 et 443 vers `192.168.0.84`. À fixer : bail DHCP du TP-Link
  sur la Freebox (`98:03:8e:99:5e:a5` → `192.168.10.100`) et réservation du PC sur le TP-Link (`fc:aa:14:06:12:52`).
- **DNS OVH** (zone `kysoe.com`) : `clockifai` A → IPv4 publique de la Freebox, `*.clockifai` CNAME → `clockifai.kysoe.com.`
- Diagnostic par maillon : depuis le réseau Freebox, `curl -H 'Host: clockifai.kysoe.com' http://192.168.10.100/` teste
  le TP-Link seul ; check-host.net teste l'IP publique depuis l'étranger. Depuis le LAN, l'IP publique ne répond pas
  (pas de NAT loopback) : c'est attendu, et sans incidence vu de l'extérieur.
- Après des échecs ACME (DNS absent), Caddy espace ses essais : `docker restart edge-caddy` relance immédiatement.

## Exploitation

- Mises à jour : `make deploy HOST=ysimonx@192.168.0.84` (rebuild de l'image web, migrations rejouées au démarrage).
- Logs : `make logs SERVICE=…` sur le serveur ; proxy : `cd ~/edge && docker compose logs -f`.
- Sauvegardes : `~/Clockifai/deploy/backups/` chaque nuit à 3 h, 14 jours ; **à copier hors du PC** (disque, NAS, cloud).
- Studio Supabase : `https://supabase.clockifai.kysoe.com`, identifiants `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` du `.env`.
- Autre application derrière le proxy : la raccorder au réseau `edge` sans publier 80/443, ajouter
  `~/edge/sites/<app>.caddy`, puis `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`.

## Points ouverts

- **Inscriptions fermées** (2026-10-13, après création du compte propriétaire) : `DISABLE_SIGNUP=true`, puis
  `up -d auth`. Les invitations restent possibles : dans GoTrue v2.189.0, seul `POST /signup` teste `DisableSignup`
  (`internal/api/signup.go`), pas `admin/generate_link` ni `verify`. `ENABLE_EMAIL_AUTOCONFIRM=true` faute de SMTP.
- **SMTP** : sans lui, pas d'email de récupération de mot de passe ; les invitations renvoient le lien à l'admin.
  Réglé le 23 octobre 2026 : Mailjet (`in-v3.mailjet.com:587`, expéditeur `clockifai@kysoe.com`, alias de la
  boîte Google Workspace), emails de Flask et d'Auth reçus, puis `ENABLE_EMAIL_AUTOCONFIRM=false`.
- ~~**Studio** exposé sur Internet (protégé par mot de passe)~~ : restreint au réseau local le 23 octobre 2026
  (`STUDIO_ALLOWED_IPS`, défaut `private_ranges`). Docker garde l'adresse d'origine des connexions externes
  (pas de `daemon.json`, IPv4 seulement) et `~/edge` la transmet dans `X-Forwarded-For`. Sur le serveur :
  `STUDIO_ALLOWED_IPS=private_ranges 82.96.171.69/32 84.16.74.153/32` : IP publique de la box (NAT en boucle,
  pas encore vérifié depuis le Wi-Fi sans VPN) et sortie du VPN personnel, par lequel passe le Mac de
  développement. Vérifié : 403 depuis un téléphone en 4G, mot de passe demandé depuis le Mac.
- Applications mobiles : construire avec `SUPABASE_URL=https://supabase.clockifai.kysoe.com`,
  `POWERSYNC_URL=https://sync.clockifai.kysoe.com`, `SERVICES_URL=https://clockifai.kysoe.com`.
