# Authentification auprès d'Apple pour xcodebuild, lue par ios_dist.sh et macos_dist.sh (. tool/apple_auth.sh).
# Avec une clé d'API App Store Connect, hors du dépôt comme la clé d'envoi Android, les envois ne dépendent plus de
# la session du compte dans Xcode : son jeton n'est lisible que session déverrouillée (« missing Xcode-Token » quand
# l'écran du Mac est verrouillé, constaté le 27 octobre 2026) et il finit par expirer :
#   ~/.config/clockifai/apple/AuthKey_<ID>.p8   la clé téléchargée (rôle Admin, pour que Xcode gère certificats et profils)
#   ~/.config/clockifai/apple/asc.env           ASC_KEY_ID=<ID> et ASC_ISSUER_ID=<identifiant de l'émetteur>
# Sans ces fichiers, xcodebuild passe par le compte ajouté dans Xcode (Réglages > Comptes).
ASC_DIR=${ASC_DIR:-$HOME/.config/clockifai/apple}
[ -f "$ASC_DIR/asc.env" ] && . "$ASC_DIR/asc.env"
ASC_KEY=${ASC_KEY_ID:+$ASC_DIR/AuthKey_$ASC_KEY_ID.p8}
if [ -n "$ASC_KEY" ] && { [ ! -f "$ASC_KEY" ] || [ -z "${ASC_ISSUER_ID:-}" ]; }; then
  echo "Clé d'API App Store Connect incomplète : $ASC_KEY et ASC_ISSUER_ID (dans $ASC_DIR/asc.env) sont nécessaires." >&2
  exit 1
fi

xcodebuild_asc() {
  if [ -n "$ASC_KEY" ]; then
    xcodebuild -authenticationKeyPath "$ASC_KEY" -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID" "$@"
  else
    xcodebuild "$@"
  fi
}

asc_auth_label() {
  if [ -n "$ASC_KEY" ]; then echo "clé d'API $ASC_KEY_ID"; else echo "compte ajouté dans Xcode"; fi
}

asc_expired_hint() {
  if ioreg -n Root -d1 -k IOConsoleUsers 2>/dev/null | grep -q '"CGSSessionScreenIsLocked"=Yes'; then
    echo "Envoi refusé : l'écran du Mac est verrouillé, et Xcode ne lit le jeton de son compte Apple que session" >&2
    echo "déverrouillée. Déverrouillez le Mac (sur place ou par partage d'écran), puis relancez. Pour ne plus en" >&2
    echo "dépendre : une clé d'API App Store Connect dans $ASC_DIR (voir app/tool/apple_auth.sh)." >&2
    return
  fi
  echo "Envoi refusé : la connexion de Xcode au compte Apple a expiré. Xcode > Réglages > Comptes :" >&2
  echo "reconnectez le compte (ou retirez-le et rajoutez-le), puis relancez. Pour ne plus en dépendre :" >&2
  echo "une clé d'API App Store Connect dans $ASC_DIR (voir app/tool/apple_auth.sh)." >&2
}
