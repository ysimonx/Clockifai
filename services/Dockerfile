# Clockifai services (Flask) — image multi-arch (amd64 / arm64), dépendances gérées par uv.
FROM python:3.12-slim-bookworm AS base

# WeasyPrint (PDF) a besoin de Pango/Cairo ; curl pour les healthchecks manuels.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz0b libffi8 libcairo2 \
      fonts-dejavu-core shared-mime-info curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /srv

# Dépendances d'abord (cache Docker), code ensuite.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY app ./app
COPY gunicorn.conf.py ./

# Plugin Claude Code servi par /api/claude : contexte nommé « integrations » (deploy/docker-compose.yml).
COPY --from=integrations claude-code ./integrations/claude-code
ENV CLAUDE_PLUGIN_DIR=/srv/integrations/claude-code

EXPOSE 5000
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:create_app()"]
