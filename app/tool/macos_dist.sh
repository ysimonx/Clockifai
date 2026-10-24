#!/bin/sh
# « Clockifai » pour macOS, version de production, distribuée de deux façons :
#   make app-dist-macos              notarize   : signée Developer ID et notarisée, zip à installer sur n'importe quel Mac
#   make app-dist-macos-testflight   testflight : envoyée à App Store Connect, installée par TestFlight sur Mac
# (APPLE_TEAM=…, BUILD_NUMBER=… pour forcer.) S'appuie sur le compte développeur ajouté dans Xcode
# (Réglages > Comptes) : aucun mot de passe ici. Avec -allowProvisioningUpdates, Xcode crée au besoin les
# certificats et profils. Numéro de build croissant (exigé par TestFlight) : minutes depuis le 2026-01-01 UTC.
set -eu
cd "$(dirname "$0")/.."
MODE=${1:-notarize}
TEAM=${APPLE_TEAM:?"APPLE_TEAM manquant (identifiant d'équipe Apple)"}
ARCHIVE=build/macos/Clockifai.xcarchive
OUT=build/macos/dist
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
BUILD=${BUILD_NUMBER:-$(( ($(date +%s) - 1767225600) / 60 ))}

case "$MODE" in notarize|testflight) ;; *) echo "Mode inconnu : $MODE (notarize ou testflight)" >&2; exit 1 ;; esac
[ -f config/prod.json ] || { echo "config/prod.json manquant : make app-config-prod HOST=user@ip" >&2; exit 1; }

echo "[dist] compilation Flutter (prod) $VERSION ($BUILD)"
fvm flutter build macos --release --dart-define-from-file=config/prod.json --build-number="$BUILD"

echo "[dist] archive Xcode (équipe $TEAM, runtime renforcé exigé par la notarisation)"
rm -rf "$ARCHIVE" "$OUT"
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  ENABLE_HARDENED_RUNTIME=YES || {
  echo "Archive impossible. « login details … rejected » : reconnectez le compte dans Xcode > Réglages > Comptes." >&2
  exit 1
}

# Les bundles de ressources des paquets SPM (PrivacyInfo.xcprivacy seul, sans exécutable) héritent du
# CODE_SIGN_IDENTITY passé ci-dessus et sont signés « Apple Development » ; l'export ne les re-signe pas, d'où le
# refus d'App Store Connect (ITMS-90284). Sans signature propre, comme après flutter build, celle de l'app les scelle.
rm -rf "$ARCHIVE"/Products/Applications/Clockifai.app/Contents/Resources/*.bundle/Contents/_CodeSignature

export_options() {
  mkdir -p "$OUT"
  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$1</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>$2
</dict>
</plist>
PLIST
}

if [ "$MODE" = testflight ]; then
  echo "[dist] signature Mac App Store et envoi à App Store Connect"
  export_options app-store-connect '
  <key>manageAppVersionAndBuildNumber</key><false/>'
  if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates > "$OUT/export.log" 2>&1; then
    tail -5 "$OUT/export.log" >&2
    if grep -q "Failed to Use Accounts" "$OUT/export.log"; then
      # « Invalid credentials in keychain … missing Xcode-Token » : la session du compte dans Xcode a expiré.
      echo "Envoi refusé : la connexion de Xcode au compte Apple a expiré. Xcode > Réglages > Comptes :" >&2
      echo "reconnectez le compte (ou retirez-le et rajoutez-le), puis relancez." >&2
    else
      echo "Envoi refusé. Si App Store Connect ne trouve pas d'app macOS : ajoutez la plateforme macOS à la fiche" >&2
      echo "« clockifai » (com.kysoe.clockifai) dans App Store Connect, puis relancez." >&2
    fi
    exit 1
  fi
  echo "[dist] envoyé : $VERSION ($BUILD) apparaîtra dans TestFlight pour Mac après traitement par Apple (5 à 30 min)."
  exit 0
fi

echo "[dist] signature Developer ID et envoi au service de notarisation d'Apple"
export_options developer-id ''
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates

echo "[dist] attente de la notarisation (en général quelques minutes)"
i=0
until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/notarized" > "$OUT/notarization.log" 2>&1; do
  # Tant qu'Apple traite l'archive : « … is processing and not ready for distribution ». Tout autre message = échec.
  if ! grep -q "is processing" "$OUT/notarization.log" || [ $i -ge 60 ]; then
    echo "Notarisation refusée ou interrompue (journaux Xcode : Organizer > Archives) :" >&2
    tail -5 "$OUT/notarization.log" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 30
done

APP="$OUT/notarized/Clockifai.app"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ZIP="build/macos/Clockifai-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "[dist] prêt : app/$ZIP (à décompresser dans /Applications)"
