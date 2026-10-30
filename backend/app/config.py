import os


def database_url() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        raise RuntimeError("DATABASE_URL is not set")
    return url


def cors_origins() -> list[str]:
    raw = os.environ.get("CORS_ORIGINS", "http://localhost:3000")
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def cognito_user_pool_id() -> str:
    return os.environ.get("COGNITO_USER_POOL_ID", "")


def cognito_client_id() -> str:
    return os.environ.get("COGNITO_CLIENT_ID", "")
