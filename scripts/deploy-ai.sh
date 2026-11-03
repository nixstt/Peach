#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws
require_region

: "${PARSER_INPUT_USD_PER_MILLION:?Set PARSER_INPUT_USD_PER_MILLION from the current Bedrock model pricing}"
: "${PARSER_OUTPUT_USD_PER_MILLION:?Set PARSER_OUTPUT_USD_PER_MILLION from the current Bedrock model pricing}"

BACKEND_STACK="${PROJECT_NAME}-backend"
AUTH_STACK="${PROJECT_NAME}-auth"
FRONTEND_STACK="${PROJECT_NAME}-frontend"
AI_STACK="${PROJECT_NAME}-ai"
IMAGE="$(stack_param "${BACKEND_STACK}" ImageUri)"
[[ -n "${IMAGE}" && "${IMAGE}" != "None" ]] || die "backend stack has no ImageUri"

COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:-$(stack_output "${AUTH_STACK}" UserPoolId 2>/dev/null || true)}"
COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID:-$(stack_output "${AUTH_STACK}" UserPoolClientId 2>/dev/null || true)}"
[[ -n "${COGNITO_USER_POOL_ID}" && "${COGNITO_CLIENT_ID}" ]] \
  || die "deploy the Cognito auth stack before deploying the agenda parser"

SITE_URL="$(stack_output "${FRONTEND_STACK}" SiteUrl 2>/dev/null || true)"
ORIGINS="${CORS_ORIGINS:-http://localhost:3000}"
if [[ -n "${SITE_URL}" && "${SITE_URL}" != "None" ]]; then
  ORIGINS="${ORIGINS},${SITE_URL%/}"
fi
if [[ -n "${APP_DOMAIN:-}" ]]; then
  ORIGINS="${ORIGINS},https://${APP_DOMAIN}"
fi

BUDGET_EMAIL="${BUDGET_EMAIL:-}"
if [[ -z "${BUDGET_EMAIL}" ]]; then
  BUDGET_EMAIL="$(aws cloudformation describe-stacks --stack-name "${BACKEND_STACK}" \
    --query "Stacks[0].Parameters[?ParameterKey=='ReportRecipients'].ParameterValue | [0]" \
    --output text 2>/dev/null || true)"
fi
if [[ "${BUDGET_EMAIL}" == "None" ]]; then
  BUDGET_EMAIL=""
fi
BUDGET_EMAIL="${BUDGET_EMAIL%%,*}"
[[ -n "${BUDGET_EMAIL}" ]] || die "set BUDGET_EMAIL or configure REPORT_RECIPIENTS for the $5 monthly budget alert"

drop_failed_stack "${AI_STACK}"
log "deploying the authenticated agenda parser"
aws cloudformation deploy \
  --stack-name "${AI_STACK}" \
  --template-file "$(cygpath -w "${ROOT}/infra/ai.yml")" \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "ImageUri=${IMAGE}" \
    "CognitoUserPoolId=${COGNITO_USER_POOL_ID}" \
    "CognitoClientId=${COGNITO_CLIENT_ID}" \
    "CorsOrigins=${ORIGINS}" \
    "ParserModel=${PARSER_MODEL:-anthropic.claude-opus-5-5}" \
    "ParserInputUsdPerMillion=${PARSER_INPUT_USD_PER_MILLION}" \
    "ParserOutputUsdPerMillion=${PARSER_OUTPUT_USD_PER_MILLION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUDGET_NAME="${PROJECT_NAME}-monthly-ai-budget"
EXISTING_BUDGET="$(aws budgets describe-budgets --account-id "${ACCOUNT_ID}" \
  --region us-east-1 \
  --query "Budgets[?BudgetName=='${BUDGET_NAME}'].BudgetName | [0]" --output text)"
if [[ "${EXISTING_BUDGET}" == "None" || -z "${EXISTING_BUDGET}" ]]; then
  BUDGET_JSON="$(printf '{"BudgetName":"%s","BudgetLimit":{"Amount":"5","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' "${BUDGET_NAME}")"
  NOTIFICATIONS_JSON="$(printf '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":100,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"%s"}]}]' "${BUDGET_EMAIL}")"
  aws budgets create-budget \
    --account-id "${ACCOUNT_ID}" \
    --region us-east-1 \
    --budget "${BUDGET_JSON}" \
    --notifications-with-subscribers "${NOTIFICATIONS_JSON}" \
    >/dev/null
fi

PARSER_URL="$(stack_output "${AI_STACK}" ParserUrl)"
log "agenda parser is at ${PARSER_URL}"
printf '%s\n' "${PARSER_URL}"
