#!/bin/sh
# « Clockifai » pour iPhone : archive de production envoyée à App Store Connect, puis proposée par TestFlight.
#   make app-dist-ios                (APPLE_TEAM=…, BUILD_NUMBER=… pour forcer)
# Prérequis : compte développeur ajouté dans Xcode (Réglages > Comptes), ou clé d'API App Store Connect
# (tool/apple_auth.sh), et fiche de l'app créée dans App Store Connect pour l'identifiant com.kysoe.clockifai.
# Aucun mot de passe ici.
# Numéro de build croissant exigé : par défaut, minutes écoulées depuis le 2026-01-01 (UTC).
set -eu
cd "$(dirname "$0")/.."
. tool/apple_auth.sh
TEAM=${APPLE_TEAM:?"APPLE_TEAM manquant (identifiant d'équipe Apple)"}
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
BUILD=${BUILD_NUMBER:-$(( ($(date +%s) - 1767225600) / 60 ))}
ARCHIVE=build/ios/Clockifai.xcarchive
OUT=build/ios/dist

[ -f config/prod.json ] || { echo "config/prod.json manquant : make app-config-prod HOST=user@ip" >&2; exit 1; }

echo "[ios] compilation Flutter (prod) $VERSION ($BUILD)"
fvm flutter build ios --release --no-codesign --dart-define-from-file=config/prod.json --build-number="$BUILD"

echo "[ios] archive Xcode (équipe $TEAM, $(asc_auth_label))"
rm -rf "$ARCHIVE" "$OUT"
xcodebuild_asc -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic || {
  echo "Archive impossible. « login details … rejected » : reconnectez le compte dans Xcode > Réglages > Comptes." >&2
  exit 1
}

echo "[ios] signature App Store et envoi à App Store Connect"
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
if ! xcodebuild_asc -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates > "$OUT/export.log" 2>&1; then
  tail -5 "$OUT/export.log" >&2
  if grep -q "Failed to Use Accounts" "$OUT/export.log"; then
    # « Invalid credentials in keychain … missing Xcode-Token » : écran verrouillé, ou session du compte expirée.
    asc_expired_hint
  else
    echo "Envoi refusé. « App record … not found » : créez l'app dans App Store Connect" >&2
    echo "(Apps > + > Nouvelle app, identifiant de bundle com.kysoe.clockifai), puis relancez." >&2
  fi
  exit 1
fi
echo "[ios] envoyé : $VERSION ($BUILD) apparaîtra dans TestFlight après traitement par Apple (5 à 30 min)."
