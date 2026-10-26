# Plan 07 — Versions iOS et Android : développement, TestFlight, Google Play

> Statut : **fait** (14 octobre 2026). Reste l'icône de l'app (« Limites connues »).

## Besoin

Comme pour macOS (`06-macos-barre-de-menus.md`) : une version de développement branchée sur la pile locale et une version de production
(clockifai.kysoe.com), distribuée par **TestFlight** sur iPhone et par **Google Play** (app bundle) sur Android.

## Décisions

1. **Deux applications par plateforme**, installables côte à côte (base locale et session séparées) :

   | Build | Nom | iOS | Android | Backend |
   |---|---|---|---|---|
   | Debug | Clockifai Dev | `com.kysoe.clockifai.dev` | `com.kysoe.clockifai.dev` (`applicationIdSuffix`) | pile locale |
   | Release | Clockifai | `com.kysoe.clockifai` | `com.kysoe.clockifai` | prod (`app/config/prod.json`) |

   Identifiant `com.kysoe.clockifai` sur toutes les plateformes (macOS compris) : un identifiant suit un domaine que l'on
   possède (kysoe.com) ; il a remplacé `fr.clockifai.clockifai` le 2026-10-14, avant tout envoi sur les stores (il y
   devient définitif). Paquet Kotlin `com.kysoe.clockifai` (`MainActivity`).
   iOS : `APP_DISPLAY_NAME` et identifiant par configuration dans `project.pbxproj` (Info.plist lit `$(APP_DISPLAY_NAME)`).
   Android : `resValue("string", "app_name", …)` par type de build (`buildFeatures.resValues` activé).
2. **Pile locale depuis les appareils** : le simulateur iOS partage le réseau du Mac (`localhost` fonctionne) ;
   sur Android, `make app-android` fait `adb reverse` des ports 8000 / 8080 / 5050, si bien que la même
   `config/local.json` sert au web, à macOS, à iOS et à Android (émulateur comme téléphone branché).
   HTTP en clair autorisé sur Android en Debug seulement (`src/debug/AndroidManifest.xml`).
3. **TestFlight** (`make app-dist-ios`, `app/tool/ios_dist.sh`) : archive Release signée automatiquement avec l'équipe
   `9SGKL7VUD3`, export `app-store-connect` avec `destination=upload`, via le compte ajouté dans Xcode
   (`-allowProvisioningUpdates`) : ni mot de passe ni clé d'API dans le dépôt. Sa session expirant (« missing
   Xcode-Token », 26 octobre 2026), une clé d'API App Store Connect rangée dans `~/.config/clockifai/apple/`
   prend le relais quand elle est présente (`app/tool/apple_auth.sh`, aussi pour macOS) ; `make app-dist-testflight`
   enchaîne iPhone et Mac. `ITSAppUsesNonExemptEncryption = NO`
   (HTTPS seulement) évite la question d'export à chaque build. Prérequis unique : la fiche de l'app dans
   App Store Connect (identifiant de bundle `com.kysoe.clockifai`).
4. **Google Play** (`make app-dist-android`, `app/tool/android_dist.sh`) : app bundle `.aab` de production signé par la
   **clé d'envoi** (Play App Signing : Google détient la clé de signature finale). La clé est créée une fois par
   `make app-android-keystore` dans `~/.config/clockifai/android/` (`upload.jks`, `key.properties`), hors du dépôt,
   et doit être sauvegardée. Le script vérifie que le bundle porte bien l'empreinte SHA-256 de cette clé (et non la clé
   de debug, repli de `build.gradle.kts` sur un poste sans clé).
5. **Numéro de build** croissant exigé par TestFlight et Google Play : par défaut, minutes écoulées depuis le
   2026-01-01 UTC (`BUILD_NUMBER=…` pour forcer) ; la version affichée reste celle de `pubspec.yaml`.
6. **Outils** : SDK Android 36 (licences acceptées), simulateur iOS 27. Avec Xcode 27, l'app Simulator est remplacée
   par DeviceHub ; `make app-ios` ouvre l'une ou l'autre.

## Utilisation

```bash
make up && make app-config
make app-ios                                   # Clockifai Dev sur le simulateur iPhone
make app-android-emulator && make app-android  # Clockifai Dev sur l'émulateur (ou un téléphone branché)

make app-config-prod HOST=ysimonx@192.168.0.84
make app-dist-ios          # → App Store Connect, puis TestFlight
make app-android-keystore  # une fois ; sauvegarder ~/.config/clockifai/android/
make app-dist-android      # → app/build/Clockifai-<version>-<build>.aab à déposer dans la Play Console
```

## Limites connues

- Premier envoi Google Play manuel : la Play Console exige de créer l'app et de déposer le premier `.aab` à la main
  (envois automatiques possibles ensuite avec un compte de service et l'API Google Play).
- Sur un iPhone physique, la version Dev ne joint pas `localhost` : générer la config avec l'adresse IP du Mac.
- Les deux variantes déclarent le schéma `clockifai://` : un lien magique peut ouvrir l'une ou l'autre.
- Icône de l'app : celle de Flutter par défaut, à remplacer avant une publication publique.
