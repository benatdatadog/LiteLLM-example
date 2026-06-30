"""
LiteLLM + Datadog LLM Observability demo.

Run with auto-instrumentation (recommended):
  ddtrace-run python app.py

Or load env vars first:
  set -a && source .env && set +a && ddtrace-run python app.py
"""

from __future__ import annotations

import os
import sys
import uuid

from dotenv import load_dotenv
from litellm import completion

load_dotenv()

MODEL = os.getenv("DEMO_MODEL", "gpt-4o-mini")
TEAM = os.getenv("DEMO_TEAM", "platform-engineering")
USER_HANDLE = os.getenv("DEMO_USER_HANDLE", "demo@example.com")
MOCK_MODE = os.getenv("DEMO_MOCK", "").lower() in {"1", "true", "yes"}
PROXY_URL = os.getenv("LITELLM_PROXY_URL")
PROXY_API_KEY = os.getenv("LITELLM_MASTER_KEY", "sk-litellm-demo")

MOCK_RESPONSES = {
    "I'd like to buy a chair for my living room.": (
        "We have several accent chairs and recliners in stock — "
        "would you like fabric or leather?"
    ),
    "What's your return policy on sofas?": (
        "Sofas can be returned within 30 days in original condition."
    ),
    "Do you deliver to Boston?": (
        "Yes, we deliver to Boston — standard delivery is 5–7 business days."
    ),
}


def _require_api_key() -> None:
    if MOCK_MODE:
        return
    if os.getenv("OPENAI_API_KEY") or os.getenv("ANTHROPIC_API_KEY"):
        return
    print(
        "Set OPENAI_API_KEY or ANTHROPIC_API_KEY in .env (see .env.example),\n"
        "or set DEMO_MOCK=true to run without a provider (Datadog tracing still works).",
        file=sys.stderr,
    )
    sys.exit(1)


def _require_datadog() -> None:
    if os.getenv("DD_LLMOBS_ENABLED", "").lower() in {"1", "true"}:
        return
    print(
        "Run with ddtrace-run and DD_LLMOBS_ENABLED=1 so LiteLLM calls are traced.\n"
        "Example:\n"
        "  DD_API_KEY=... DD_SITE=datadoghq.com DD_LLMOBS_ENABLED=1 "
        "DD_LLMOBS_ML_APP=litellm-demo ddtrace-run python app.py",
        file=sys.stderr,
    )
    sys.exit(1)


def run_customer_assistant(session_id: str, user_message: str) -> str:
    """Single-turn assistant wrapped in a workflow span for end-to-end tracing."""
    from ddtrace.llmobs import LLMObs
    from ddtrace.llmobs.decorators import workflow

    @workflow(name="customer_assistant", session_id=session_id)
    def _assistant() -> str:
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a helpful customer assistant for a furniture store. "
                    "Keep answers to one or two sentences."
                ),
            },
            {"role": "user", "content": user_message},
        ]

        completion_kwargs: dict = {"model": MODEL, "messages": messages}
        if PROXY_URL:
            completion_kwargs["api_base"] = PROXY_URL
            completion_kwargs["api_key"] = PROXY_API_KEY
        if MOCK_MODE:
            completion_kwargs["mock_response"] = MOCK_RESPONSES.get(
                user_message,
                "Happy to help — ask me about furniture, delivery, or returns.",
            )

        with LLMObs.annotation_context(
            tags={
                "team": TEAM,
                "user_handle": USER_HANDLE,
                "session_id": session_id,
            },
            cost_tags=["team"],
        ):
            try:
                response = completion(**completion_kwargs)
            except Exception as exc:
                err = str(exc)
                if "insufficient_quota" in err or "exceeded your current quota" in err:
                    print(
                        "\nOpenAI returned insufficient_quota — the key is valid but the "
                        "account has no billing/quota.\n"
                        "Fix: https://platform.openai.com/settings/organization/billing\n"
                        "Or run with DEMO_MOCK=true to demo Datadog tracing without OpenAI.\n",
                        file=sys.stderr,
                    )
                raise

        content = response.choices[0].message.content or ""
        LLMObs.annotate(
            input_data=user_message,
            output_data=content,
            tags={"team": TEAM, "user_handle": USER_HANDLE},
        )
        return content

    return _assistant()


def main() -> None:
    _require_api_key()
    _require_datadog()

    session_id = f"demo-{uuid.uuid4().hex[:8]}"
    prompts = [
        "I'd like to buy a chair for my living room.",
        "What's your return policy on sofas?",
        "Do you deliver to Boston?",
    ]

    mode = "mock (no API calls)" if MOCK_MODE else ("proxy" if PROXY_URL else "live")
    print(f"LiteLLM demo | model={MODEL} | team={TEAM} | mode={mode} | session={session_id}\n")

    for i, prompt in enumerate(prompts, start=1):
        print(f"[{i}/{len(prompts)}] User: {prompt}")
        answer = run_customer_assistant(session_id, prompt)
        print(f"Assistant: {answer}\n")

    from ddtrace.llmobs import LLMObs

    LLMObs.flush()
    print("Done. Check Datadog → LLM Observability → Traces for litellm spans.")


if __name__ == "__main__":
    main()
