from sqlalchemy.engine import make_url

from app.config import database_url


def test_database_url_includes_password_for_engine(monkeypatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DB_USER", "postgres")
    monkeypatch.setenv("DB_PASSWORD", "report-test-password")
    monkeypatch.setenv("DB_HOST", "db.example")
    monkeypatch.setenv("DB_PORT", "5432")
    monkeypatch.setenv("DB_NAME", "spry")

    url = make_url(database_url())

    assert url.password == "report-test-password"
    assert url.host == "db.example"


def test_database_url_supports_cloud_sql_unix_socket(monkeypatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DB_USER", "spry")
    monkeypatch.setenv("DB_PASSWORD", "socket-test-password")
    monkeypatch.setenv("DB_HOST", "/cloudsql/project:region:instance")
    monkeypatch.setenv("DB_PORT", "5432")
    monkeypatch.setenv("DB_NAME", "spry")

    url = make_url(database_url())

    assert url.password == "socket-test-password"
    assert url.host is None
    assert url.query["host"] == "/cloudsql/project:region:instance"
