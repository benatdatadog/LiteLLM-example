#!/usr/bin/env bash
# Configure the user's datadog-agent container for LiteLLM metrics scraping.
#
# Usage:
#   AGENT_CONTAINER=c8fcb176d565 ./scripts/use-existing-datadog-agent.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_ID="${AGENT_CONTAINER:-c8fcb176d565}"
AGENT_NAME="${AGENT_NAME:-datadog-agent}"

echo "Configuring Datadog Agent: $AGENT_ID ($AGENT_NAME)"

docker stop litellm-demo-datadog-agent 2>/dev/null || true

docker cp "$ROOT/datadog/datadog.yaml" "$AGENT_ID:/etc/datadog-agent/datadog.yaml"
docker exec "$AGENT_ID" mkdir -p /etc/datadog-agent/conf.d/litellm.d 2>/dev/null \
  || docker start "$AGENT_ID" && sleep 2 && docker exec "$AGENT_ID" mkdir -p /etc/datadog-agent/conf.d/litellm.d
docker cp "$ROOT/datadog/conf.d/litellm.d/conf.yaml" \
  "$AGENT_ID:/etc/datadog-agent/conf.d/litellm.d/conf.yaml"

docker start "$AGENT_ID" 2>/dev/null || true
docker network connect litellm-demo "$AGENT_NAME" 2>/dev/null || true
docker restart "$AGENT_ID" >/dev/null

echo "Waiting for agent..."
for _ in $(seq 1 30); do
  if docker exec "$AGENT_NAME" agent status >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo
docker exec "$AGENT_NAME" agent version | head -1
docker exec "$AGENT_NAME" agent status 2>&1 | rg -A10 "litellm \(" || {
  echo "LiteLLM check not listed yet — inspect with: docker exec $AGENT_NAME agent status"
}
