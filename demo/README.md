# Vidéos de démonstration

Cinq vidéos sans voix, avec des bandeaux explicatifs incrustés, tournées automatiquement
dans un navigateur (Playwright) sur la pile locale :

| Vidéo | Personne | Ce qu'elle montre |
|---|---|---|
| `1-camille-membre.mp4` | Camille, membre | Saisie après coup et chronomètre, tâche créée à la volée, feuille de temps et soumission, planning, absences, rapports personnels, hors ligne, mobile |
| `2-karim-chef-equipe.mp4` | Karim, chef de l'équipe « Unité 4 » | Pointage d'équipe, saisie pour une collègue, approbation des feuilles de temps et des absences, rapports limités à son équipe |
| `3-julien-manager.mp4` | Julien, conducteur de travaux, manager | Toute l'entreprise : équipe et taux, approbation d'une feuille et d'une absence hors de l'équipe de Karim, affectation au planning, rapports et export Excel, budgets, réglages en lecture seule |
| `4-sophie-gestion-workspace.mp4` | Sophie, propriétaire | Rôles, groupes, chefs d'équipe, invitations, règles (saisie pour autrui, verrouillage, arrondi), projets, absences, planning, rapports, factures, kiosque |
| `5-admin-installation.mp4` | Administrateur de l'installation | Supabase Studio (comptes, données, SQL), paramétrage `deploy/.env`, commandes d'exploitation, récapitulatif des rôles |

## Tourner

```bash
make up                         # pile Docker démarrée
make app-build-web              # build web de production à jour
cd demo && npm install
node record.mjs                 # les 5 vidéos → demo/out/*.mp4
node record.mjs 2               # une seule vidéo
DEMO_FAST=1 node record.mjs 1   # répétition rapide, sans vidéo, pour mettre au point un scénario
```

Avant chaque vidéo, `prepare-demo.sh` recrée l'entreprise fictive « Échafaudages du Nord »
(comptes `*@demo.clockifai.fr`, mot de passe `Demo-2026-clockifai`). Ces comptes servent aussi
à essayer l'app à la main. `sh prepare-demo.sh --clean-test-accounts` supprime en plus les comptes
laissés par les tests automatiques.

L'app est servie depuis `app/build/web` sur le port **3100** (le 3000 sert au `flutter run` de
développement). Une scène qui échoue est notée, une capture est enregistrée dans `demo/out/echec-*.png`
et le tournage continue.

Sous macOS, `record.mjs` réveille l'écran et empêche la mise en veille (`caffeinate`) le temps du
tournage. Sur batterie, capot fermé, le Mac s'endort malgré tout et les vidéos se remplissent de temps
morts : garder l'écran ouvert, ou brancher le secteur.

## Organisation

| Fichier | Rôle |
|---|---|
| `record.mjs` | Lance les vidéos, encode en MP4 (ffmpeg embarqué), assemble les parties |
| `videos/*.mjs` | Un scénario par vidéo : scènes, bandeaux, actions |
| `lib/helpers.mjs` | Pilotage de Flutter web par son arbre d'accessibilité, curseur, enregistrement |
| `lib/overlay.js` | Incrustations : bandeau, carte titre, panneau de code, curseur visible |
| `prepare-demo.sh` | Données de démonstration rejouables |
| `serve.mjs` | Petit serveur du build web |
