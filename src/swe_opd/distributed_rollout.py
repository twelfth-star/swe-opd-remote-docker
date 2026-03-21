from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def normalize_api_base(api_base: str) -> str:
    api_base = api_base.rstrip("/")
    if api_base.endswith("/v1"):
        return api_base
    return f"{api_base}/v1"


def str_to_bool(value: str) -> bool:
    value = value.strip().lower()
    if value in {"1", "true", "yes", "y", "on"}:
        return True
    if value in {"0", "false", "no", "n", "off"}:
        return False
    raise ValueError(f"Unsupported boolean value: {value}")


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "PyYAML is required for render-mini-config. "
            "Install requirements-bootstrap.txt or run with the mini-swe-agent-plus Python environment."
        ) from exc

    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise TypeError(f"Expected YAML object at top level, got {type(data).__name__}")
    return data


def write_yaml(path: Path, data: dict[str, Any]) -> None:
    try:
        import yaml
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "PyYAML is required for render-mini-config. "
            "Install requirements-bootstrap.txt or run with the mini-swe-agent-plus Python environment."
        ) from exc

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)


def http_get_json(url: str) -> tuple[int, Any]:
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=10) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        return resp.status, json.loads(body) if body else None


def http_get_text(url: str) -> tuple[int, str]:
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=10) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        return resp.status, body


def http_post_json(url: str, payload: dict[str, Any], headers: dict[str, str] | None = None) -> tuple[int, Any]:
    encoded = json.dumps(payload).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(url, data=encoded, headers=request_headers, method="POST")
    with urllib.request.urlopen(request, timeout=60) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        return resp.status, json.loads(body) if body else None


def probe_sglang(args: argparse.Namespace) -> int:
    api_base = normalize_api_base(args.api_base)
    root_base = api_base[: -len("/v1")] if api_base.endswith("/v1") else api_base

    try:
        status, body = http_get_text(f"{root_base}/health_generate")
    except urllib.error.URLError as exc:
        print(f"[FAIL] health_generate: {exc}", file=sys.stderr)
        return 1
    print(f"[OK] health_generate: HTTP {status}")
    if body:
        print(body)

    try:
        status, payload = http_get_json(f"{api_base}/models")
    except urllib.error.URLError as exc:
        print(f"[FAIL] v1/models: {exc}", file=sys.stderr)
        return 1
    except json.JSONDecodeError:
        print("[FAIL] v1/models: response is not valid JSON", file=sys.stderr)
        return 1
    print(f"[OK] v1/models: HTTP {status}")
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


def openai_smoke(args: argparse.Namespace) -> int:
    api_base = normalize_api_base(args.api_base)
    status, response = http_post_json(
        f"{api_base}/chat/completions",
        payload={
            "model": args.model_name,
            "messages": [{"role": "user", "content": args.prompt}],
            "temperature": args.temperature,
            "max_tokens": args.max_tokens,
        },
        headers={"Authorization": f"Bearer {args.api_key}"},
    )
    if status != 200:
        raise RuntimeError(f"openai-smoke failed with HTTP {status}: {json.dumps(response, ensure_ascii=False)}")
    content = response["choices"][0]["message"]["content"] or ""
    print(content)
    return 0


def litellm_smoke(args: argparse.Namespace) -> int:
    try:
        import litellm
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "litellm is required for litellm-smoke. "
            "Install requirements-bootstrap.txt or use the mini-swe-agent-plus Python environment."
        ) from exc

    completion_kwargs: dict[str, Any] = {
        "model": args.model_name,
        "messages": [{"role": "user", "content": args.prompt}],
        "api_base": normalize_api_base(args.api_base),
        "api_key": args.api_key,
        "temperature": args.temperature,
        "max_tokens": args.max_tokens,
        "custom_llm_provider": args.custom_llm_provider,
        "drop_params": args.drop_params,
    }

    if args.extra_model_kwargs_json:
        completion_kwargs.update(json.loads(args.extra_model_kwargs_json))

    response = litellm.completion(**completion_kwargs)
    content = response.choices[0].message.content or ""
    print(content)
    return 0


def render_mini_config(args: argparse.Namespace) -> int:
    base_config = load_yaml(Path(args.base_config))

    model_cfg = base_config.setdefault("model", {})
    model_cfg["model_name"] = args.model_name

    model_kwargs = model_cfg.setdefault("model_kwargs", {})
    model_kwargs["api_base"] = normalize_api_base(args.api_base)
    model_kwargs["custom_llm_provider"] = args.custom_llm_provider
    model_kwargs["api_key"] = args.api_key
    model_kwargs["temperature"] = args.temperature
    model_kwargs["drop_params"] = args.drop_params

    if args.extra_model_kwargs_json:
        model_kwargs.update(json.loads(args.extra_model_kwargs_json))

    if args.environment_class:
        base_config.setdefault("environment", {})["environment_class"] = args.environment_class

    output_path = Path(args.output_path)
    write_yaml(output_path, base_config)
    print(output_path)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bootstrap helpers for distributed serving + rollout.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe = subparsers.add_parser("probe-sglang", help="Probe SGLang HTTP endpoints.")
    probe.add_argument("--api-base", required=True, help="SGLang base URL, with or without /v1.")
    probe.set_defaults(func=probe_sglang)

    openai_cmd = subparsers.add_parser("openai-smoke", help="Send a minimal OpenAI client request.")
    openai_cmd.add_argument("--api-base", required=True)
    openai_cmd.add_argument("--api-key", default="EMPTY")
    openai_cmd.add_argument("--model-name", required=True)
    openai_cmd.add_argument("--prompt", default="Reply with exactly: bootstrap-ok")
    openai_cmd.add_argument("--temperature", type=float, default=0.0)
    openai_cmd.add_argument("--max-tokens", type=int, default=32)
    openai_cmd.set_defaults(func=openai_smoke)

    litellm_cmd = subparsers.add_parser("litellm-smoke", help="Send a minimal LiteLLM request.")
    litellm_cmd.add_argument("--api-base", required=True)
    litellm_cmd.add_argument("--api-key", default="EMPTY")
    litellm_cmd.add_argument("--model-name", required=True)
    litellm_cmd.add_argument("--custom-llm-provider", default="openai")
    litellm_cmd.add_argument("--prompt", default="Reply with exactly: bootstrap-ok")
    litellm_cmd.add_argument("--temperature", type=float, default=0.0)
    litellm_cmd.add_argument("--max-tokens", type=int, default=32)
    litellm_cmd.add_argument("--drop-params", type=str_to_bool, default=True)
    litellm_cmd.add_argument("--extra-model-kwargs-json", default="")
    litellm_cmd.set_defaults(func=litellm_smoke)

    render = subparsers.add_parser("render-mini-config", help="Render mini-swe-agent-plus config for remote SGLang.")
    render.add_argument("--base-config", required=True)
    render.add_argument("--output-path", required=True)
    render.add_argument("--model-name", required=True)
    render.add_argument("--api-base", required=True)
    render.add_argument("--api-key", default="EMPTY")
    render.add_argument("--custom-llm-provider", default="openai")
    render.add_argument("--temperature", type=float, default=0.0)
    render.add_argument("--drop-params", type=str_to_bool, default=True)
    render.add_argument("--environment-class", default="")
    render.add_argument("--extra-model-kwargs-json", default="")
    render.set_defaults(func=render_mini_config)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
