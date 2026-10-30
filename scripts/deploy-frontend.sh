#!/usr/bin/env bash
# Build the Vite bundle against the deployed API and publish it.
# API Gateway reads the objects over HTTPS and is the public URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws
require_region
command -v docker >/dev/null 2>&1 || die "Docker is required to build the frontend"

STACK="${PROJECT_NAME}-frontend"
BACKEND_STACK="${PROJECT_NAME}-backend"

API_URL="${VITE_API_URL:-$(stack_output "${BACKEND_STACK}" ApiUrl 2>/dev/null || true)}"
if [[ -z "${API_URL}" || "${API_URL}" == "None" ]]; then
  API_URL="https://7eaqqj55z1.execute-api.eu-north-1.amazonaws.com"
fi
[[ "${API_URL}" == https://* ]] || die "the API URL is ${API_URL}. An HTTPS page cannot call an HTTP API."

drop_failed_stack "${STACK}"

overrides=("ProjectName=${PROJECT_NAME}")

log "creating the bucket and API if they are not there yet"
if ! aws cloudformation deploy \
  --stack-name "${STACK}" \
  --template-file "${ROOT}/infra/frontend.yaml" \
  --parameter-overrides "${overrides[@]}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed. Recent stack errors:"
  aws cloudformation describe-stack-events --stack-name "${STACK}" --max-items 25 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

log "building the frontend against ${API_URL}"

AUTH_STACK="${PROJECT_NAME}-auth"
COGNITO_AUTHORITY="${COGNITO_AUTHORITY:-$(stack_output "${AUTH_STACK}" AuthorityUrl 2>/dev/null || true)}"
COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID:-$(stack_output "${AUTH_STACK}" UserPoolClientId 2>/dev/null || true)}"
COGNITO_DOMAIN="${COGNITO_DOMAIN:-$(stack_output "${AUTH_STACK}" CognitoDomain 2>/dev/null || true)}"

SITE_URL="$(stack_output "${STACK}" SiteUrl 2>/dev/null || true)"
if [[ -z "${SITE_URL}" || "${SITE_URL}" == "None" ]]; then
  SITE_URL="https://lruc3lxk63eduqfsfqfxm26fr40rliuh.lambda-url.eu-north-1.on.aws"
fi
SITE_URL="${SITE_URL%/}"
AUTH_REDIRECT_URI="${SITE_URL}/auth/callback/"
AUTH_LOGOUT_URI="${SITE_URL}/"

docker run --rm \
  -v "${ROOT}/frontend:/app" \
  -w /app \
  -e "VITE_API_URL=${API_URL}" \
  -e "VITE_COGNITO_AUTHORITY=${COGNITO_AUTHORITY:-}" \
  -e "VITE_COGNITO_CLIENT_ID=${COGNITO_CLIENT_ID:-}" \
  -e "VITE_COGNITO_DOMAIN=${COGNITO_DOMAIN:-}" \
  -e "VITE_AUTH_REDIRECT_URI=${AUTH_REDIRECT_URI}" \
  -e "VITE_AUTH_LOGOUT_URI=${AUTH_LOGOUT_URI}" \
  node:22-alpine \
  sh -c "npm ci && npm run build"
[[ -f "${ROOT}/frontend/dist/index.html" ]] || die "the build did not produce dist/index.html"

BUCKET="$(stack_output "${STACK}" BucketName 2>/dev/null || true)"
[[ -n "${BUCKET}" && "${BUCKET}" != "None" ]] || die "stack ${STACK} has no bucket"

log "uploading to s3://${BUCKET}"
aws s3 sync "${ROOT}/frontend/dist" "s3://${BUCKET}" --delete \
  --cache-control "max-age=0,must-revalidate"
aws s3 cp "${ROOT}/frontend/dist/assets" "s3://${BUCKET}/assets" --recursive \
  --cache-control "public,max-age=31536000,immutable"

ORIGINS="http://localhost:3000,${SITE_URL}"
if [[ -n "${APP_DOMAIN:-}" ]]; then
  ORIGINS="${ORIGINS},https://${APP_DOMAIN}"
fi

log "allowing the site through CORS on the API"
SKIP_BUILD=1 CORS_ORIGINS="${ORIGINS}" "${ROOT}/scripts/deploy-backend.sh" >/dev/null

log "frontend is at ${SITE_URL}"
printf '%s\n' "${SITE_URL}"
