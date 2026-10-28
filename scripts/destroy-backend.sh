#!/usr/bin/env bash
# Delete the API stack, including the database, then the image repository.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws

STACK="${PROJECT_NAME}-backend"
if [[ -z "$(stack_status "${STACK}")" ]]; then
  log "no ${STACK} stack"
else
  log "deleting ${STACK}. RDS and the load balancer can take ten to fifteen minutes."
  aws cloudformation delete-stack --stack-name "${STACK}"
  aws cloudformation wait stack-delete-complete --stack-name "${STACK}"
fi

if aws ecr describe-repositories --repository-names "${PROJECT_NAME}-backend" >/dev/null 2>&1; then
  log "deleting ECR repository ${PROJECT_NAME}-backend"
  aws ecr delete-repository --repository-name "${PROJECT_NAME}-backend" --force >/dev/null
fi

if aws secretsmanager describe-secret --secret-id "${PROJECT_NAME}/db-password" >/dev/null 2>&1; then
  aws secretsmanager delete-secret --secret-id "${PROJECT_NAME}/db-password" \
    --force-delete-without-recovery >/dev/null || true
fi

log "backend resources are gone"
