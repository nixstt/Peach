#!/usr/bin/env bash
# Create the role GitHub Actions assumes. No access key is created.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws

STACK="${PROJECT_NAME}-github-oidc"
REPO="${GITHUB_REPO:-}"
if [[ -z "${REPO}" ]]; then
  ORIGIN="$(git -C "${ROOT}" remote get-url origin 2>/dev/null || true)"
  REPO="$(printf '%s' "${ORIGIN}" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
fi
[[ "${REPO}" == */* ]] || die "could not work out owner/repo. Set GITHUB_REPO in .env."

SUBJECT_CLAIM="${GITHUB_SUBJECT_CLAIM:-ref:refs/heads/main}"
log "trusting only repo:${REPO}:${SUBJECT_CLAIM}"
log "StringEquals is exact. A star in that subject is a literal character, not a wildcard."

EXISTING="$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')]|[0].Arn" \
  --output text 2>/dev/null || true)"
[[ "${EXISTING}" == "None" ]] && EXISTING=""

if ! aws cloudformation deploy \
  --stack-name "${STACK}" \
  --template-file "${ROOT}/infra/github-oidc.yaml" \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "GitHubRepo=${REPO}" \
    "SubjectClaim=${SUBJECT_CLAIM}" \
    "ExistingProviderArn=${EXISTING}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"; then
  warn "deploy failed. Recent stack errors:"
  aws cloudformation describe-stack-events --stack-name "${STACK}" --max-items 20 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

ROLE_ARN="$(stack_output "${STACK}" RoleArn)"
log "role ready: ${ROLE_ARN}"
echo
echo "  Set these repository variables (Settings -> Secrets and variables -> Actions -> Variables)."
echo "  They are not secrets. The role trusts only this repository on main."
echo
echo "    AWS_DEPLOY_ROLE_ARN = ${ROLE_ARN}"
echo "    AWS_REGION          = ${AWS_REGION}"
echo
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  log "setting the variables with gh"
  gh variable set AWS_DEPLOY_ROLE_ARN --repo "${REPO}" --body "${ROLE_ARN}"
  gh variable set AWS_REGION --repo "${REPO}" --body "${AWS_REGION}"
else
  echo "  gh is not installed or not logged in, so paste the variables yourself."
  echo
fi
