#!/bin/bash
# gh_auth.sh — единый источник GitHub-токена (AUDIT-2026-1030 / FINDING-C1).
# Порядок: GH_TOKEN/GITHUB_TOKEN из окружения -> git credential fill -> падение с ошибкой.
# Plaintext-файлы (.gh_token / .phx_gh_token) НЕ читаются — их хранение в проекте запрещено.
gh_token() {
  if [ -n "${GH_TOKEN:-}" ]; then printf '%s' "$GH_TOKEN"; return 0; fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then printf '%s' "$GITHUB_TOKEN"; return 0; fi
  local out pass
  out=$(printf 'protocol=https\nhost=github.com\n\n' \
        | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null) || out=""
  pass=$(printf '%s' "$out" | sed -n 's/^password=//p')
  if [ -n "$pass" ]; then printf '%s' "$pass"; return 0; fi
  echo "gh_token: GitHub-токен не найден. Экспортируй GH_TOKEN (или GITHUB_TOKEN)," \
       "либо настрой credential helper для https://github.com" >&2
  return 1
}
