import os
import pytest
import psycopg
from psycopg import sql

from alembic import command
from alembic.config import Config

from app.auth import verify_token
from app.main import app

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+psycopg://postgres:postgres@postgres:5432/spry_test",
)
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")


def _ensure_database() -> None:
    url = os.environ["DATABASE_URL"]
    if not url.endswith("/spry_test"):
        raise RuntimeError("refusing to test against a database other than spry_test")
    admin_url = url.replace("postgresql+psycopg://", "postgresql://", 1)
    admin_url = admin_url.rsplit("/", 1)[0] + "/postgres"
    with psycopg.connect(admin_url, autocommit=True) as conn:
        row = conn.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s",
            ("spry_test",),
        ).fetchone()
        if row is None:
            conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier("spry_test")))


def pytest_configure() -> None:
    _ensure_database()
    command.upgrade(Config("alembic.ini"), "head")


@pytest.fixture(autouse=True)
def _mock_auth():
    """Mock authentication so existing API unit tests pass without real Cognito tokens."""
    app.dependency_overrides[verify_token] = lambda: {
        "sub": "test-user-id",
        "client_id": "test-client-id",
        "email": "tester@example.com",
    }
    yield
    app.dependency_overrides.pop(verify_token, None)
