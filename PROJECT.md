# spry

Monorepo for the first slice of Spry: list meetings and create one.

## Decision

One repository, not three. A commit can change the API and the client that calls it together, so the two cannot drift. The stronger reason in this course: the repository is the context an agent can read. The endpoint, the model, the migration, and the component that renders it are one tree, so a change can be checked against the real contract. Splitting the same system into three repositories would buy independent release trains and cost that context. For a team of four and a product that does not exist yet, context is worth more.

## 1. Structure

```
spry/
├── docker-compose.yml          # postgres, backend, frontend
├── PROJECT.md                  # this specification
├── Makefile                    # local checks and the deploy contract
├── backend/
│   ├── Dockerfile              # image ECS runs; python:3.12-slim
│   ├── requirements.txt        # runtime, pinned
│   ├── requirements-dev.txt    # ruff, pytest, httpx; not installed in the image
│   ├── alembic.ini
│   ├── ruff.toml
│   ├── alembic/
│   │   ├── env.py              # migration runtime; reads DATABASE_URL
│   │   ├── script.py.mako
│   │   └── versions/           # committed revisions; 0001 creates meetings
│   ├── app/
│   │   ├── main.py             # FastAPI app, CORS, router
│   │   ├── config.py           # environment
│   │   ├── db.py               # engine and session
│   │   ├── api/routes/         # HTTP only: status codes and dependencies
│   │   ├── schemas/            # request and response contracts
│   │   ├── services/           # list and create
│   │   └── models/             # SQLAlchemy rows
│   ├── scripts/entrypoint.sh   # build DATABASE_URL if needed, then migrate and serve
│   └── tests/                  # API tests against a real Postgres
├── frontend/
│   ├── Dockerfile              # image for the local Vite dev server; node:22-alpine
│   ├── package.json            # pinned
│   ├── index.html
│   └── src/
│       ├── api.ts              # the only module that calls the backend
│       ├── components/         # meeting form, meeting table, week summary
│       ├── components/ui/      # shadcn/ui: button, input, label, card, table
│       └── lib/                # dates and classnames
├── .github/workflows/ci.yml    # lint, test, and deploy on main
├── infra/                      # CloudFormation: ECS, RDS, S3, CloudFront, OIDC role
└── scripts/                    # the commands the Makefile targets call
```

`backend/app/api` does not import the database driver except through a session dependency. `backend/app/services` does not know about HTTP. `backend/app/models` does not know about JSON. The split is there so a change to a status code does not sit in the same function as a query.

Nothing in `frontend/` imports Python. Nothing in `backend/` imports TypeScript. The HTTP contract below is the only coupling.

## 2. Pinned versions

Images: `python:3.12-slim`, `postgres:16`, `node:22-alpine`.

Backend runtime: FastAPI 0.110.0, Pydantic 2.6.4, SQLAlchemy 2.0.28, Alembic 1.13.1, Uvicorn 0.28.0, psycopg[binary] 3.1.18.

Backend tooling: ruff 0.7.4, pytest 8.3.3, httpx 0.27.2.

Frontend runtime: React 18.3.1, React DOM 18.3.1, `@radix-ui/react-label` 2.1.0, `@radix-ui/react-slot` 1.1.0, class-variance-authority 0.7.0, clsx 2.1.1, tailwind-merge 2.5.4.

Frontend tooling: Vite 5.4.11, `@vitejs/plugin-react` 4.3.3, TypeScript 5.6.3, Tailwind CSS 3.4.17, PostCSS 8.4.49, autoprefixer 10.4.20, ESLint 9.14.0, typescript-eslint 8.14.0, Prettier 3.3.3, Vitest 2.1.4.

shadcn/ui is not a runtime package. The components it would generate are copied into `frontend/src/components/ui` and styled with the packages above.

## 3. Contract

### Meeting

| Field | Type | Rules |
| --- | --- | --- |
| `id` | integer | auto-increment primary key; assigned by the database |
| `title` | string | trimmed first; then 1–200 characters |
| `starts_at` | string | ISO 8601 with a timezone; stored as `timestamptz`; always returned in UTC with a `Z` and no fractional seconds, e.g. `2026-10-01T10:00:00Z` |
| `ends_at` | string | same as `starts_at`; must be strictly after `starts_at` |
| `attendee_count` | integer | `>= 1` |

`GET /api/meetings` returns a JSON array of these objects, sorted by `starts_at` ascending, then `id` ascending. An empty table returns `[]`. No query parameters. No body.

```json
[
  {
    "id": 1,
    "title": "Design review",
    "starts_at": "2026-10-01T10:00:00Z",
    "ends_at": "2026-10-01T11:00:00Z",
    "attendee_count": 4
  }
]
```

`POST /api/meetings` accepts JSON and returns `201` with the created meeting, including `id`.

```json
{
  "title": "Design review",
  "starts_at": "2026-10-01T12:00:00+02:00",
  "ends_at": "2026-10-01T13:00:00+02:00",
  "attendee_count": 4
}
```

`id` is not a field of the request. Any unknown field, including `id`, is rejected. `422` uses FastAPI's body `{"detail": [...]}` when the title is empty after trim, a datetime has no timezone, `ends_at <= starts_at`, or `attendee_count < 1`.

If Postgres cannot be reached, the request returns `500` and the process stays up. Compose cannot help with a database that dies later. SQLAlchemy uses `pool_pre_ping`, so the next request discards a dead connection; if the database is still down, that request fails and the process keeps running.

### Frontend and backend

