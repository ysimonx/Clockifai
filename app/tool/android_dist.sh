#!/bin/sh
# « Clockifai » pour Google Play : app bundle (.aab) de production signé avec la clé d'envoi.
#   make app-dist-android            (BUILD_NUMBER=… pour forcer le numéro de build)
# Google Play exige un numéro de build croissant : par défaut, minutes écoulées depuis le 2026-01-01 (UTC).
set -eu
cd "$(dirname "$0")/.."
KEYS=${CLOCKIFAI_ANDROID_KEY_PROPERTIES:-$HOME/.config/clockifai/android/key.properties}
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
BUILD=${BUILD_NUMBER:-$(( ($(date +%s) - 1767225600) / 60 ))}

[ -f config/prod.json ] || { echo "config/prod.json manquant : make app-config-prod HOST=user@ip" >&2; exit 1; }
[ -f "$KEYS" ] || { echo "Clé d'envoi absente ($KEYS) : make app-android-keystore" >&2; exit 1; }

echo "[android] app bundle de production $VERSION ($BUILD)"
fvm flutter build appbundle --release --dart-define-from-file=config/prod.json --build-number="$BUILD"
AAB=build/app/outputs/bundle/release/app-release.aab

# Le bundle doit être signé par la clé d'envoi, pas par la clé de debug (repli de build.gradle.kts).
# keytool en anglais : sa sortie est traduite selon la langue du système.
prop() { sed -n "s/^$1=//p" "$KEYS"; }
expected=$(keytool -J-Duser.language=en -list -v -keystore "$(prop storeFile)" -storepass "$(prop storePassword)" -alias "$(prop keyAlias)" \
  | sed -n 's/^.*SHA256: *//p')
actual=$(keytool -J-Duser.language=en -printcert -jarfile "$AAB" | sed -n 's/^.*SHA256: *//p' | head -1)
[ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo "Le bundle n'est pas signé par la clé d'envoi." >&2; exit 1; }

OUT="build/Clockifai-$VERSION-$BUILD.aab"
cp "$AAB" "$OUT"
echo "[android] prêt : app/$OUT (Play Console > Tester et publier)"
