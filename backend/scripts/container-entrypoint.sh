#!/bin/sh
set -eu

if [ -n "${AWS_LAMBDA_RUNTIME_API:-}" ]; then
  exec python -m awslambdaric "$@"
fi

exec ./scripts/entrypoint.sh
