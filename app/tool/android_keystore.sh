#!/bin/sh
# Crée une fois pour toutes la clé d'envoi Google Play, hors du dépôt : ~/.config/clockifai/android/
# (upload.jks + key.properties, mot de passe aléatoire). À SAUVEGARDER, par exemple dans un gestionnaire
# de mots de passe : sans elle, plus de mise à jour sur le Play Store (sauf réinitialisation demandée à Google).
#   make app-android-keystore
set -eu
DIR=${CLOCKIFAI_ANDROID_DIR:-$HOME/.config/clockifai/android}
if [ -f "$DIR/key.properties" ]; then
  echo "Clé d'envoi déjà présente : $DIR"
  exit 0
fi
mkdir -p "$DIR"
chmod 700 "$DIR"
pass=$(openssl rand -base64 32 | tr -d '/+=\n')
keytool -genkeypair -keystore "$DIR/upload.jks" -storetype PKCS12 -alias upload \
  -keyalg RSA -keysize 4096 -validity 10000 -storepass "$pass" -keypass "$pass" \
  -dname "CN=Clockifai, O=Clockifai, C=FR"
cat > "$DIR/key.properties" <<PROPS
storeFile=$DIR/upload.jks
storePassword=$pass
keyAlias=upload
keyPassword=$pass
PROPS
chmod 600 "$DIR/upload.jks" "$DIR/key.properties"
echo "Clé d'envoi créée dans $DIR : sauvegardez upload.jks et key.properties."
