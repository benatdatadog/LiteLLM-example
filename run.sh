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

if [[ -n "${LITELLM_PROXY_URL:-}" ]]; then
  proxy_health="${LITELLM_PROXY_URL%/}/health/liveliness"
  echo "Waiting for LiteLLM proxy at ${LITELLM_PROXY_URL}..."
  for _ in $(seq 1 30); do
    if curl -sf "${proxy_health}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if ! curl -sf "${proxy_health}" >/dev/null 2>&1; then
    echo "LiteLLM proxy is not reachable at ${LITELLM_PROXY_URL}." >&2
    echo "Start it with: docker compose up -d litellm-proxy" >&2
    exit 1
  fi
fi

exec ddtrace-run python app.py
