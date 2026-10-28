#!/usr/bin/env bash
# One certificate for the app hostname and the api hostname, then point DNS at
# CloudFront and the load balancer.
#
# A validation CNAME proves you control the domain. ACM issues the certificate
# only after that record resolves. A routing record (alias here, or a CNAME
# you add yourself) is a different record: it sends traffic to AWS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/common.sh"
load_env "${ROOT}"
require_aws
require_region

[[ -n "${APP_DOMAIN:-}" && -n "${API_DOMAIN:-}" ]] \
  || die "set APP_DOMAIN and API_DOMAIN in .env (see .env.example)"
[[ -n "$(stack_status "${PROJECT_NAME}-backend")" ]] \
  || die "deploy the backend first: make deploy-backend"

upsert_env() {
  python3 - "$ROOT/.env" "$1" "$2" <<'PY'
import pathlib, sys
path, key, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines() if path.exists() else []
seen = False
out = []
for line in lines:
    if "=" in line and not line.startswith("#") and line.split("=", 1)[0] == key:
        out.append(f"{key}={value}")
        seen = True
    else:
        out.append(line)
if not seen:
    out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
PY
}

if [[ -z "${ACM_CERTIFICATE_ARN:-}" ]]; then
  log "requesting a certificate for ${APP_DOMAIN} and ${API_DOMAIN}"
  TOKEN="$(printf '%s' "${APP_DOMAIN}${API_DOMAIN}" | tr -cd 'A-Za-z0-9' | cut -c1-32)"
  ACM_CERTIFICATE_ARN="$(aws acm request-certificate \
    --region us-east-1 \
    --domain-name "${APP_DOMAIN}" \
    --subject-alternative-names "${API_DOMAIN}" \
    --validation-method DNS \
    --idempotency-token "${TOKEN}" \
    --query CertificateArn --output text)"
  upsert_env ACM_CERTIFICATE_ARN "${ACM_CERTIFICATE_ARN}"
fi

log "waiting for ACM to publish the validation records"
RECORDS=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  RECORDS="$(aws acm describe-certificate --region us-east-1 \
    --certificate-arn "${ACM_CERTIFICATE_ARN}" \
    --query "Certificate.DomainValidationOptions[].ResourceRecord" --output json)"
  if [[ "${RECORDS}" != "[]" && "${RECORDS}" != "null" && "${RECORDS}" != *"null"* ]]; then
    break
  fi
  sleep 5
done

STATUS="$(aws acm describe-certificate --region us-east-1 \
  --certificate-arn "${ACM_CERTIFICATE_ARN}" --query Certificate.Status --output text)"

zone_for() {
  local name="$1"
  name="${name%.}"
  local candidate zone
  candidate="${name}"
  while [[ "${candidate}" == *.* ]]; do
    zone="$(aws route53 list-hosted-zones-by-name --dns-name "${candidate}" \
      --query "HostedZones[?Name=='${candidate}.'].Id | [0]" --output text 2>/dev/null || true)"
    if [[ -n "${zone}" && "${zone}" != "None" ]]; then
      printf '%s' "${zone#/hostedzone/}"
      return 0
    fi
    candidate="${candidate#*.}"
  done
  return 1
}

if [[ "${STATUS}" != "ISSUED" ]]; then
  echo
  echo "  Validation CNAME. This proves you control the domain. The certificate"
  echo "  is not issued until it resolves. It does not send visitors anywhere."
  echo
  python3 -c 'import json,sys
records=json.load(sys.stdin)
for record in records:
    if not record:
        continue
    print("  %s  %s  %s" % (record["Name"], record["Type"], record["Value"]))' <<<"${RECORDS}"
  echo

  ZONE="$(zone_for "${APP_DOMAIN}" || true)"
  if [[ -n "${ZONE}" ]]; then
    log "writing the validation records in Route 53 zone ${ZONE}"
    python3 - "${ZONE}" "${RECORDS}" <<'PY'
import json, subprocess, sys
zone, records = sys.argv[1], json.loads(sys.argv[2])
changes = []
for record in records:
    if not record:
        continue
    changes.append({
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": record["Name"],
            "Type": record["Type"],
            "TTL": 300,
            "ResourceRecords": [{"Value": record["Value"]}],
        },
    })
subprocess.run(
    ["aws", "route53", "change-resource-record-sets", "--hosted-zone-id", zone,
     "--change-batch", json.dumps({"Changes": changes})],
    check=True,
)
PY
    upsert_env HOSTED_ZONE_ID "${ZONE}"
    HOSTED_ZONE_ID="${ZONE}"
    log "waiting for the certificate to be issued"
    aws acm wait certificate-validated --region us-east-1 --certificate-arn "${ACM_CERTIFICATE_ARN}"
  else
    die "no Route 53 zone covers ${APP_DOMAIN}. Add the validation records above, wait until they resolve, then run make domain again."
  fi
else
  ZONE="${HOSTED_ZONE_ID:-}"
  if [[ -z "${ZONE}" ]]; then
    ZONE="$(zone_for "${APP_DOMAIN}" || true)"
    if [[ -n "${ZONE}" ]]; then
      upsert_env HOSTED_ZONE_ID "${ZONE}"
      HOSTED_ZONE_ID="${ZONE}"
    fi
  fi
fi

log "attaching the certificate to the load balancer"
SKIP_BUILD=1 \
  ACM_CERTIFICATE_ARN="${ACM_CERTIFICATE_ARN}" \
  API_DOMAIN="${API_DOMAIN}" \
  HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}" \
  "${ROOT}/scripts/deploy-backend.sh"

ALB="$(stack_output "${PROJECT_NAME}-backend" AlbDnsName)"
echo
if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
  echo "  Route 53 now has an alias from ${API_DOMAIN} to the load balancer."
  echo "  An alias is the routing record. It is not the validation CNAME."
else
  echo "  Routing record. This sends api traffic to the load balancer."
  echo "  ${API_DOMAIN}  CNAME  ${ALB}"
fi

FRONT="$(stack_status "${PROJECT_NAME}-frontend" || true)"
if [[ -n "${FRONT}" ]]; then
  log "attaching ${APP_DOMAIN} to CloudFront"
  APP_DOMAIN="${APP_DOMAIN}" ACM_CERTIFICATE_ARN="${ACM_CERTIFICATE_ARN}" \
    HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}" "${ROOT}/scripts/deploy-frontend.sh"
else
  echo "  Run make deploy-frontend next. It will attach ${APP_DOMAIN} if the certificate is in .env."
  if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
    echo "  After that, add a CNAME from ${APP_DOMAIN} to the CloudFront domain the script prints."
  fi
fi

echo
echo "  DNS is not instant. Check it before deciding something is broken:"
echo "    dig ${API_DOMAIN}"
echo "    dig ${APP_DOMAIN}"
echo
