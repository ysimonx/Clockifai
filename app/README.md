# Clockifai — application Flutter

Application unique web / iOS / Android, offline-first (PowerSync + Drift).
Voir le [README](../README.md) et le [CLAUDE.md](../CLAUDE.md) à la racine du dépôt.

```bash
make app-config     # config/local.json depuis deploy/.env
make app-get        # dépendances, génération Drift, assets web PowerSync
make app-web        # Chrome sur http://localhost:3000
cd app && fvm flutter run             # simulateur iOS / émulateur Android
cd app && fvm flutter test
```

Les libellés FR/EN sont générés par `python3 tool/gen_arb.py` (source unique), puis `fvm flutter gen-l10n`.