The browser calls `VITE_API_URL`. In Compose that value is `http://localhost:8000`, never the Docker name `backend`. CORS origins come from `CORS_ORIGINS`, a comma-separated list, default `http://localhost:3000`.

The form uses `datetime-local`. Those values are local time. The client converts them to UTC ISO with a `Z` before `POST`. The table renders timestamps in the browser's local zone.

Week summary, computed in the browser from the list, not from a new endpoint: count of meetings whose `starts_at` falls in the current local week (Monday 00:00 inclusive to the next Monday exclusive) and the previous local week, plus the difference. After a successful `POST` the list is fetched again.

## 4. Docker Compose

`docker compose up --build` is the only command a new developer runs. They install Docker Desktop first. There is no second compose file. Values below are fixed in the file so no `.env` is required to boot.

The frontend service runs the Vite dev server. Published host ports, the database password, and that dev server are for this laptop only. They are the wrong shape for production: the deployed frontend is the Vite build on S3 and CloudFront, and the deployed backend is the same backend image on ECS. The backend Dockerfile answers "what is in the image and how the process starts". Compose answers "how these three processes find each other on a laptop". The Dockerfile moves to ECS. The compose file does not.

### postgres

Image `postgres:16`. Listens on 5432 inside the compose network only. That port is not published on the host.

Environment: `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=postgres`, `POSTGRES_DB=postgres`. These credentials are for local development.

Volume `pgdata` mounted at `/var/lib/postgresql/data`.

Depends on nothing.

Ready when the healthcheck `pg_isready -h 127.0.0.1 -U postgres -d postgres` succeeds. Interval 5s, timeout 3s, 10 retries. The TCP host is forced so the check cannot pass against the temporary server Postgres opens on a local socket during init.

### backend

Build `./backend`. Listens on 8000. Published `8000:8000`.

Environment: `DATABASE_URL=postgresql+psycopg://postgres:postgres@postgres:5432/postgres`. Alembic and the app both read it. `CORS_ORIGINS=http://localhost:3000`.

Depends on `postgres` with `condition: service_healthy`. `depends_on` without the condition only orders process start, which is not readiness.

Command: `scripts/entrypoint.sh`. When `DATABASE_URL` is already set, the script runs:

```sh
alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The migration runs at container start, not during `docker build`, and not by hand. On ECS the same script builds `DATABASE_URL` from `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD` when the URL is not already in the environment, then runs the same two commands.

Ready when a healthcheck requests `GET http://localhost:8000/api/meetings` with Python `urllib`. The slim image has no curl. Interval 5s, timeout 5s, `start_period` 10s, 12 retries. There is no `/health` route. A 200 from the list endpoint means the process is up and the database answered.

### frontend

Build `./frontend`. Listens on 3000. Published `3000:3000`.

Command: `vite --host 0.0.0.0 --port 3000`. No second web server.

Environment: `VITE_API_URL=http://localhost:8000`. Vite reads it when the dev server starts.

Depends on `backend` with `condition: service_healthy`.

## 5. Out of scope

Authentication, edit, delete, pagination, a message queue, a cache, a reverse proxy, a second database, Kubernetes, and any route other than `GET /api/meetings` and `POST /api/meetings`.

## 6. Checks and deploy

Tooling and AWS are not part of the first slice's product behaviour. They are how this repository is checked and how the same two services leave the laptop. `make deploy-backend` and `make deploy-frontend` are the contract. GitHub Actions runs those same targets. It does not have a second deploy script.

Lint: `ruff check` and `ruff format --check` in `backend/`. ESLint, Prettier, and `tsc --noEmit` in `frontend/`.

Tests: pytest against Postgres, using the database name `spry_test` so the dev database is not wiped. Vitest for the date helpers.

AWS, region `us-east-1` only, so one ACM certificate can be attached to both CloudFront and the load balancer:

| Piece | What it is | Name |
| --- | --- | --- |
| ECR | stores the backend image; tag is the full git commit SHA, never `latest` | `spry-backend` |
| ECS cluster and Fargate service | runs the backend image | cluster `spry`, service `spry-backend` |
| ALB and target group | stable address; health check `GET /api/meetings` expecting 200 | `spry-alb` |
| RDS Postgres 16 | the database Compose provided locally; `db.t4g.micro`, 20 GB, not publicly reachable | `spry-db` |
| S3 and CloudFront | private bucket, origin access control, HTTPS at the edge | `spry-frontend` |
| ACM | one certificate for the app hostname and the api hostname | DNS validation |
| IAM role | GitHub OIDC, `sts:AssumeRoleWithWebIdentity` | `spry-github-deploy` |

No NAT gateway. Tasks run in the default VPC's public subnets with a public IP so they can pull the image, and their security group accepts port 8000 only from the load balancer. The database accepts 5432 only from the tasks.

The task's own health check hits `GET /api/meetings`. Three failures and ECS replaces the task. The load balancer's health check is what stops sending traffic before that replacement finishes.

Trust policy on the deploy role, both conditions `StringEquals` (a `*` is a literal character, not a wildcard):

- `token.actions.githubusercontent.com:aud` is `sts.amazonaws.com`
- `token.actions.githubusercontent.com:sub` is `repo:<owner>/<repo>:ref:refs/heads/main`

A push to `main` lints, tests, builds the image, pushes it to ECR tagged with the commit SHA, and updates the ECS service to that tag. The frontend target builds with `VITE_API_URL` set to the API's HTTPS URL, syncs `dist/` to the bucket, and invalidates the distribution.

Access keys are not stored in this repository. Actions gets temporary credentials by assuming the role above.
