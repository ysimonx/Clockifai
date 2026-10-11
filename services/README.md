# Clockifai services (Flask)

Petit service Python pour ce que Supabase ne fait pas : exports CSV/XLSX/PDF, factures,
jobs planifiés (auto-stop des chronomètres, purge), kiosque.

```bash
uv sync                      # crée .venv et installe (dev inclus)
uv run pytest                # tests sans base
DATABASE_URL=postgresql://postgres:...@localhost:5432/postgres \
SUPABASE_JWT_SECRET=... uv run flask --app app run --debug -p 5050
```

En production le service tourne dans le conteneur `services` (voir `deploy/docker-compose.yml`).
