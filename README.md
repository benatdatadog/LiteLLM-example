# LiteLLM + Datadog LLM Observability Demo

Minimal Python demo that calls [LiteLLM](https://docs.litellm.ai/) and sends traces to [Datadog LLM Observability](https://docs.datadoghq.com/llm_observability/) using native auto-instrumentation (`ddtrace>=3.9.0`).

## What this demonstrates

- **Automatic LiteLLM tracing** — `litellm.completion()` is instrumented with no LiteLLM code changes
- **End-to-end workflow spans** — a `@workflow` wraps each user turn
- **Usage attribution** — `team` and `user_handle` tags (and `cost_tags`) for cost/usage breakdowns in Datadog
- **Token & cost metadata** — captured automatically on LLM spans

## Prerequisites

1. [Enable LLM Observability](https://docs.datadoghq.com/llm_observability/) in your Datadog account
2. Python 3.10+
3. **AWS Bedrock** access — enable `anthropic.claude-3-5-haiku-20241022-v1:0` in your region and set `AWS_REGION_NAME` plus credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, or `~/.aws/credentials` via `AWS_PROFILE`)
4. A Datadog API key (`DD_API_KEY`)

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.lock

cp .env.example .env
# Edit .env with your keys

chmod +x run.sh
./run.sh
```

Or run manually:

```bash
export DD_API_KEY=...
export DD_SITE=datadoghq.com
export DD_LLMOBS_ENABLED=1
export DD_LLMOBS_ML_APP=litellm-demo
export DD_LLMOBS_AGENTLESS_ENABLED=1
export AWS_REGION_NAME=us-east-1
# AWS credentials via env vars or ~/.aws/credentials

ddtrace-run python app.py
```

## View traces

After the script finishes, open **Datadog → LLM Observability → Traces** and filter by ML app `litellm-demo`.

You should see:

- Root `workflow` spans (`customer_assistant`)
- Child `llm` spans from the LiteLLM integration
- Token counts, model/provider metadata, prompts, and responses

## LiteLLM dashboard (metrics + logs via Datadog Agent)

The **LLM Observability traces** above come from `ddtrace-run` on the Python app. To light up the **LiteLLM integration dashboard** (request volume, latency, token usage, spend, logs), you also need:

1. **LiteLLM Proxy** exposing `/metrics` (Prometheus) and sending logs via the `datadog` callback
2. **Datadog Agent** `litellm` check scraping that `/metrics` endpoint (Agent **>= 7.68.0**)

### Option A — docker-compose stack (recommended)

Starts a Datadog Agent + LiteLLM Proxy on a shared `litellm-demo` network:

```bash
chmod +x scripts/start-stack.sh
./scripts/start-stack.sh
```

Then route app traffic through the proxy so metrics are generated:

```bash
# Add to .env:
# LITELLM_PROXY_URL=http://localhost:4000
# LITELLM_MASTER_KEY=sk-litellm-demo

./run.sh
```

Validate the agent check:

```bash
docker exec litellm-demo-datadog-agent agent status | rg -A5 litellm
curl http://localhost:4000/metrics | head
```

In Datadog:

- **Integrations → LiteLLM** — install/enable the integration tile
- **Dashboards** — search for the LiteLLM out-of-the-box dashboard
- **Logs** — filter `source:litellm` or `service:litellm-proxy`

### Option B — patch your existing `datadog-agent` container

If you already run a Docker Datadog Agent (e.g. container name `datadog-agent`):

```bash
# Start only the LiteLLM proxy (connect to your agent network separately)
docker compose up -d litellm-proxy

# Patch the existing agent with the litellm check config
chmod +x scripts/patch-existing-datadog-agent.sh
AGENT_CONTAINER=datadog-agent \
  LITELLM_METRICS_URL=http://host.docker.internal:4000/metrics \
  ./scripts/patch-existing-datadog-agent.sh
```

Your existing agent must have been started with `DD_LOGS_ENABLED=true` so LiteLLM can ship logs via `LITELLM_DD_AGENT_HOST`.

If the agent and proxy are on the same Docker network, use:

```bash
LITELLM_METRICS_URL=http://litellm-proxy:4000/metrics ./scripts/patch-existing-datadog-agent.sh
docker network connect litellm-demo datadog-agent
```

### What each layer provides

| Layer | Source | Datadog product |
| --- | --- | --- |
| Python app + `ddtrace-run` | SDK auto-instrumentation | LLM Observability traces |
| LiteLLM Proxy `prometheus` callback | `/metrics` scraped by Agent | LiteLLM integration metrics + dashboard |
| LiteLLM Proxy `datadog` callback | Logs to Datadog API (`DD_API_KEY` + `DD_SITE`) | Logs (`source:litellm`) |

## Configuration

| Variable | Description |
| --- | --- |
| `DD_API_KEY` | Datadog API key |
| `DD_SITE` | Datadog site (e.g. `datadoghq.com`, `datadoghq.eu`) |
| `DD_LLMOBS_ML_APP` | ML application name in Datadog |
| `DEMO_MODEL` | Proxy alias `bedrock-claude-haiku`, or full id `bedrock/anthropic.claude-3-5-haiku-20241022-v1:0` for direct SDK calls |
| `AWS_REGION_NAME` | Bedrock region (default: `us-east-1`) |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | AWS credentials (optional if using `~/.aws/credentials`) |
| `DEMO_TEAM` | Team tag for usage/cost attribution |
| `DEMO_USER_HANDLE` | User tag for session attribution |
| `LITELLM_PROXY_URL` | Route calls through LiteLLM Proxy (e.g. `http://localhost:4000`) |
| `LITELLM_MASTER_KEY` | Proxy master key (default: `sk-litellm-demo`) |

## References

- [Monitor LiteLLM with Datadog (blog)](https://www.datadoghq.com/blog/monitor-litellm-with-datadog/)
- [LiteLLM auto-instrumentation](https://docs.datadoghq.com/llm_observability/instrumentation/auto_instrumentation/?tab=python#litellm)
- [LLM Observability quickstart](https://docs.datadoghq.com/llm_observability/quickstart/?tab=python)
