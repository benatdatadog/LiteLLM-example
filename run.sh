#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${DD_LLMOBS_ENABLED:=1}"
: "${DD_LLMOBS_ML_APP:=litellm-demo}"
: "${DD_LLMOBS_AGENTLESS_ENABLED:=1}"
: "${DD_ENV:=dev}"
: "${DD_SERVICE:=litellm-demo}"

if [[ -z "${DD_API_KEY:-}" ]]; then
  echo "DD_API_KEY is required. Copy .env.example to .env and set your Datadog API key." >&2
  exit 1
fi

exec ddtrace-run python app.py
