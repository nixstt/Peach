#!/bin/sh
# Container start, locally and on ECS. The migration is not part of the image build.
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  : "${DB_USER:?DB_USER is required when DATABASE_URL is unset}"
  : "${DB_PASSWORD:?DB_PASSWORD is required when DATABASE_URL is unset}"
  : "${DB_HOST:?DB_HOST is required when DATABASE_URL is unset}"
  : "${DB_PORT:?DB_PORT is required when DATABASE_URL is unset}"
  : "${DB_NAME:?DB_NAME is required when DATABASE_URL is unset}"
  DATABASE_URL="postgresql+psycopg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
  export DATABASE_URL
fi

alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
