# Spry on Google Cloud

This stack is independent from the AWS CloudFormation templates. It deploys a
Cloud Run API, Cloud SQL for PostgreSQL, Artifact Registry, and a generated
database password in Secret Manager. Firebase Hosting serves the Vite build;
[`../firebase.json`](../firebase.json) rewrites `/api/**` to Cloud Run.

The example region is `us-central1`. Cloud SQL is billable while running even
when the API has no traffic. Do not apply this stack unless you have billing
enabled and accept the charges. Run `terraform destroy` in this directory when
you finish; stopped Cloud SQL still incurs storage charges.

## Initialize and validate

Install Terraform 1.6 or newer. Copy `terraform.tfvars.example` to
`terraform.tfvars` and set your project ID. The project must have billing
enabled and your user must be allowed to enable APIs, create Cloud SQL,
Artifact Registry and Cloud Run resources, and manage IAM.

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set project_id, cognito_user_pool_id, and
# cognito_client_id from the existing AWS Cognito user pool/app client.
terraform init
terraform validate
```

No Google credentials are needed for `init` or `validate`. `plan` and `apply`
require Google credentials and a project. The default Terraform state is
local to this `gcp/` directory and is ignored by git. To use the required
separate HCP Terraform workspace, configure the HCP Terraform Cloud backend
for a workspace named `spry-gcp` before applying: create that workspace in
HCP Terraform, copy `backend.tf.example` to the ignored `backend.tf`, replace
the organization placeholder, then rerun `terraform init` and confirm the
state migration. Do not share the AWS workspace or state. Keep the local state
private if you do not use HCP because it contains the generated database
password.

## Apply and deploy the API

Terraform first creates the infrastructure and uses Google's public hello
image as a temporary Cloud Run revision. It does not contain application
code. Build and push the real image, then set `backend_image` to the pushed
image and apply again:

```powershell
$project = "YOUR_PROJECT_ID"
$region = "us-central1"
$repo = "spry-containers"
$image = "$region-docker.pkg.dev/$project/$repo/api:lab9"

gcloud auth login
gcloud config set project $project
terraform apply
gcloud auth configure-docker "$region-docker.pkg.dev"
docker build -f ..\backend\Dockerfile.cloudrun -t $image ..\backend
docker push $image
terraform apply -var="backend_image=$image"
```

The selected project must have billing enabled. Terraform enables the required
service APIs and creates a 10 GiB SSD `db-f1-micro` Cloud SQL instance. Cloud
Run scales to zero, but Cloud SQL does not. `terraform destroy` deletes the
database and its data. This deployment starts with an empty database and
applies the checked-in Alembic migrations at API startup; it does not copy
production Aurora/RDS records.

## Deploy Firebase Hosting

Enable Firebase for the same Google Cloud project in the Firebase console.
Add the Firebase Hosting origin to the existing Cognito app client's callback
and sign-out URL allowlists; the app's API still verifies Cognito access
tokens. Build the site for Firebase Hosting (empty API base uses the same
origin and the rewrite in `firebase.json`):

```powershell
Push-Location ..\frontend
$env:VITE_API_URL = ""
npm ci
npm run build
Pop-Location
firebase use $project
Push-Location ..
firebase deploy --only hosting
Pop-Location
```

For the SPA sign-in to work, also set the Vite Cognito variables used by the
existing frontend (`VITE_COGNITO_USER_POOL_ID`, `VITE_COGNITO_CLIENT_ID`,
`VITE_COGNITO_DOMAIN`, and `VITE_AWS_REGION`) before building.

The deployment uses a Firebase Hosting rewrite to reach the public Cloud Run
service. Cloud Run accepts requests from Hosting, while protected API routes
continue requiring a valid Cognito bearer token.

## Local Cloud Run-compatible fallback

Start the existing local PostgreSQL and frontend, and run the Cloud Run
Dockerfile as a normal HTTP container:

```powershell
docker compose up -d postgres
docker build -f backend\Dockerfile.cloudrun -t spry-api-cloudrun backend
docker run --rm --name spry-api-cloudrun --network spry_default `
  -e PORT=8080 `
  -e DB_USER=postgres -e DB_PASSWORD=postgres `
  -e DB_HOST=postgres -e DB_PORT=5432 -e DB_NAME=postgres `
  -e CORS_ORIGINS=http://localhost:3000 `
  -p 8080:8080 spry-api-cloudrun
```

Run the frontend with `VITE_API_URL=http://localhost:8080`. Use the existing
Cognito development configuration if you want to test authenticated API
routes; do not disable token validation for the demo. From the host, verify
database connectivity with `http://localhost:8080/health` and the protected
meeting read with a valid access token:

```powershell
curl.exe -H "Authorization: Bearer YOUR_COGNITO_ACCESS_TOKEN" `
  http://localhost:8080/api/meetings
```

`/health` also executes `SELECT 1` against PostgreSQL. Do not paste a real
access token into source control, screenshots, or the lab submission.
