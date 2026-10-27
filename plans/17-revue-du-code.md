# Plan 17 — Revue du code (octobre 2026)

> Statut : **en cours** (27 octobre 2026). Demandé par Yannick après les plans 13, 14 et 16, livrés vite : une revue
> de fond, du nettoyage et du refactoring.

## Méthode

Quatre revues en lecture seule, menées en parallèle : l'app Flutter (Aujourd'hui, coquille, saisie ; puis les autres
pages et les dépôts), le service Flask, puis le plugin Claude Code, les migrations et l'alignement des colonnes
synchronisées. Chaque constat est relu dans le code avant d'être corrigé ; chaque correction de règle a son test.

Vérifié sans constat : `fvm flutter analyze` et ruff propres ; colonnes alignées entre migrations, `schema.dart`,
Drift et `sync-config.yaml` (24 tables) ; plugin en Python 3.9, liste blanche D6 respectée, `PLUGIN_FILES` complet ;
aucune fonction `security definer` sans `search_path`, RLS sur toutes les tables de `public`.

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 Base et serveur | Migration 0022 ; Flask (sessions Claude, exports, assistant) ; serveur MCP du plugin | fait |
| 2 App : bugs | Constats « bug » de l'app ci-dessous | en cours |
| 3 App : nettoyage | Code mort, duplications, découpage de `today_page.dart` | à faire |
| 4 À décider | Constats qui changent une règle ou un montant | à décider avec Yannick |

## Lot 1 — base et serveur (fait)

Migration `0022_review_guards.sql`, tests dans `services/tests/integration/test_review_guards.py` :

- la politique d'une demande d'absence ou d'un solde est celle du workspace (une politique « sans approbation » de
  son propre espace faisait approuver d'office une demande dans l'entreprise) ;
- seul un propriétaire donne ou retire le rôle de propriétaire (un admin promu pouvait supprimer le workspace) ;
  hors admins, ni capacité journalière ni adresse autre que celle du profil ;
- le créateur d'une tâche ne la range pas sous une autre (réservé aux managers, comme la déplacer) ; une sous-tâche
  créée hors ligne sous une tâche supprimée part avec elle ;
- la personne relancée ne fait que marquer la relance vue ;
- un nouveau chronomètre arrête l'ancien même verrouillé (l'insertion échouait, et le connecteur l'abandonnait) ;
- factures et tags ne lient que des lignes de leur workspace ;
- `team_scope_wanted`, `refresh_team_scope`, `user_local_date` ne sont plus appelables en RPC ;
- index : `time_entries(task_id)`, `time_entry_tags(tag_id)`, `code_commits(workspace_id, author_user_id, authored_at)`.

Flask :

- une session Claude déjà tenue par l'agent d'un autre pilote n'est plus recalculée (son id se lit dans
  `code_commits` : un membre pouvait effacer l'usage IA d'un collègue ou renommer ses tâches) ;
- l'auteur d'un commit n'est cherché que parmi les membres du workspace ;
- « une tâche par session » avec des étapes : la tâche de la session est la tâche racine (une sous-tâche prise à sa
  place faisait échouer chaque recalcul) ; une sous-tâche renommée à la main reste celle de l'entrée ;
- exports : bornes et heures dans le fuseau du profil (le conteneur est en UTC : décalage d'une ou deux heures) ; un
  membre exporte aussi le temps de son agent ;
- assistant : un id mal formé donné par Claude revient en erreur d'outil au lieu d'une erreur 500 ;
- `entry_defaults` ignore un projet supprimé ;
- nettoyage : `profiles.user_tz` (trois copies), rôles importés d'`auth.py`, `hash_token` du kiosque,
  `running_timers_summary` et paramètres inutilisés retirés.

Plugin : le serveur MCP lit et écrit en UTF-8 quelle que soit la locale, et survit à une requête inattendue ; le hook
ignore un `tool_input` qui n'est pas un objet.

## Lot 4 — à décider

- **Taux des entrées** : un membre peut changer `hourly_rate_cents` de ses propres entrées par l'API (les exports le
  prennent en premier). Le figer côté serveur suppose de recalculer le taux quand le projet change.
- **« À facturer » et la facture** : le bloc des rapports applique l'arrondi du workspace, la facture créée depuis
  ce bloc facture les durées brutes. Lequel fait foi ?
- **Agenda iCal** : le contrôle d'adresse (pas d'IP privée) résout le nom puis le laisse résoudre à nouveau à la
  connexion ; un DNS complaisant pourrait viser le réseau Docker. Épingler l'adresse vérifiée.
- **Agent désactivé** : son entrée en cours reste ouverte (`process_session` sort sans rien écrire).
- **Sujet sans tâche possible** (création réservée aux managers) : la nouvelle entrée garde la tâche de l'entrée
  précédente de la session.
