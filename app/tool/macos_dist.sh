#!/bin/sh
# « Clockifai » pour macOS signée Developer ID et notarisée par Apple : un zip à installer sur n'importe quel Mac.
#   make app-dist-macos                 (APPLE_TEAM=XXXXXXXXXX pour une autre équipe)
# S'appuie sur le compte développeur ajouté dans Xcode (Réglages > Comptes) : aucun mot de passe ici.
# Avec -allowProvisioningUpdates, Xcode crée au besoin les certificats (Apple Development, Developer ID).
set -eu
cd "$(dirname "$0")/.."
TEAM=${APPLE_TEAM:?"APPLE_TEAM manquant (identifiant d'équipe Apple)"}
ARCHIVE=build/macos/Clockifai.xcarchive
OUT=build/macos/dist
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)

[ -f config/prod.json ] || { echo "config/prod.json manquant : make app-config-prod HOST=user@ip" >&2; exit 1; }

echo "[dist] compilation Flutter (prod)"
fvm flutter build macos --release --dart-define-from-file=config/prod.json

echo "[dist] archive Xcode (équipe $TEAM, runtime renforcé exigé par la notarisation)"
rm -rf "$ARCHIVE" "$OUT"
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  ENABLE_HARDENED_RUNTIME=YES || {
  echo "Archive impossible. « login details … rejected » : reconnectez le compte dans Xcode > Réglages > Comptes." >&2
  exit 1
}

echo "[dist] signature Developer ID et envoi au service de notarisation d'Apple"
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
PLIST
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
