#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws

STACK="${PROJECT_NAME}-github-oidc"
if [[ -z "$(stack_status "${STACK}")" ]]; then
  log "no ${STACK} stack"
  exit 0
fi

log "deleting ${STACK}. The GitHub OIDC provider is kept if this stack created it."
aws cloudformation delete-stack --stack-name "${STACK}"
aws cloudformation wait stack-delete-complete --stack-name "${STACK}"
log "deploy role is gone"
