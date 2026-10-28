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
[[ -n "$(stack_status "${BACKEND_STACK}")" ]] || die "deploy the backend first: make deploy-backend"

API_URL="${VITE_API_URL:-$(stack_output "${BACKEND_STACK}" ApiUrl)}"
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
docker run --rm \
  -v "${ROOT}/frontend:/app" \
  -w /app \
  -e "VITE_API_URL=${API_URL}" \
  node:22-alpine \
  sh -c "npm ci && npm run build"
[[ -f "${ROOT}/frontend/dist/index.html" ]] || die "the build did not produce dist/index.html"

BUCKET="$(stack_output "${STACK}" BucketName)"
[[ -n "${BUCKET}" && "${BUCKET}" != "None" ]] || die "stack ${STACK} has no bucket"

log "uploading to s3://${BUCKET}"
aws s3 sync "${ROOT}/frontend/dist" "s3://${BUCKET}" --delete \
  --cache-control "max-age=0,must-revalidate"
aws s3 cp "${ROOT}/frontend/dist/assets" "s3://${BUCKET}/assets" --recursive \
  --cache-control "public,max-age=31536000,immutable"

SITE="$(stack_output "${STACK}" SiteUrl)"
SITE="${SITE%/}"
ORIGINS="http://localhost:3000,${SITE}"
if [[ -n "${APP_DOMAIN:-}" ]]; then
  ORIGINS="${ORIGINS},https://${APP_DOMAIN}"
fi

log "allowing the site through CORS on the API"
SKIP_BUILD=1 CORS_ORIGINS="${ORIGINS}" "${ROOT}/scripts/deploy-backend.sh" >/dev/null

log "frontend is at ${SITE}"
printf '%s\n' "${SITE}"
