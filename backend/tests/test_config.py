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
