# Lab 9 — Spry cost estimate

Planning estimates only; this is not a live bill or a saved Pricing Calculator
export. The GCP figures use the Lab 9 rates supplied with the assignment for
`us-central1`, 730 hours/month, one 10 GiB SSD Cloud SQL instance, no tax, and
Cloud Run usage within its free quota. Firebase Hosting is assumed to remain
within its free plan. Exact rates and free-tier eligibility depend on region,
account, and current Google pricing.

## Profile comparison

For the activity-based rows, assume the database is manually started during
the listed active hours and stopped otherwise. This is an estimate, not
automatic scaling: the Terraform deployment leaves Cloud SQL running until
you stop it or destroy the stack. Stopped Cloud SQL still bills storage.

| Traffic profile | Active hours/month | GCP Cloud Run + Firebase | GCP Cloud SQL compute | GCP storage | GCP estimate | AWS estimate* |
|---|---:|---:|---:|---:|---:|---:|
| Nobody; Cloud SQL stopped | 0 | $0 | $0 | $1.70 | **$1.70** | **about $16 + RDS storage** |
| Class demos: 10 × 2 h | 20 | $0 | $0.21 | $1.70 | **$1.91** | **about $16.58 + RDS storage** |
| Office hours: 8 h × 22 days | 176 | $0 | $1.85 | $1.70 | **$3.55** | **about $21.06 + RDS storage** |
| Busy around the clock | 730 | $0 | $7.67 | $1.70 | **$9.37** | **about $37 + RDS storage** |

GCP Cloud SQL compute is estimated at `$0.0105/hour`; storage is
`10 GiB × $0.17/GiB-month`. Cloud Run stays within the supplied monthly free
allowances (2 million requests, 180,000 vCPU-seconds, 360,000 GiB-seconds).
Artifact Registry, Secret Manager, and logs are assumed to remain at negligible
or free-tier usage.

*The AWS figures are based on this repository's current default architecture:
approximately `$16/month` for its always-on Application Load Balancer, `$9`
for a continuously running Fargate task, and `$12` for continuously running
RDS `db.t4g.micro`, before RDS storage and traffic. For the activity-based
rows, the estimate assumes ECS and RDS are manually stopped outside active
hours; the ALB remains. This AWS stack does not automatically scale to zero,
so if left deployed as configured its total remains roughly `$37/month` plus
RDS storage for every traffic profile. RDS stop periods also have AWS service
limits and require operations work.*

The fixed line that most affects the comparison is the AWS ALB: it continues
to cost money even when the API task is stopped. On GCP the corresponding
trap is Cloud SQL, which does not scale to zero with Cloud Run. If you leave
the Terraform deployment running through an idle month, estimate about
`$9.37` for GCP's Cloud SQL compute and storage rather than the stopped
database row's `$1.70`.

These are estimates derived from the supplied handout prices and the
repository's documented AWS estimates, not independently verified calculator
results. If the instructor requires calculator evidence, enter the same
resource sizes and uptime assumptions into the Google Cloud and AWS Pricing
Calculators and save their outputs.
