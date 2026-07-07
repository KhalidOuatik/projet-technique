# syntax=docker/dockerfile:1
# ---- Image multi-stage : petite, reproductible, non-root ----

# 1) Étape build : installe les dépendances dans un venv isolé
FROM python:3.12-slim AS builder
WORKDIR /app
ENV PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1
COPY requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install -r requirements.txt

# 2) Étape runtime : image finale minimale
FROM python:3.12-slim AS runtime
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    APP_VERSION=1.0.0

# Utilisateur non-root (bonne pratique sécurité)
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY app.py .

USER appuser
EXPOSE 8080

# Healthcheck Docker (Kubernetes utilise en plus ses propres probes)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/health').status==200 else 1)"

# Serveur WSGI de production (gunicorn), 2 workers
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
