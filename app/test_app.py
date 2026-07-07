"""Tests unitaires minimaux — exécutés par le pipeline CI (pytest)."""
import app as app_module


def _client():
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


def test_health_ok():
    resp = _client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_index_has_version():
    resp = _client().get("/")
    assert resp.status_code == 200
    assert "version" in resp.get_json()


def test_hello_default():
    resp = _client().get("/api/hello")
    assert resp.get_json()["greeting"] == "Bonjour, monde !"


def test_hello_named():
    resp = _client().get("/api/hello?name=Ada")
    assert "Ada" in resp.get_json()["greeting"]


def test_metrics_exposed():
    resp = _client().get("/metrics")
    assert resp.status_code == 200
    assert b"app_requests_total" in resp.data
