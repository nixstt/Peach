#!/usr/bin/env bash
# Empty the bucket, then delete the distribution. CloudFront deletion is slow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws

STACK="${PROJECT_NAME}-frontend"
if [[ -z "$(stack_status "${STACK}")" ]]; then
  log "no ${STACK} stack"
  exit 0
fi

BUCKET="$(stack_output "${STACK}" BucketName)"
if [[ -n "${BUCKET}" && "${BUCKET}" != "None" ]]; then
  log "emptying s3://${BUCKET}"
  aws s3 rm "s3://${BUCKET}" --recursive
fi

log "deleting ${STACK}. The distribution often takes about fifteen minutes to go away."
aws cloudformation delete-stack --stack-name "${STACK}"
aws cloudformation wait stack-delete-complete --stack-name "${STACK}"
log "frontend resources are gone"
