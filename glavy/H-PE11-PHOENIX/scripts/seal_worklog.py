#!/usr/bin/env python3
"""seal_worklog.py — пломба ворклога: append-only хеш-цепь по канону дома.

Каждая операция, зафиксированная в worklog.md, запечатывает свой факт: запись
SEALS.jsonl несёт SHA-256 байтов worklog.md на момент пломбы и prev_sha256 —
SHA-256 канонической JSON-формы предыдущей пломбы (json.dumps(sort_keys=True,
ensure_ascii=False, separators=(",",":")) — канон SPEC-0003 дома, совместим
с canonical_sha256 emit.py ядра cell-swarm байт-в-байт).

Триггер — событие, не время: пломбу ставит сам шаг операции после записи в
ворклог (не по расписанию и не по накоплению). Цепочка fail-closed: чужая
вставка или правка задним числом рвёт цепь — verify это показывает.

Запуск:
    python3 scripts/seal_worklog.py --subject TH-RTP-04 --note "..."   # запечатать
    python3 scripts/seal_worklog.py --verify                           # сверить цепь
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKLOG = ROOT / "worklog.md"
SEALS = ROOT / "SEALS.jsonl"


def canonical_sha256(envelope: dict) -> str:
    """Канон дома (SPEC-0003) по телу пломбы БЕЗ self-поля: поле sha256_self —
    печать, она не входит в то, что подписывает сама себя."""
    body = {k: v for k, v in envelope.items() if k != "sha256_self"}
    canonical = json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def load_seals() -> list[dict]:
    if not SEALS.exists():
        return []
    out = []
    for line in SEALS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            out.append(json.loads(line))
    return out


def verify() -> int:
    seals = load_seals()
    if not seals:
        print("пломб нет — цепь пуста (запечатай первую операцию)")
        return 0
    prev = ""
    for i, env in enumerate(seals, 1):
        if env.get("prev_sha256") != prev:
            print(f"ЦЕПЬ РВАНА на пломбе {i}: prev_sha256 не сходится")
            return 1
        if canonical_sha256(env) != env.get("sha256_self"):
            print(f"ПЛОМБА {i} подменена: каноническая форма не совпадает с sha256_self")
            return 1
        prev = env["sha256_self"]
    wl = hashlib.sha256(WORKLOG.read_bytes()).hexdigest() if WORKLOG.exists() else ""
    last = seals[-1]
    print(f"цепь цела: {len(seals)} пломб; последняя {last['sha256_self'][:12]}")
    if wl == last["sha256_worklog"]:
        print(f"worklog.md бит-в-бит запечатан ({last['subject']})")
    else:
        print(f"worklog.md изменился после пломбы ({last['subject']}) — запечатай новый факт")
    return 0


def seal(subject: str, note: str) -> int:
    if verify() != 0 and SEALS.exists():
        print("отказ: цепь рвана — сначала разберись с прошлым фактом (fail-closed)")
        return 1
    seals = load_seals()
    body = WORKLOG.read_bytes()
    prev = seals[-1]["sha256_self"] if seals else ""
    envelope = {
        "seq": len(seals) + 1,
        "kind": "worklog-seal",
        "subject": subject,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "bytes": len(body),
        "sha256_worklog": hashlib.sha256(body).hexdigest(),
        "note": note,
        "prev_sha256": prev,
    }
    envelope["sha256_self"] = canonical_sha256(envelope)
    with SEALS.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(envelope, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
    print(f"пломба #{envelope['seq']} поставлена: {envelope['sha256_self'][:12]} ← worklog {envelope['sha256_worklog'][:12]}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--subject", help="что запечатываем (ид операции, например TH-RTP-04)")
    ap.add_argument("--note", default="", help="короткая метка факта")
    ap.add_argument("--verify", action="store_true", help="сверить цепь, ничего не писать")
    args = ap.parse_args()
    if args.verify:
        return verify()
    if not args.subject:
        print("нужен --subject (или --verify)")
        return 1
    return seal(args.subject, args.note)


if __name__ == "__main__":
    sys.exit(main())
