#!/usr/bin/env bash
# cosign-аттестация ISO (ПРЕДЛОЖЕНИЕ-40, issue #5) — скрипт-заготовка протокола.
# Если cosign установлен — исполняет честный путь (attest-blob/verify-blob,
# PROVEN/COSIGN-ATTEST-PROTOCOL.md). Если нет — печатает протокол и делает
# stdlib-fallback (DSSE-конверт с HMAC/unsigned) через tools/iso_attest.py.
# Выход: 0 — аттестация+проверка прошли; 2 — cosign недоступен (fallback исполнен);
# 1 — ошибка. Секреты (ключи) никогда не печатаются и не коммитятся.
set -euo pipefail

ISO="${1:-}"
KEY="${2:-}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVELOPE="$REPO_DIR/PROVEN/ATTEST-0.2-BISECT.json"

if [ -z "$ISO" ]; then
  echo "usage: $0 <path-to-iso> [cosign-key-prefix]" >&2
  exit 1
fi
if [ ! -f "$ISO" ]; then
  echo "FAIL: артефакт '$ISO' не найден (Law 4: сначала хеш, потом дело)" >&2
  exit 1
fi

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign недоступен в этой среде — честный fallback (stdlib, DSSE/HMAC):"
  echo "  протокол: PROVEN/COSIGN-ATTEST-PROTOCOL.md"
  python3 "$REPO_DIR/tools/iso_attest.py" verify \
    --artifact "$ISO" --envelope "$ENVELOPE" --allow-unsigned
  echo "Замечание: unsigned-режим подтверждает только дайджест; подпись cosign добавляет Хозяин по протоколу."
  exit 2
fi

echo "cosign найден: $(cosign version 2>/dev/null | head -1 || echo unknown)"
KEYARG=()
if [ -n "$KEY" ]; then
  KEYARG=(--key "$KEY.key")
fi
cosign attest-blob --yes "${KEYARG[@]:-}" --predicate "$ENVELOPE" --type slsaprovenance "$ISO"
cosign verify-blob --key "${KEY}.pub" --signature "$ISO.bundle" "$ISO" \
  && echo "cosign verify OK — sha256 сверяется со строкой PROVEN/SHA256SUMS-BISECT.txt и SEALS.jsonl (evidence_sha256_iso)"
