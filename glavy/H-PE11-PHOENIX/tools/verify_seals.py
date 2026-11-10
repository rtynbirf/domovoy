#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Верификатор хеш-цепи SEALS.jsonl (ПРЕДЛОЖЕНИЕ-40, issue #5) — только stdlib.

Цепь (П-09): каждая запись ссылается на sha256_self предыдущей через
prev_sha256; голова цепочки = sha256_self последней записи — тампер-очевидность
всего журнала одним числом.

Канон v2 (PROVEN/SEALS-CANON.md): записи с полем "canon":"v2" несут
sha256_self = sha256 канонического JSON записи БЕЗ поля sha256_self
(sort_keys, ensure_ascii=False, separators=(',',':'), utf-8) — сам-хеш
выводим из содержимого, тампер ловится байт-в-байт.

Наследие (canon v1): sha256_self ссылался на внешний ворклог — verifiable
только линк-цепь (prev_sha256[i] == sha256_self[i-1]); содержимое не
перепроверяется, и верификатор честно помечает такие записи legacy.

Выход: 0 — разрывов нет; 1 — разрыв/тампер/структурная рана. --json — машиночитаемый отчёт.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def canonical_payload(record: dict) -> bytes:
    body = {k: v for k, v in record.items() if k != "sha256_self"}
    return json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def expected_self(record: dict) -> str:
    return hashlib.sha256(canonical_payload(record)).hexdigest()


def verify(path: Path) -> dict:
    report: dict = {"file": str(path), "records": 0, "breaks": [], "legacy": 0, "v2": 0, "head": None}
    lines = path.read_text(encoding="utf-8").splitlines()
    prev_self: str | None = None
    prev_seq = 0
    for i, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            report["breaks"].append({"line": i, "kind": "json", "detail": str(e)})
            continue
        report["records"] += 1
        seq = rec.get("seq")
        selfh = rec.get("sha256_self") or ""
        prev = rec.get("prev_sha256")
        if not isinstance(seq, int) or seq <= prev_seq:
            report["breaks"].append({"line": i, "kind": "seq", "detail": f"seq={seq!r} после {prev_seq}"})
        prev_seq = seq or prev_seq
        if not HEX64.match(selfh):
            report["breaks"].append({"line": i, "kind": "self-hash", "detail": "sha256_self не hex64"})
        if report["records"] == 1:
            if prev not in ("", None):
                report["breaks"].append({"line": i, "kind": "genesis", "detail": f"первая запись с prev={prev!r}"})
        elif prev != prev_self:
            report["breaks"].append({
                "line": i, "kind": "link",
                "detail": f"prev_sha256={str(prev)[:12]}… != sha256_self[{i-1}]={str(prev_self)[:12]}…",
            })
        if rec.get("canon") == "v2":
            report["v2"] += 1
            if HEX64.match(selfh) and expected_self(rec) != selfh:
                report["breaks"].append({"line": i, "kind": "tamper", "detail": "sha256_self не выводим из содержимого (canon v2)"})
        else:
            report["legacy"] += 1
        if HEX64.match(selfh):
            prev_self = selfh
    report["head"] = prev_self
    return report


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Верификатор хеш-цепи SEALS.jsonl")
    ap.add_argument("file", nargs="?", default="SEALS.jsonl")
    ap.add_argument("--json", action="store_true", help="машиночитаемый отчёт")
    args = ap.parse_args(argv)

    path = Path(args.file)
    if not path.exists():
        print(f"FAIL: {path} не найден")
        return 2
    report = verify(path)
    if args.json:
        report["ok"] = not report["breaks"]
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return 0 if report["ok"] else 1
    else:
        print(f"записей: {report['records']} (legacy: {report['legacy']}, canon v2: {report['v2']})")
        for b in report["breaks"]:
            print(f"РАЗРЫВ строка {b['line']} [{b['kind']}]: {b['detail']}")
        print(f"голова цепочки: {report['head']}")
    if report["breaks"]:
        print(f"FAIL: разрывов {len(report['breaks'])}")
        return 1
    print(f"OK: цепь целая, 0 разрывов; голова {str(report['head'])[:16]}…")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
