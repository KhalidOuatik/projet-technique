"""
Application de démonstration — API Flask instrumentée pour Prometheus.

Le but pédagogique n'est PAS l'application elle-même, mais la chaîne DevSecOps
qui l'entoure. Elle expose volontairement le minimum utile :
  - /            page d'accueil + version
  - /health      sonde liveness/readiness (utilisée par Kubernetes)
  - /api/hello   endpoint métier de démonstration
  - /metrics     métriques au format Prometheus
"""
import os
import time

from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
app = Flask(__name__)

# --- Métriques Prometheus ---------------------------------------------------
REQUEST_COUNT = Counter(
    "app_requests_total", "Nombre total de requêtes HTTP",
    ["method", "endpoint", "http_status"],
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds", "Latence des requêtes HTTP", ["endpoint"],
)


@app.before_request
def _start_timer():
    request._start_time = time.time()


@app.after_request
def _record_metrics(response):
    latency = time.time() - getattr(request, "_start_time", time.time())
    endpoint = request.path
    REQUEST_LATENCY.labels(endpoint=endpoint).observe(latency)
    REQUEST_COUNT.labels(
        method=request.method, endpoint=endpoint, http_status=response.status_code
    ).inc()
    return response


# --- Routes -----------------------------------------------------------------
@app.route("/")
def index():
    return jsonify(
        message="Bienvenue sur la demo DevSecOps 🚀",
        version=APP_VERSION,
        hint="Essayez /health, /api/hello?name=Ada et /metrics",
    )


@app.route("/health")
def health():
    # Point de contrôle pour les probes Kubernetes.
    return jsonify(status="ok", version=APP_VERSION), 200


@app.route("/api/hello")
def hello():
    name = request.args.get("name", "monde")
    return jsonify(greeting=f"Bonjour, {name} !")


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
