# Plan 06 — Version macOS et icône de la barre de menus

## Besoin

Une version macOS de l'app avec, comme Clockify, une petite icône en haut à droite de l'écran (barre de menus)
qui permet de démarrer le chronomètre sans ouvrir l'application, ou d'ouvrir l'application complète.

## Décisions

1. **Cible macOS de l'app Flutter existante** (`app/macos`, `flutter create --platforms=macos`, identifiant
   `fr.clockifai.clockifai` comme iOS). Même code, même base locale PowerSync, même sync. macOS 12 minimum.
   Flutter 3.47 intègre les plugins par Swift Package Manager : pas de CocoaPods.
2. **Panneau natif SwiftUI**, pas une deuxième fenêtre Flutter : le multi-fenêtre Flutter est encore expérimental et
   un second moteur ouvrirait une seconde connexion PowerSync. `NSStatusItem` + `NSPopover`
   (`macos/Runner/MenuBarController.swift`, `MenuBarView.swift`).
3. **Le panneau n'a pas accès aux données.** `MacMenuBar` (`lib/features/timer/menu_bar.dart`, monté dans
   `MaterialApp.builder`) lui envoie l'état par le canal `clockifai/menu_bar` (`update` : connecté, chronomètre en
   cours, 5 entrées récentes, projets actifs, libellés traduits par l'ARB) et exécute ses commandes sur la base locale
   (`start`, `stop`, `setDescription`, `setProject`, `continue`), avec les mêmes règles que la barre du chronomètre
   (`timer_rules.dart` : projet / description obligatoires). Un message d'erreur revient au panneau. Un état identique
   au précédent n'est pas renvoyé (la sync notifie souvent sans rien changer).
4. **Contenu du panneau** : description, projet (menu), temps écoulé, bouton démarrer / arrêter ; entrées récentes
   (une par description / projet / tâche, `TimeEntryRepository.watchRecent`) relancées d'un clic ; « Ouvrir Clockifai »
   (et le bouton ⤢) affiche la fenêtre principale ; « Quitter ». Clic droit sur l'icône : ouvrir / quitter.
   Le temps écoulé s'affiche à côté de l'icône tant qu'un chronomètre tourne.
5. **Fermer la fenêtre ne quitte pas l'app** (`applicationShouldTerminateAfterLastWindowClosed` = false, fenêtre non
   libérée) : le moteur Flutter, la sync et l'icône restent actifs ; le Dock ou le panneau rouvrent la fenêtre.
   Taille de fenêtre mémorisée (1200 × 800 au premier lancement, pour le menu latéral).
6. **Deux applications, développement et production**, installables côte à côte (conditions `[config=Debug]` dans
   `Configs/AppInfo.xcconfig`) :

   | Build | Nom | Identifiant | Backend |
   |---|---|---|---|
   | Debug (`make app-macos`) | Clockifai Dev | `fr.clockifai.clockifai.dev` | pile locale (`app/config/local.json`) |
   | Release (`make app-build-macos`) | Clockifai | `fr.clockifai.clockifai` | clockifai.kysoe.com (`app/config/prod.json`) |

   Identifiants distincts = bacs à sable distincts : base locale et session ne se mélangent jamais.
   `make app-config-prod HOST=ysimonx@192.168.0.84` lit sur le serveur les seules valeurs publiques
   (`ANON_KEY`, URLs publiques, `APP_DOMAIN`) ; `SERVICES_URL` = `https://clockifai.kysoe.com` (Caddy route `/api`).
7. **Bac à sable** : réseau sortant, dossier Téléchargements (exports, factures) et fichiers choisis par l'utilisateur.
   `NSAllowsLocalNetworking` pour le backend local en HTTP. Schéma `clockifai://` déclaré pour les liens de connexion.
8. **Distribution signée et notarisée** (`make app-dist-macos`, `app/tool/macos_dist.sh`) : archive Xcode avec
   l'équipe `9SGKL7VUD3` et le runtime renforcé, export `developer-id` envoyé au service de notarisation, puis
   `-exportNotarizedApp` (ticket agrafé) et zip `app/build/macos/Clockifai-<version>.zip`. Tout passe par le compte
   ajouté dans Xcode (`-allowProvisioningUpdates` crée les certificats) : ni mot de passe ni clé d'API dans le dépôt.
   Les builds locaux (`make app-macos`, `make app-build-macos`) restent en signature locale, sans dépendre du compte.
   Pas de TestFlight : il ne concerne que les apps publiées par l'App Store. Hors App Store, Developer ID +
   notarisation suffisent (premier zip notarisé le 2026-10-14, accepté par Gatekeeper après téléchargement).

## Utilisation

```bash
make up && make app-config && make app-macos          # développement
make app-config-prod HOST=ysimonx@192.168.0.84        # une fois (ou après changement de clé / d'URL)
make app-build-macos && make app-install-macos        # production → /Applications/Clockifai.app
make app-dist-macos                                   # production signée + notarisée → zip pour d'autres Mac
```

## Limites connues

- `make app-build-macos` signe localement (« Sign to Run Locally ») : ce build ne s'ouvre que sur ce Mac.
  Pour un autre Mac, passer par `make app-dist-macos`.
- Les deux apps déclarent le schéma `clockifai://` : si les deux sont installées, un lien magique ou d'invitation
  ouvert sur le Mac peut arriver dans l'une ou l'autre. La connexion par mot de passe n'est pas concernée.
- Le panneau ne choisit ni tâche ni tags (la fenêtre principale le fait) ; changer de projet retire la tâche.
- Ouvrir le panneau active l'app (nécessaire pour taper la description) : si la fenêtre principale est ouverte,
  elle passe aussi au premier plan.

## Pistes

- Lancement à l'ouverture de session (`SMAppService`, macOS 13+), raccourci clavier global.
- Masquer l'icône du Dock quand la fenêtre est fermée (`NSApp.setActivationPolicy(.accessory)`).
- Mises à jour automatiques : Sparkle (usage courant hors App Store), ou Mac App Store + TestFlight
  (revue Apple, certificat Apple Distribution ; le bac à sable est déjà en place).
- Menus de l'app (Edit, View, Window…) en anglais : localiser `MainMenu.xib` en français.
