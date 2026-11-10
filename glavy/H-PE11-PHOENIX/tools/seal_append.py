#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Дописыватель пломб SEALS.jsonl по П-09 (ПРЕДЛОЖЕНИЕ-40) — только stdlib.

Append-only: сначала верифицирует живую цепь (fail-closed на любой разрыв),
затем дописывает новую запись canon v2 (PROVEN/SEALS-CANON.md):
  prev_sha256  = sha256_self предыдущей записи (голова цепи);
  seq          = prev.seq + 1;
  sha256_worklog = sha256 файла-ворклога (--worklog), bytes = его размер;
  sha256_self  = sha256 канонического JSON записи без поля sha256_self;
  created_at   = текущее время UTC (единственное недетерминированное поле —
                 оно семантическое: момент пломбы).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_seals import verify, expected_self  # noqa: E402


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Append-only пломба в SEALS.jsonl (П-09, canon v2)")
    ap.add_argument("--file", default="SEALS.jsonl")
    ap.add_argument("--note", required=True, help="суть пломбы (одно предложение)")
    ap.add_argument("--subject", required=True, help="метка субъекта (например TH-W4-E)")
    ap.add_argument("--kind", default="worklog-seal")
    ap.add_argument("--worklog", required=True, help="файл-доказательство: его sha256 и размер идут в запись")
    ap.add_argument("--extra", action="append", default=[], help="доп. поле KEY=VALUE (JSON-значение если парсится)")
    args = ap.parse_args(argv)

    path = Path(args.file)
    worklog = Path(args.worklog)
    if not path.exists() or not worklog.exists():
        print("FAIL: не найден журнал или ворклог")
        return 2

    report = verify(path)
    if report["breaks"]:
        print(f"FAIL: цепь разорвана ({len(report['breaks'])}) — пломба запрещена")
        return 1

    wb = worklog.read_bytes()
    rec: dict = {
        "bytes": len(wb),
        "canon": "v2",
        "created_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "+00:00"),
        "kind": args.kind,
        "note": args.note,
        "prev_sha256": report["head"],
        "seq": report["records"] + 1,
        "sha256_worklog": hashlib.sha256(wb).hexdigest(),
        "subject": args.subject,
    }
    for kv in args.extra:
        k, _, v = kv.partition("=")
        try:
            rec[k] = json.loads(v)
        except json.JSONDecodeError:
            rec[k] = v

    rec["sha256_self"] = expected_self(rec)
    line = json.dumps(rec, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    with path.open("a", encoding="utf-8", newline="\n") as f:
        f.write(line + "\n")

    re_report = verify(path)
    if re_report["breaks"]:
        print("FAIL: после дописывания цепь разорвана — откатите файл")
        return 1
    print(f"OK: пломба seq={rec['seq']} дописана; новая голова {re_report['head'][:16]}…")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
