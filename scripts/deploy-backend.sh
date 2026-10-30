#!/usr/bin/env bash
# Build the backend image, push it to ECR tagged with the git commit, and
# roll the ECS service. GitHub Actions runs this same script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws
require_region

STACK="${PROJECT_NAME}-backend"
REPO_NAME="${PROJECT_NAME}-backend"
SECRET_NAME="${PROJECT_NAME}/db-password"

drop_failed_stack "${STACK}"
STATUS="$(stack_status "${STACK}")"

if [[ "${SKIP_BUILD:-}" == "1" ]]; then
  [[ -n "${STATUS}" ]] || die "there is no ${STACK} stack yet. Run make deploy-backend first."
  IMAGE="$(stack_param "${STACK}" ImageUri)"
  [[ -n "${IMAGE}" && "${IMAGE}" != "None" ]] || die "the stack has no ImageUri"
else
  command -v docker >/dev/null 2>&1 || die "Docker is required to build the image"
  if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
    die "commit or stash changes before deploying. The image tag is the commit SHA, so a dirty tree would make the tag lie."
  fi
  TAG="$(git -C "${ROOT}" rev-parse HEAD)"
  ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
  REGISTRY="${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  IMAGE="${REGISTRY}/${REPO_NAME}:${TAG}"

  if ! aws ecr describe-repositories --repository-names "${REPO_NAME}" >/dev/null 2>&1; then
    log "creating ECR repository ${REPO_NAME}"
    aws ecr create-repository --repository-name "${REPO_NAME}" \
      --image-scanning-configuration scanOnPush=true \
      --tags Key=PROJECT_NAME,Value="${PROJECT_NAME}" >/dev/null
  fi
  aws ecr put-lifecycle-policy --repository-name "${REPO_NAME}" --lifecycle-policy-text \
    '{"rules":[{"rulePriority":1,"description":"keep last 10","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}' \
    >/dev/null

  log "building ${IMAGE}"
  aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${REGISTRY}"
  docker build --platform linux/amd64 -t "${IMAGE}" "${ROOT}/backend"
  docker push "${IMAGE}"
fi

overrides=("ProjectName=${PROJECT_NAME}" "ImageUri=${IMAGE}" "DesiredCount=1")
[[ -n "${CORS_ORIGINS:-}" ]] && overrides+=("CorsOrigins=${CORS_ORIGINS}")
[[ -n "${ACM_CERTIFICATE_ARN:-}" ]] && overrides+=("CertificateArn=${ACM_CERTIFICATE_ARN}")
[[ -n "${API_DOMAIN:-}" ]] && overrides+=("ApiDomain=${API_DOMAIN}")
[[ -n "${HOSTED_ZONE_ID:-}" ]] && overrides+=("HostedZoneId=${HOSTED_ZONE_ID}")
AUTH_STACK="${PROJECT_NAME}-auth"
if [[ -n "$(stack_status "${AUTH_STACK}" 2>/dev/null || true)" ]]; then
  COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:-$(stack_output "${AUTH_STACK}" UserPoolId)}"
  COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID:-$(stack_output "${AUTH_STACK}" UserPoolClientId)}"
  [[ -n "${COGNITO_USER_POOL_ID:-}" ]] && overrides+=("CognitoUserPoolId=${COGNITO_USER_POOL_ID}")
  [[ -n "${COGNITO_CLIENT_ID:-}" ]] && overrides+=("CognitoClientId=${COGNITO_CLIENT_ID}")
fi

if [[ -z "${STATUS}" ]]; then
  log "this creates an Application Load Balancer, a Fargate service, and an RDS Postgres instance"
  log "all three bill by the hour. There is no NAT gateway. Run make destroy-backend when you are done."
  VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
  [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]] || die "no default VPC in ${AWS_REGION}"
  SUBNET_CSV="$(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="${VPC_ID}" Name=default-for-az,Values=true \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ',')"
  SUBNET_COUNT="$(printf '%s' "${SUBNET_CSV}" | tr ',' '\n' | grep -c .)"
  [[ "${SUBNET_COUNT}" -ge 2 ]] || die "RDS needs subnets in two availability zones"
  ENGINE_VERSION="$(aws rds describe-db-engine-versions --engine postgres \
    --query "DBEngineVersions[?starts_with(EngineVersion, '16.')].EngineVersion" --output text \
    | tr '\t' '\n' | sort -V | tail -1)"
  [[ -n "${ENGINE_VERSION}" ]] || die "could not find a Postgres 16 version in RDS"

  if aws secretsmanager describe-secret --secret-id "${SECRET_NAME}" >/dev/null 2>&1; then
    PASS="$(aws secretsmanager get-secret-value --secret-id "${SECRET_NAME}" --query SecretString --output text)"
    SECRET_ARN="$(aws secretsmanager describe-secret --secret-id "${SECRET_NAME}" --query ARN --output text)"
  else
    PASS="$(openssl rand -hex 20)"
    SECRET_ARN="$(aws secretsmanager create-secret --name "${SECRET_NAME}" --secret-string "${PASS}" \
      --tags Key=PROJECT_NAME,Value="${PROJECT_NAME}" --query ARN --output text)"
  fi
  overrides+=(
    "VpcId=${VPC_ID}"
    "PublicSubnetIds=${SUBNET_CSV}"
    "EngineVersion=${ENGINE_VERSION}"
    "DBPassword=${PASS}"
    "DbPasswordSecretArn=${SECRET_ARN}"
  )
fi

log "updating stack ${STACK}"
if ! aws cloudformation deploy \
  --stack-name "${STACK}" \
  --template-file "${ROOT}/infra/backend.yaml" \
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

log "waiting for the service to become stable"
aws ecs wait services-stable --cluster "${PROJECT_NAME}" --services "${PROJECT_NAME}-backend"

API_URL="$(stack_output "${STACK}" ApiUrl)"
log "backend is at ${API_URL}"
printf '%s\n' "${API_URL}"
