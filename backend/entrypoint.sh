#!/bin/sh
set -eu

echo "Starting backend on 0.0.0.0:8000"

if alembic upgrade head; then
  echo "Alembic migrations applied"
else
  echo "WARNING: Alembic migrations failed or were skipped; starting the app anyway" >&2
fi

exec uvicorn app.main:app --host 0.0.0.0 --port 8000
