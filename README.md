# Spry

Meetings, as one repository. `PROJECT.md` is the specification: the layout, the HTTP contract, and why this is a monorepo.

```bash
docker compose up --build
```

The API is at <http://localhost:8000> and the app at <http://localhost:3000>. Add a meeting and reload. If it is still there, the path is component, API, SQLAlchemy, Postgres, and back.

`make lint` and `make test` run inside those images. Postgres for tests is a separate database, `spry_test`.

## Deploy

These commands bill by the hour once they succeed. The load balancer is about $16 a month, Fargate at this size is about $9, and RDS `db.t4g.micro` is inside the free tier for the first 12 months of an account and about $12 a month after that. There is no NAT gateway. Run the destroy targets when the lab is over.

You do the account, the domain, and the DNS. Nothing in this repository holds an access key.

1. Create an AWS account, turn on MFA for the root user, and stop using root. Create an IAM user for yourself and run `aws login` or `aws configure`.
2. `cp .env.example .env` and leave the key fields absent.
3. Commit your work, then `make deploy-backend`. The first run takes about ten minutes, almost all of it the database. The image tag is the git commit SHA.
4. Put `APP_DOMAIN` and `API_DOMAIN` in `.env` (two names on a domain you control, for example `app.example.com` and `api.example.com`).
5. `make domain`. If the domain is in Route 53, the script writes the records. Otherwise it prints a **validation** CNAME. Add that, wait until it resolves, and run `make domain` again. It then prints the **routing** records, which are a different pair: `api` to the load balancer, and later `app` to CloudFront.
6. `make deploy-frontend`. The page is HTTPS, so this refuses to build until the API URL is HTTPS too.
7. `make github-role`. Paste the two variables it prints into GitHub (Settings, Secrets and variables, Actions, Variables). The next push to `main` lints, tests, and deploys.

Check DNS with `dig` before treating a failure as a bug in the app. `make logs-backend` tails the API.

```bash
make destroy-frontend
make destroy-backend
```

CloudFront deletion often takes fifteen minutes. Destroy the frontend first.

If an earlier Peach stack is still in this account (`peach-backend`, `peach-frontend`, `peach-github-oidc`), delete those too. They are not part of Spry and they keep billing.
