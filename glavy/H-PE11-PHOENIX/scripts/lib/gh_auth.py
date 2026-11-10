"""gh_auth — единый источник GitHub-токена (AUDIT-2026-1030 / FINDING-C1).

Порядок: GH_TOKEN/GITHUB_TOKEN из окружения -> git credential fill -> SystemExit
с понятной ошибкой. Plaintext-файлы (.gh_token / .phx_gh_token) НЕ читаются —
их хранение в проекте запрещено (исторический инцидент 2026-10-29).
"""
import os
import subprocess


def gh_token() -> str:
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if tok:
        return tok.strip()
    try:
        out = subprocess.run(
            ["git", "credential", "fill"],
            input="protocol=https\nhost=github.com\n\n",
            capture_output=True, text=True, timeout=15,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        ).stdout
        for line in out.splitlines():
            if line.startswith("password="):
                return line[9:].strip()
    except Exception:
        pass
    raise SystemExit(
        "gh_auth: GitHub-токен не найден. Экспортируй GH_TOKEN (или GITHUB_TOKEN) "
        "либо настрой credential helper для https://github.com")
