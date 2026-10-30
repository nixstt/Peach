#!/usr/bin/env bash
# Delete the Cognito auth stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws
require_region

STACK="${PROJECT_NAME}-auth"
[[ -n "$(stack_status "${STACK}")" ]] || { log "${STACK} does not exist"; exit 0; }

log "deleting stack ${STACK}"
aws cloudformation delete-stack --stack-name "${STACK}"
aws cloudformation wait stack-delete-complete --stack-name "${STACK}"
log "done"
