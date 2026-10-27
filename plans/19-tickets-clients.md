# Plan 19 — Tickets clients : Projet › Ticket › Sous-tâches

> Statut : **validé** (27 octobre 2026). Demandé par Yannick : ses clients lui confient des tickets (Jira, Linear),
> qu'il facture ; il ouvre en général une session Claude Code par ticket.

## Ce qui est demandé

```
Projet « Site Acme »
└── ENG-123 · Formulaire de commande        ← tâche = ticket (lien Jira ou Linear)
    ├── Validation des champs               ← sous-tâches = sujets nommés par Claude
    └── Tests du paiement
```

La tâche est la référence du ticket, celle que le client reconnaît sur la facture ; dessous, les sujets de Claude.

## Décisions (27 octobre 2026)

1. **Le ticket est une tâche** (de premier niveau) qui porte l'URL du ticket (`tasks.ticket_url`) et sa clé
   (`tasks.ticket_key`, `ENG-123`), tirée de l'URL. La clé retrouve la tâche : un ticket, une tâche par projet,
   quel que soit son nom (index unique partiel sur `(project_id, lower(ticket_key))`, tâches non supprimées).
2. **Nom de la tâche** : « ENG-123 · Titre », le titre étant tiré par Claude du message du pilote, ou du ticket
   s'il peut le lire (connecteur Jira ou Linear de Claude). Sans titre connu, la clé seule ; un titre donné ensuite
   complète le nom, sauf si la tâche a été renommée à la main (« préciser = renommer », plan 10, D18).
3. **Sous-tâches = sujets de Claude** : avec un ticket, l'objectif nommé par Claude devient une sous-tâche du ticket
   (un seul niveau, plan 16) ; l'étape va dans la description (« Sujet · étape », plan 10, D10). Sans ticket, rien
   ne change (objectif › étape).
4. **Comment Claude l'apprend** :
   - le pilote donne l'URL (ou la clé) dans son message ; Claude la passe à `set_current_task` (`ticket`,
     `ticket_title`) ;
   - sinon, la clé trouvée dans le nom de la branche (`yannick/eng-123-formulaire`, le nom que propose Linear),
     sans Claude ;
   - le ticket vaut pour toute la session, reprises comprises, jusqu'à un autre ticket ; la première entrée de la
     session le prend en entier.
5. **Où va la session** : la tâche du ticket dans le projet du dépôt ; si une tâche de cette clé existe déjà dans un
   autre projet de l'espace (créée à la main quand le client l'a envoyée), la session y va, projet compris. Création
   soumise au même droit que D18 (`workspaces.task_creation`) ; sans projet ni droit, le ticket décrit l'entrée.
6. **Réglage « Tâches de Claude »** : le ticket s'applique en « par objectif » et « par session » ; « Pas de tâche »
   l'ignore.
7. **Confidentialité (D6)** : en plus du nom de tâche, l'URL du ticket (500 caractères) et son titre (80) quittent
   le poste, et seulement par l'outil `set_current_task`.

## Clés reconnues

| Source | Exemple | Clé |
|---|---|---|
| Jira (cloud ou auto-hébergé) | `https://acme.atlassian.net/browse/ENG-123`, `…?selectedIssue=ENG-123` | `ENG-123` |
| Linear | `https://linear.app/acme/issue/ENG-123/formulaire-de-commande` | `ENG-123` |
| GitHub | `https://github.com/acme/site/issues/45` (ou `/pull/45`) | `site#45` |
| Clé seule | `ENG-123` | `ENG-123` (sans lien) |
| Autre URL | | pas de clé : la tâche se retrouve par son URL |

Branche : première sous-chaîne `[A-Za-z][A-Za-z0-9]+-\d+` (mise en majuscules). Même analyse en Dart (app) et en
Python (serveur), testée sur les mêmes cas.

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 Ticket sur la tâche | Migration 0027 (`tasks.ticket_url`, `ticket_key`, index unique partiel), `schema.dart` et Drift ; analyse des URL (Dart) ; Projets : champ « Ticket » dans le dialogue de la tâche, clé et lien ouvrable sur la ligne ; sélecteur de tâche : coller une URL ou une clé retrouve la tâche du ticket ou propose de la créer ; lien du ticket dans le dialogue de l'entrée ; tests | à faire |
| 2 Claude et le ticket | Outil `set_current_task` (`ticket`, `ticket_title`) et sa consigne ; relais par le hook (`session_task` `{…, ticket, ticket_title}`, liste blanche) ; serveur : analyse (Python), ticket collant par session, clé de la branche, tâche par clé (projet du dépôt, sinon tâche existante de l'espace), sujet en sous-tâche, titre qui complète le nom ; tests unitaires, du plugin et d'intégration ; essai réel ; mise à jour du plugin sur chaque poste | à faire |
| 3 Facturation et exports | Facture depuis le temps « par tâche » : une ligne par ticket, sous-tâches cumulées (aujourd'hui une sous-tâche ne remonte pas à sa tâche), libellé « ENG-123 · Titre » et lien ; exports CSV, Excel et PDF : colonne « Ticket » (URL) ; rapport partagé : clé liée ; Rapports groupés par tâche : lien du ticket | à faire |

## Documentation (par lot)

- `docs/architecture/donnees.md` : colonnes `tasks.ticket_url` et `ticket_key` (lot 1).
- `docs/api/openapi.yaml` : charge utile de `session_task` (lot 2).
- `plans/10-suivi-claude-code.md` : D18 complété par le ticket (lot 2).
- Guide : Membre (tickets, Claude Code), Manager (factures et exports) ; `CHANGELOG.md` à chaque lot.
- Vidéos : pas de tournage (choix de Yannick, 27 octobre 2026).
