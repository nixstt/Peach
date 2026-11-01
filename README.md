# Spry

Meetings, as one repository. `PROJECT.md` is the specification: the layout, the HTTP contract, and why this is a monorepo.

```bash
docker compose up --build
```

The API is at <http://localhost:8000> and the app at <http://localhost:3000>. Add a meeting and reload. If it is still there, the path is component, API, SQLAlchemy, Postgres, and back.

`make lint` and `make test` run inside those images. Postgres for tests is a separate database, `spry_test`.

## Deploy

These commands bill by the hour once they succeed. The load balancer is about $16 a month, Fargate at this size is about $9, and RDS `db.t4g.micro` is inside the free tier for the first 12 months of an account and about $12 a month after that. There is no NAT gateway. Run the destroy targets when the lab is over.

You do the account, any domain/DNS you want to configure, and AWS credentials. Nothing in this repository holds an access key.

1. Create an AWS account, turn on MFA for the root user, and stop using root. Create an IAM user for yourself and run `aws login` or `aws configure`.
2. `cp .env.example .env`. Set `REPORT_SENDER_EMAIL` and `REPORT_RECIPIENTS` to an email address you control. For a simple SES sandbox test, use the same address for both; SES requires the sender identity and each recipient to be verified.
3. Commit your work, then `make deploy-backend`. The first run takes about ten minutes, almost all of it the database. The image tag is the git commit SHA. This also creates the report bucket, builder and mailer functions, request queues, weekly schedule, outbox poller, and SES email identity.
4. Open the SES verification message sent to `REPORT_SENDER_EMAIL` and confirm the address. No paid domain or DKIM DNS records are needed for this email-identity setup.
5. Put `APP_DOMAIN` and `API_DOMAIN` in `.env` (two names on a domain you control, for example `app.example.com` and `api.example.com`).
6. `make domain`. If the domain is in Route 53, the script writes the records. Otherwise it prints a **validation** CNAME. Add that, wait until it resolves, and run `make domain` again. It then prints the **routing** records, which are a different pair: `api` to the load balancer, and later `app` to CloudFront.
7. `make deploy-frontend`. The page is HTTPS, so this refuses to build until the API URL is HTTPS too.
8. `make github-role`. Paste the two variables it prints into GitHub (Settings, Secrets and variables, Actions, Variables). The next push to `main` lints, tests, and deploys.

## Weekly meeting reports

The report builder queries the local database with `build_weekly_report("YYYY-Www")` and emits deterministic CSV bytes. ISO weeks use the same Europe/Kyiv calendar as the schedule; meeting timestamps are converted from UTC at the week boundaries. The Lambda writes each week to the same S3 key, `reports/YYYY-Www.csv`. The bucket is private and expires report objects after 90 days. A free S3 gateway endpoint connects the VPC Lambda to S3; neither the API nor builder needs a NAT gateway or an SQS network connection.

Every Monday at 07:00 Europe/Kyiv, EventBridge Scheduler enqueues the previous week. `make report-now WEEK=2026-W39` queues a rebuild for a chosen ISO week. The SQS queue has a DLQ after three receives. The authenticated app button adds a request to the database outbox; a five-minute scheduled poller picks it up, so the VPC API does not need to reach SQS. S3 uploads invoke a separate, non-VPC mailer. The mailer sends to `REPORT_RECIPIENTS`; for the lab, configure your own verified address there.

```bash
make report-now WEEK=2026-W39
aws s3 ls "s3://$(aws cloudformation describe-stacks --stack-name "${PROJECT_NAME:-spry}-backend" --query "Stacks[0].Outputs[?OutputKey=='ReportsBucketName'].OutputValue" --output text)/reports/" --recursive
aws logs tail "/aws/lambda/${PROJECT_NAME:-spry}-report-builder" --since 10m
aws logs tail "/aws/lambda/${PROJECT_NAME:-spry}-report-mailer" --since 10m
```

In the final deployment, the builder logs `trigger=schedule` for scheduled requests and `trigger=sqs` for manual queue requests; the mailer logs `trigger=s3`. A repeated S3 notification currently sends a repeated email. A durable idempotency record could live in DynamoDB, keyed by report object key and recipient, and be claimed with a conditional write. Since SES and DynamoDB cannot commit atomically, production code should track send state and accept/repair the narrow failure window between sending and recording success.

The builder has no SES route because it lives in the VPC. In us-east-1, a NAT gateway costs about `$0.045/hour` (roughly `$32.85/month`) plus data processing; an SES interface endpoint is roughly `$0.01/hour/AZ` (about `$7.30/month` per AZ, or `$14.60/month` across two AZs) plus data processing; the split builder/mailer costs no NAT or SES endpoint hourly charge (the S3 gateway endpoint has no hourly fee), only normal Lambda/S3/SES usage. For ten more emails a week, the split is the least fixed-cost option. At a million emails, keep the split, request SES production access, and size/monitor sending quotas and delivery reputation; email volume charges dominate, not a network endpoint. See [VPC pricing](https://aws.amazon.com/vpc/pricing/) and [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/) for current regional rates.

For a link that remains usable for a week, serve the private S3 object through CloudFront with Origin Access Control and use a CloudFront signed URL that expires in seven days. The CloudFront signing key is not the Lambda role's short-lived credentials.

The app's transactional outbox avoids adding an SQS interface endpoint: an API request is committed to PostgreSQL, and a VPC poller later builds its report. It trades a few minutes of delay for a durable request and no new hourly network endpoint. Requests are delivered to the configured report recipient list, so set that list to the app user for this lab.

Check DNS with `dig` before treating a failure as a bug in the app. `make logs-backend` tails the API.

```bash
make destroy-frontend
make destroy-backend
```

CloudFront deletion often takes fifteen minutes. Destroy the frontend first.

If an earlier Peach stack is still in this account (`peach-backend`, `peach-frontend`, `peach-github-oidc`), delete those too. They are not part of Spry and they keep billing.
