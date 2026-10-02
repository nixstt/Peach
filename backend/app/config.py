import os

POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "postgres")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB", "postgres")

_explicit_database_url = os.getenv("DATABASE_URL")

if _explicit_database_url:
    DATABASE_URL = _explicit_database_url
else:
    DATABASE_URL = (
        f"postgresql+psycopg://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
        f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
    )

CORS_ORIGINS = [
    "https://d1ceuiiiioyp3m.cloudfront.net",
    "http://localhost:3000",
]
