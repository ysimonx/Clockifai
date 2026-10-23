# Regroupement des entrées similaires — plan

> Objectif : dans « Suivi du temps », réunir sur une ligne dépliable les entrées identiques d'une même journée,
> comme Clockify (« Group similar entries »). Utile dès qu'on relance souvent la même activité, et plus encore
> avec les chronomètres simultanés (`05-chronometres-paralleles.md`), qui multiplient les courtes entrées.

## 1. Décision

| Sujet | Choix |
|---|---|
| Critères | Même **jour** (heure locale) et mêmes **description** (sans espaces en bout), **projet**, **tâche**, **tags** (ensemble) et **facturable**, comme Clockify. Le taux horaire et l'auteur n'entrent pas en compte |
| Ligne de groupe | Pastille du nombre d'entrées, description, projet, tags ; plage du premier début à la dernière fin ; **durée cumulée** ; ▶ relance l'activité, **■ Arrêter** si sa tâche tourne déjà (un chronomètre par tâche, `05-chronometres-paralleles.md`) ; un clic sur la ligne ou la pastille déplie ou replie |
| Détail | Entrées en retrait, avec modifier, dupliquer, supprimer ; **pas de ▶** : on relance depuis la ligne du groupe |
| Actions de groupe | **Modifier** description, projet, tâche, tags, facturable de toutes les entrées (pas les horaires) ; **Supprimer** le groupe après confirmation |
| Verrouillage | Une entrée verrouillée (non admin) ou une journée dans la période close : cadenas sur le groupe, actions de groupe désactivées (le serveur les refuserait), détail consultable |
| Entrée seule | Affichée comme avant |
| Réglage | « Regrouper les entrées similaires », **activé par défaut**, dans Paramètres, **mémorisé sur l'appareil** (`shared_preferences`, comme la langue) : ni colonne ni synchronisation |
| Hors périmètre | Rapport détaillé : non regroupé, il est fait pour tout montrer |

Aucune migration, aucun changement de synchronisation ni de serveur.

## 2. Réalisation

- `features/time_entries/entry_groups.dart` : `similarityKey()` et `groupSimilar()` (fonction pure ; ordre conservé :
  groupe placé à son entrée la plus récente, entrées les plus récentes d'abord), `EntryGroup` (durée, plage, verrou).
- `TimeEntryRepository.updateMany()` / `deleteMany()` : même règles que `update()` / `delete()`, en une transaction.
- `time_entries_page.dart` : `_DayCard` affiche des groupes si le réglage est actif ; `EntryGroupTile` (état déplié
  propre au groupe, clé = jour + critères) ; « Continuer » factorisé entre ligne simple et groupe.
- `entry_group_dialog.dart` : modification de groupe (description, projet, tâche, tags, facturable), mêmes contrôles
  du workspace que le dialogue d'entrée (projet / description obligatoires) ; le taux horaire suit le nouveau projet.
- `core/display_prefs.dart` : `DisplayPrefs` (ChangeNotifier) fourni par Provider ; interrupteur dans Paramètres.
- Libellés FR / EN ; tests : regroupement (critères, ordre, totaux) et dépôt (`updateMany`, `deleteMany`).
