#!/usr/bin/env bash
# Shared helpers for the deploy scripts. Source this; do not execute it.

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

load_env() {
  local root="$1"
  if [[ -f "${root}/.env" ]]; then
    local preset
    preset="$(export -p)"
    set -a
    # shellcheck disable=SC1091
    source "${root}/.env"
    set +a
    eval "${preset}"
  fi
  local var
  for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
    [[ -n "${!var:-}" ]] || unset "${var}"
  done
  PROJECT_NAME="${PROJECT_NAME:-spry}"
  if [[ -z "${AWS_REGION:-}" && -z "${AWS_DEFAULT_REGION:-}" ]]; then
    AWS_REGION="$(aws configure get region 2>/dev/null || true)"
  fi
  AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
  export AWS_DEFAULT_REGION="${AWS_REGION}"
  export PROJECT_NAME AWS_REGION
}

require_aws() {
  command -v aws >/dev/null 2>&1 || die "the AWS CLI is required"
  aws sts get-caller-identity >/dev/null 2>&1 \
    || die "no AWS credentials. Run 'aws login' or 'aws configure'. Do not put keys in the repository."
}

require_region() {
  # A custom-domain certificate for CloudFront still has to be requested in
  # us-east-1. The services themselves run in whatever region the CLI is using.
  :
}

stack_status() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].StackStatus" --output text 2>/dev/null || true
}

stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text 2>/dev/null || true
}

stack_param() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Parameters[?ParameterKey=='$2'].ParameterValue" --output text 2>/dev/null || true
}

drop_failed_stack() {
  local name="$1"
  local status
  status="$(stack_status "${name}")"
  case "${status}" in
    ROLLBACK_COMPLETE|ROLLBACK_FAILED|DELETE_FAILED)
      log "removing failed stack ${name} (${status})"
      aws cloudformation delete-stack --stack-name "${name}"
      aws cloudformation wait stack-delete-complete --stack-name "${name}"
      ;;
  esac
}
