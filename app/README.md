# Clockifai — application Flutter

Application unique web / iOS / Android / macOS, offline-first (PowerSync + Drift).
Voir le [README](../README.md) et le [CLAUDE.md](../CLAUDE.md) à la racine du dépôt.

```bash
make app-config     # config/local.json depuis deploy/.env
make app-get        # dépendances, génération Drift, assets web PowerSync
make app-web        # Chrome sur http://localhost:3000
make app-macos      # « Clockifai Dev » (macOS, pile locale, icône dans la barre de menus)
cd app && fvm flutter run             # simulateur iOS / émulateur Android
cd app && fvm flutter test
```

Libellés FR/EN : `tool/gen_arb.py` est en retard sur les ARB (des clés y ont été ajoutées directement) ;
le relancer en supprimerait. Ajouter les clés dans `lib/l10n/app_fr.arb` et `app_en.arb`, puis `fvm flutter gen-l10n`.
