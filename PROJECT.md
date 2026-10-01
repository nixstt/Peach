spry. First slice: list meetings and create a meeting.

## 1. Structure

- `backend/` — REST API (FastAPI, SQLAlchemy, Alembic).
  - `app/` — models, Pydantic schemas, routes, DB config.
  - `alembic/` — migration environment and `versions/` (initial migration creating `meetings` is committed).
  - `alembic.ini`, `Dockerfile`, `requirements.txt` (pinned).
- `frontend/` — SPA (React, Vite, Tailwind, shadcn/ui).
  - `src/` — components (meetings list, create form), layout, styles, API client.
  - `Dockerfile`, `package.json` (pinned).
- `docker-compose.yml` — postgres, backend, frontend. After installing Docker Desktop, `docker compose up` is the only command needed (use `--build` after code changes).

## 2. Pinned versions

- Images: `python:3.12-slim`, `postgres:16`, `node:22-alpine`
- Backend: FastAPI 0.110.0, Pydantic 2.6.4, SQLAlchemy 2.0.28, Alembic 1.13.1, Uvicorn 0.28.0, psycopg[binary] 3.1.18
- Frontend: React 18.3.1, Vite 5.4.11, Tailwind CSS 3.4.17, TypeScript 5.6.3

## 3. Contract

### Meeting
- `id`: integer, auto-increment primary key
- `title`: string, 1–200 chars, non-empty after trim
- `starts_at`, `ends_at`: ISO 8601 with timezone; stored as `timestamptz`; always returned in UTC with `Z` (e.g. `2026-10-01T10:00:00Z`)
- `attendee_count`: integer, >= 1

### GET /api/meetings
- No body, no query params.
- 200: JSON array of Meeting, sorted by `starts_at` ascending, then `id`. Empty table returns `[]`.

### POST /api/meetings
- Body: `title`, `starts_at`, `ends_at`, `attendee_count` (`id` is not accepted).
- 201: the created Meeting, including `id`.
- 422: standard FastAPI body `{"detail": [...]}` when any rule is violated:
  empty title, datetime without timezone, `ends_at <= starts_at`, `attendee_count < 1`.

### Frontend <-> backend
- The browser calls the backend at `http://localhost:8000` (not `backend:8000`).
- Backend allows CORS for `http://localhost:3000`.
- Frontend reads the API address from `VITE_API_URL`.
- The form converts `datetime-local` values to UTC ISO before sending.

### UI
One page: a table of meetings (from GET) and a form (title, starts_at, ends_at, attendee_count). On successful POST the list is refreshed.

## 4. Docker Compose

### postgres
- Image `postgres:16`. Port 5432 inside the compose network only (not published).
- Env: `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=postgres`, `POSTGRES_DB=postgres` (local dev only).
- Volume: `pgdata` at `/var/lib/postgresql/data`.
- Depends on: nothing.
- Ready when: healthcheck `pg_isready -h 127.0.0.1 -U postgres -d postgres`, every 5s, timeout 3s, 10 retries. TCP host is forced so the check cannot pass against the temporary init-time server.

### backend
- Build `./backend`. Listens on 8000, published `8000:8000`.
- Env: `DATABASE_URL=postgresql+psycopg://postgres:postgres@postgres:5432/postgres` (read by both the app and Alembic).
- Depends on: `postgres`, `condition: service_healthy`.
- Startup: `alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000`.
- Ready when: healthcheck requests `GET http://localhost:8000/api/meetings` via Python `urllib` (no curl in the image); every 5s, `start_period` 10s, 12 retries.

### frontend
- Build `./frontend`. Listens on 3000, published `3000:3000`.
- Runs the Vite dev server: `vite --host 0.0.0.0 --port 3000`. No additional web server.
- Env: `VITE_API_URL=http://localhost:8000`.
- Depends on: `backend`, `condition: service_healthy`.

## 5. Out of scope
Auth, edit/delete, pagination, tests, CI, queues, caches, reverse proxy, extra databases, extra endpoints (including `/health`).
