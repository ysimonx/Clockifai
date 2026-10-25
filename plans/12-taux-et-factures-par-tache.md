# Plan 12 — Taux des entrées et factures détaillées par tâche

> Statut : **fait** (25 octobre 2026). Pistes : « Suites ».

## Constat

Une facture de cvad sortait en deux lignes, dont 2,11 h sans taux. Chaque entrée garde le taux applicable à sa
saisie (`time_entries.hourly_rate_cents`, posé par l'app, le kiosque et le serveur pour les agents). Les quatre
entrées du 23 octobre avaient été saisies avant que le projet ait son taux (142,85 €/h) : elles avaient gardé
« pas de taux », et la facture, qui regroupe par (projet, taux), les mettait à part et à 0 €. L'entrée de Claude
du 24 octobre, saisie après, avait le bon taux.

Par ailleurs, une facture ne montrait qu'une ligne par projet. Depuis que Claude nomme les tâches de ses sessions
(plan 10, D18), le détail du travail est dans les tâches.

## Décisions

- **D1. Une entrée sans taux prend le taux actuel** : celui du projet, sinon celui du membre, à la lecture. La
  même règle vaut pour les factures (`createInvoiceFromTime`), les rapports (`CatalogController.entryRate`) et
  les exports Flask (`coalesce` dans `_detailed_rows`). Une entrée qui a un taux le garde.
- **D2. Changer un taux propose de l'appliquer aux entrées non facturées**, comme Clockify. Au changement du taux
  d'un projet : « Appliquer le nouveau taux ? » pour les entrées du projet qui en ont un autre ; à celui d'un
  membre : pour ses entrées sur les projets sans taux. « Seulement les nouvelles » garde l'instantané. Ne sont
  jamais touchées : les entrées supprimées ou d'une facture non annulée ; hors admin, les entrées verrouillées,
  antérieures à `lock_entries_before` ou d'une période approuvée (comme `time_entries_guard`, qui les refuserait).
  L'écriture passe par la base locale, comme toute modification d'entrée (pas de RPC).
- **D3. « Détailler par tâche »** dans la création d'une facture : une ligne par (projet, tâche, taux),
  « Projet — Tâche » ; le temps sans tâche (ou d'une tâche supprimée) reste sur la ligne « Projet », en tête du
  projet, puis les tâches par ordre alphabétique. Décoché par défaut à la livraison, **coché par défaut** depuis
  le 25 octobre au soir, à la demande de Yannick : on facture d'abord par tâche, la facture par projet reste à
  un clic. La case n'agit que sur les entrées qui ont une tâche : une description (« GOT-344… ») n'en tient pas
  lieu.

Les deux premières décisions vont ensemble : D1 répare les entrées saisies sans taux, D2 traite les changements
de taux, qu'un repli ne peut pas voir (l'entrée a déjà un taux, l'ancien).

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 | D1 (app, factures, exports), D2 (dialogues des projets et des membres, `rerateableEntries`, `setEntryRates`), D3 (case de la nouvelle facture), tests de dépôt et d'intégration, guide, API, données | fait |

## Suites

- Un taux « IA » par projet, distinct du taux du projet, pour facturer autrement le temps de Claude (plan 10,
  § 11, Factures).
- Retenir le choix « Détailler par tâche » par client.
- Une ligne de 0,00 h (tâche de quelques secondes) reste sur la facture : la retirer à la main.
