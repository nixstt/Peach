#!/usr/bin/env bash
# Deploy the Cognito user pool with Google federation.
# Run after setting GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
# COGNITO_DOMAIN_PREFIX in .env.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws
require_region

: "${GOOGLE_CLIENT_ID:?Set GOOGLE_CLIENT_ID in .env}"
: "${GOOGLE_CLIENT_SECRET:?Set GOOGLE_CLIENT_SECRET in .env}"
: "${COGNITO_DOMAIN_PREFIX:?Set COGNITO_DOMAIN_PREFIX in .env}"

STACK="${PROJECT_NAME}-auth"

# Callback / logout URLs: the deployed site plus localhost for development.
FRONTEND_STACK="${PROJECT_NAME}-frontend"
if [[ -n "$(stack_status "${FRONTEND_STACK}" 2>/dev/null || true)" ]]; then
  SITE_URL="$(stack_output "${FRONTEND_STACK}" SiteUrl)"
  SITE_URL="${SITE_URL%/}"
else
  log "frontend stack not found in CloudFormation – using default deployed URL"
  SITE_URL="https://lruc3lxk63eduqfsfqfxm26fr40rliuh.lambda-url.eu-north-1.on.aws"
fi

# Include exact callback paths, roots, and localhost variants to prevent redirect_mismatch
CALLBACK_URLS="${SITE_URL}/auth/callback/,${SITE_URL}/auth/callback,${SITE_URL}/,${SITE_URL},http://localhost:3000/auth/callback/,http://localhost:3000/auth/callback,http://localhost:3000/,http://localhost:3000"
LOGOUT_URLS="${SITE_URL}/,${SITE_URL},http://localhost:3000/,http://localhost:3000"

overrides=(
  "ProjectName=${PROJECT_NAME}"
  "GoogleClientId=${GOOGLE_CLIENT_ID}"
  "GoogleClientSecret=${GOOGLE_CLIENT_SECRET}"
  "CognitoDomainPrefix=${COGNITO_DOMAIN_PREFIX}"
  "CallbackUrls=${CALLBACK_URLS}"
  "LogoutUrls=${LOGOUT_URLS}"
)

drop_failed_stack "${STACK}"

log "deploying stack ${STACK}"
if ! aws cloudformation deploy \
  --stack-name "${STACK}" \
  --template-file "${ROOT}/infra/auth.yaml" \
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

USER_POOL_ID="$(stack_output "${STACK}" UserPoolId)"
CLIENT_ID="$(stack_output "${STACK}" UserPoolClientId)"
DOMAIN="$(stack_output "${STACK}" CognitoDomain)"
AUTHORITY="$(stack_output "${STACK}" AuthorityUrl)"

log "auth stack deployed successfully"
log "  UserPoolId:    ${USER_POOL_ID}"
log "  ClientId:      ${CLIENT_ID}"
log "  CognitoDomain: ${DOMAIN}"
log "  AuthorityUrl:  ${AUTHORITY}"
log ""
log "Update your .env file with these values:"
log "  COGNITO_USER_POOL_ID=${USER_POOL_ID}"
log "  COGNITO_CLIENT_ID=${CLIENT_ID}"
log ""
log "Google Cloud Console OAuth 2.0 Web Client configuration:"
log "  Authorised JavaScript origins:"
log "    ${DOMAIN}"
log "  Authorised redirect URIs:"
log "    ${DOMAIN}/oauth2/idpresponse"
