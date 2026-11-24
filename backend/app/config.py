import os

from sqlalchemy.engine import URL


def database_url() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if url:
        return url

    required = ("DB_USER", "DB_PASSWORD", "DB_HOST", "DB_PORT", "DB_NAME")
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise RuntimeError(
            "DATABASE_URL is not set and database settings are missing: " + ", ".join(missing)
        )
    host = os.environ["DB_HOST"]
    connection_options = {
        "username": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
        "database": os.environ["DB_NAME"],
    }
    if host.startswith("/"):
        url = URL.create(
            "postgresql+psycopg",
            **connection_options,
            query={"host": host},
        )
    else:
        url = URL.create(
            "postgresql+psycopg",
            **connection_options,
            host=host,
            port=int(os.environ["DB_PORT"]),
        )
    return url.render_as_string(hide_password=False)


def cors_origins() -> list[str]:
    raw = os.environ.get("CORS_ORIGINS", "http://localhost:3000")
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def cognito_user_pool_id() -> str:
    return os.environ.get("COGNITO_USER_POOL_ID", "")


def cognito_client_id() -> str:
    return os.environ.get("COGNITO_CLIENT_ID", "")
