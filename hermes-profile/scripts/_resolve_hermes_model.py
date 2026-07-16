#!/usr/bin/env python3
"""Resolve Hermes profile model/base_url/key_env from config.yaml for setup-graphify.sh.

Prints shell assignments:
  HERMES_MODEL=... HERMES_BASE_URL=... HERMES_KEY_ENV=...
  HERMES_PROVIDER=... HERMES_PROVIDER_NAME=...
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def block(text: str, name: str) -> str:
    m = re.search(rf"(?m)^{re.escape(name)}:\s*\n((?:^[ \t].*\n?)*)", text)
    return m.group(1) if m else ""


def field(blk: str, key: str) -> str:
    m = re.search(rf"(?m)^\s*{re.escape(key)}:\s*(.+?)\s*$", blk)
    if not m:
        return ""
    v = m.group(1).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = v[1:-1]
    return v


def sh(name: str, val: str) -> None:
    for old, new in (
        ("\\", "\\\\"),
        ('"', '\\"'),
        ("$", "\\$"),
        ("`", "\\`"),
    ):
        val = val.replace(old, new)
    print(f'{name}="{val}"')


def main() -> int:
    cfg = Path(sys.argv[1] if len(sys.argv) > 1 else "config.yaml")
    if not cfg.is_file():
        for name in (
            "HERMES_MODEL",
            "HERMES_BASE_URL",
            "HERMES_KEY_ENV",
            "HERMES_PROVIDER",
            "HERMES_PROVIDER_NAME",
        ):
            sh(name, "")
        return 0

    text = cfg.read_text(encoding="utf-8")
    model_blk = block(text, "model")
    default = field(model_blk, "default")
    provider = field(model_blk, "provider")
    base_url = field(model_blk, "base_url")
    key_env = field(model_blk, "key_env")
    provider_name = ""

    items: list[dict[str, str]] = []
    cur: dict[str, str] = {}
    for line in block(text, "custom_providers").splitlines():
        if re.match(r"^\s*-\s+name:\s*", line):
            if cur:
                items.append(cur)
            cur = {"name": re.sub(r"^\s*-\s+name:\s*", "", line).strip().strip("\"'")}
            continue
        if not cur:
            continue
        m = re.match(r"^\s+(base_url|key_env|model):\s*(.+?)\s*$", line)
        if m:
            cur[m.group(1)] = m.group(2).strip().strip("\"'")
    if cur:
        items.append(cur)

    match = None
    if provider and provider not in ("custom", "openai", "ollama"):
        for it in items:
            if it.get("name") == provider:
                match = it
                break
    if match is None and base_url:
        for it in items:
            if it.get("base_url", "").rstrip("/") == base_url.rstrip("/"):
                match = it
                break

    if match:
        provider_name = match.get("name", "")
        if match.get("key_env"):
            key_env = match["key_env"]
        if provider and provider == match.get("name"):
            base_url = match.get("base_url") or base_url
            default = default or match.get("model", "")
        else:
            base_url = base_url or match.get("base_url", "")
            default = default or match.get("model", "")

    sh("HERMES_MODEL", default)
    sh("HERMES_BASE_URL", base_url)
    sh("HERMES_KEY_ENV", key_env)
    sh("HERMES_PROVIDER", provider)
    sh("HERMES_PROVIDER_NAME", provider_name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
