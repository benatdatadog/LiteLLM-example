#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${DD_API_KEY:?Set DD_API_KEY in .env}"
: "${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY in .env}"

export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-litellm-demo}"

echo "Starting LiteLLM proxy + Datadog Agent..."
docker compose up -d

echo
echo "Waiting for LiteLLM /metrics..."
for _ in $(seq 1 30); do
  if curl -sf http://localhost:4000/metrics >/dev/null 2>&1; then
    echo "LiteLLM metrics endpoint is up."
    break
  fi
  sleep 2
done

echo
echo "Generate traffic (optional):"
echo "  LITELLM_PROXY_URL=http://localhost:4000 ddtrace-run python app.py"
echo
echo "Validate agent check:"
echo "  docker exec litellm-demo-datadog-agent agent status | rg -A3 litellm"
