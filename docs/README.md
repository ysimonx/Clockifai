# Documentation de Clockifai

Elle décrit l'état actuel du logiciel ; l'historique des décisions est dans [plans/](../plans/) et dans git.
Règle de mise à jour : `CLAUDE.md`, § Documentation. `make docs-check` vérifie la cohérence des routes Flask avec
l'OpenAPI, ainsi que les liens et les scènes vidéo du guide.

| Document | Contenu | Pour qui |
|---|---|---|
| [Guide utilisateur](guide/index.html) | Utiliser Clockifai, une page par rôle, avec les vidéos ; en ligne sur `https://<APP_DOMAIN>/guide/`, en local avec `make docs-serve` (http://localhost:3200/guide/) | Utilisateurs : membres, chefs d'équipe, managers, propriétaires |
| [Vidéos de démonstration](../demo/README.md) | Cinq vidéos sans voix, une par rôle, tournées automatiquement ; publiées avec le guide (`make guide-videos`, `make guide-publish HOST=…`) | Utilisateurs (à voir), développeurs (à tourner) |
| [Exploitation](exploitation.md) | Installer, configurer `deploy/.env`, mettre à jour, sauvegarder, restaurer, surveiller | Administrateur d'une installation |
| [Architecture : composants](architecture/composants.md) | Composants et flux réseau : HTTPS, Caddy et proxy partagé, Kong, Supabase, Postgres, PowerSync, Flask, applications | Développeurs, administrateurs |
| [Architecture : déploiement](architecture/deploiement.md) | Pile locale et production sur serveur partagé : conteneurs, ports, volumes | Développeurs, administrateurs |
| [Architecture : données](architecture/donnees.md) | Schéma relationnel, flux de synchronisation, matrice des droits par rôle | Développeurs |
| [API : présentation](api/README.md) | Authentification, conventions, renvoi vers la description PostgREST | Développeurs, intégrateurs |
| [API : OpenAPI](api/openapi.yaml) | Toutes les routes du service Flask (`/api/…`) | Développeurs, intégrateurs |
| [API : séquences](api/sequences/) | Un diagramme de séquence par parcours : connexion, écriture hors ligne, chronomètres, feuille de temps, absences, invitation, kiosque, export, rapport partagé, facture PDF, barre de menus macOS, Fidwork (prévu) | Développeurs |
| [Plans](../plans/) | Plans validés et décisions, avec leur contexte | Développeurs |
| [Notes de version](../CHANGELOG.md) | Évolutions visibles, version par version | Tous ; texte repris pour TestFlight et Google Play |
