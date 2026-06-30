#!/usr/bin/env bash
# Add the LiteLLM Agent check to an existing Datadog Agent container.
#
# Usage:
#   AGENT_CONTAINER=datadog-agent ./scripts/patch-existing-datadog-agent.sh
#
# Notes:
# - The agent must be >= 7.68.0 for the litellm integration.
# - DD_LOGS_ENABLED=true is required for LiteLLM log callbacks.
# - If your agent was started without logs, recreate it with DD_LOGS_ENABLED=true.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_CONTAINER="${AGENT_CONTAINER:-datadog-agent}"
LITELLM_METRICS_URL="${LITELLM_METRICS_URL:-http://host.docker.internal:4000/metrics}"

if ! docker inspect "$AGENT_CONTAINER" >/dev/null 2>&1; then
  echo "Container '$AGENT_CONTAINER' not found." >&2
  exit 1
fi

CONF_DIR="/etc/datadog-agent/conf.d/litellm.d"
TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_CONF"' EXIT

cat >"$TMP_CONF" <<EOF
init_config:

instances:
  - openmetrics_endpoint: ${LITELLM_METRICS_URL}
    min_collection_interval: 15
    tags:
      - service:litellm-proxy
      - env:dev
EOF

echo "Installing LiteLLM check config into $AGENT_CONTAINER:$CONF_DIR/conf.yaml"
docker exec "$AGENT_CONTAINER" mkdir -p "$CONF_DIR"
docker cp "$TMP_CONF" "$AGENT_CONTAINER:$CONF_DIR/conf.yaml"

if docker network inspect litellm-demo >/dev/null 2>&1; then
  echo "Connecting $AGENT_CONTAINER to litellm-demo network..."
  docker network connect litellm-demo "$AGENT_CONTAINER" 2>/dev/null || true
fi

echo "Restarting Datadog Agent..."
docker restart "$AGENT_CONTAINER" >/dev/null

echo
echo "Done. Validate with:"
echo "  docker exec $AGENT_CONTAINER agent status | rg -A3 litellm"
echo
echo "If LiteLLM runs in docker-compose, set:"
echo "  LITELLM_METRICS_URL=http://litellm-proxy:4000/metrics"
echo "and connect the agent to the litellm-demo network."
