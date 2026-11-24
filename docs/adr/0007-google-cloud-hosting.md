# ADR 0007: Google Cloud hosting for Lab 9

- **Status:** Accepted for the Lab 9 deployment
- **Date:** 2026-11-24

## Context

Spry is a React/Vite frontend backed by a FastAPI application and PostgreSQL.
The existing AWS deployment uses an ECS Fargate service behind an Application
Load Balancer, Amazon RDS for PostgreSQL, S3-backed frontend hosting, and
Cognito access-token validation. The Lab 9 GCP deployment should preserve the
relational data model and API contract while keeping its Terraform state
separate from AWS.

## Decision

- Run the existing FastAPI API on **Cloud Run**, with request-based billing and
  zero minimum instances.
- Use **Cloud SQL for PostgreSQL** (`db-f1-micro`, 10 GiB SSD) to retain the
  current relational schema and Alembic migrations.
- Store the generated database password in **Secret Manager**. Terraform
  generates the password; the application service account receives access to
  only that secret and the Cloud SQL Client role.
- Store and deploy the API image through **Artifact Registry**.
- Host the static Vite build on **Firebase Hosting** and rewrite `/api/**` to
  the Cloud Run API. Same-origin routing avoids requiring browser CORS for the
  normal hosting path.
- Retain **Amazon Cognito** token validation for this migration lab. The
  existing browser and API already implement it; replacing the identity
  provider would broaden the migration and require a new Identity Platform
  setup. Cognito's callback and sign-out allowlists must include the Firebase
  Hosting origin before sign-in works there.
- Keep the GCP Terraform state in a separate `spry-gcp` HCP Terraform workspace
  when the student's HCP Terraform organization is configured. The `gcp/`
  directory is independently initializable and does not reference AWS state.

## Alternatives considered

- **Firestore instead of Cloud SQL:** rejected for this port because the app
  relies on PostgreSQL relations, SQLAlchemy, JSONB, and Alembic migrations.
  Firestore would require a data-model and data-access rewrite.
- **Firebase Authentication / Identity Platform:** deferred because the
  current Cognito integration already provides OIDC login and JWT validation.
- **Compute Engine or GKE:** rejected because the workload is a small
  containerized API and does not need a VM or cluster to operate.
- **Cloud SQL public application access:** rejected. Cloud Run uses the
  managed Cloud SQL connection and Unix socket; the database has no
  application-managed authorized network range.

## Consequences

The API container has a Cloud Run-specific Dockerfile without the AWS Lambda
Runtime Interface Client or AWS-only backend SDK dependencies and listens on
the injected `PORT`. Cloud Run connects to Cloud SQL through its managed
socket and reads the password from Secret Manager. Database migrations run at
API container startup, matching the current local entrypoint; before scaling
beyond this lab, move migrations to a one-off deployment job to avoid
concurrent migration attempts.

Cloud Run can scale to zero, but the selected Cloud SQL instance continues to
cost money while running. Stopping Cloud SQL still leaves storage charges, so
destroy the Terraform stack when the lab is complete. Public Cloud Run
invocation is required by Firebase Hosting's rewrite; the application still
requires Cognito bearer tokens for protected API routes.

The GCP port starts with an empty database and applies migrations; it does not
copy AWS production data. Cognito and the separate agenda-parser Lambda remain
on AWS. The weekly-report outbox API is present, but its AWS scheduler and
workers are not migrated and therefore do not process report requests from the
GCP database.
