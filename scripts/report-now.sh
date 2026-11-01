#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws

[[ "${WEEK:-}" =~ ^[0-9]{4}-W[0-9]{2}$ ]] \
  || die "usage: make report-now WEEK=2026-W39"

STACK="${PROJECT_NAME}-backend"
QUEUE_URL="$(stack_output "${STACK}" ReportRequestsQueueUrl)"
[[ -n "${QUEUE_URL}" && "${QUEUE_URL}" != "None" ]] \
  || die "no report queue found; deploy the backend first"

aws sqs send-message \
  --queue-url "${QUEUE_URL}" \
  --message-body "{\"week\":\"${WEEK}\",\"source\":\"sqs\"}" \
  --query MessageId \
  --output text
