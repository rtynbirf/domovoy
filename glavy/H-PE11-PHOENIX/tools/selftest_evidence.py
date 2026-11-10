#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Selftest свидетельств ФЕНИКС-11 (issue #5) — только stdlib, fail-closed.

Секции:
  A. Хеш-цепь SEALS.jsonl: verifier на живом журнале — 0 разрывов;
     голова публикуется.
  B. seal_append: пломба canon v2 дописывается в КОПИЮ журнала, verifier
     снова 0 разрывов, сам-хеш выводим байт-в-байт; тампер ноты в копии
     ловится (sha256_self перестаёт сходиться).
  C. Аттестация (DSSE/HMAC): attest→verify OK на синтетике; подмена байта
     артефакта ловится; подмена payload ловится.
  D. Приёмка issue #5: sha256 целого ISO из конверта == строке
     PROVEN/SHA256SUMS-BISECT.txt == полю evidence ISO-хеша в SEALS.jsonl.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
ISO_NAME = "PHOENIX-ALPHA-0.2-BISECT.iso"


def fail(msg: str) -> int:
    print(f"SELFTEST FAIL: {msg}")
    return 1


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, *args], capture_output=True, text=True)


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> int:
    seals = ROOT / "SEALS.jsonl"
    proven = ROOT / "PROVEN" / "SHA256SUMS-BISECT.txt"
    for p in (seals, proven):
        if not p.exists():
            return fail(f"нет файла {p}")

    # --- A: живая цепь
    r = run([str(TOOLS / "verify_seals.py"), str(seals), "--json"])
    if r.returncode != 0:
        return fail(f"верификатор вернул {r.returncode} на живой цепи:\n{r.stdout}")
    report = json.loads(r.stdout)
    if report["breaks"]:
        return fail("на живой цепи есть разрывы")
    head = report["head"]
    print(f"A PASS: живая цепь цела: {report['records']} записей, 0 разрывов; голова {head[:16]}…")

    # --- B: seal_append в копию + тампер-детект
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        copy = tmp / "SEALS-copy.jsonl"
        copy.write_bytes(seals.read_bytes())
        evidence = ROOT / "PROVEN" / "W4-MERGE-EVIDENCE.md"
        if not evidence.exists():
            return fail("нет PROVEN/W4-MERGE-EVIDENCE.md")
        r = run([str(TOOLS / "seal_append.py"), "--file", str(copy), "--worklog", str(evidence),
                 "--subject", "TH-W4-E-SELFTEST", "--kind", "selftest-seal",
                 "--note", "selftest: пломба в копию журнала"])
        if r.returncode != 0:
            return fail(f"seal_append упал:\n{r.stdout}{r.stderr}")
        r = run([str(TOOLS / "verify_seals.py"), str(copy)])
        if r.returncode != 0:
            return fail(f"цепь после append разорвана:\n{r.stdout}")
        lines = copy.read_text(encoding="utf-8").splitlines()
        rec = json.loads(lines[-1])
        body = {k: v for k, v in rec.items() if k != "sha256_self"}
        canon = json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if sha256(canon) != rec["sha256_self"]:
            return fail("сам-хеш canon v2 не воспроизводится")
        # тампер: меняем ноту — сам-хеш обязан перестать сходиться
        rec["note"] += " TAMPER"
        tampered = dict(rec)
        body = {k: v for k, v in tampered.items() if k != "sha256_self"}
        if sha256(json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")) == rec["sha256_self"]:
            return fail("тампер не изменил ожидаемый сам-хеш")
        print("B PASS: append+verify на копии; сам-хеш canon v2 воспроизводим; тампер ноты изменит хеш")

        # --- C: attest/verify + тамперы
        art = tmp / "synthetic.iso"
        art.write_bytes(b"PHOENIX-ALPHA-0.2-BISECT synthetic payload \x00\x01" * 1024)
        keyf = tmp / "key"
        keyf.write_bytes(b"selftest-key-not-a-secret")
        envf = tmp / "att.json"
        r = run([str(TOOLS / "iso_attest.py"), "attest", "--artifact", str(art), "--name", ISO_NAME,
                 "--key", str(keyf), "--keyid", "selftest", "--note", "selftest", "--output", str(envf)])
        if r.returncode != 0:
            return fail(f"attest упал:\n{r.stdout}{r.stderr}")
        r = run([str(TOOLS / "iso_attest.py"), "verify", "--artifact", str(art), "--envelope", str(envf), "--key", str(keyf)])
        if r.returncode != 0:
            return fail(f"verify не прошёл на честной паре:\n{r.stdout}")
        # тампер артефакта
        art.write_bytes(art.read_bytes() + b"tamper")
        r = run([str(TOOLS / "iso_attest.py"), "verify", "--artifact", str(art), "--envelope", str(envf), "--key", str(keyf)])
        if r.returncode == 0:
            return fail("verify прошёл на подменённом артефакте")
        print("C PASS: attest→verify OK; подмена артефакта поймана")
        # тампер payload
        art.write_bytes(b"PHOENIX-ALPHA-0.2-BISECT synthetic payload \x00\x01" * 1024)
        envdoc = json.loads(envf.read_text())
        st = json.loads(envdoc["payload"])
        st["predicate"]["builder"]["id"] = "https://evil.example"
        envdoc["payload"] = json.dumps(st, sort_keys=True, separators=(",", ":"))
        envf.write_text(json.dumps(envdoc))
        r = run([str(TOOLS / "iso_attest.py"), "verify", "--artifact", str(art), "--envelope", str(envf), "--key", str(keyf)])
        if r.returncode == 0:
            return fail("verify прошёл на подменённом payload")
        print("C PASS: подмена payload поймана (подпись DSSE PAE не сходится)")

    # --- D: приёмка — sha256 ISO: конверт == PROVEN-строка == SEALS-поле
    text = proven.read_text(encoding="utf-8")
    marker = "# --- целый ISO после склейки ---"
    if marker not in text:
        return fail("в PROVEN/SHA256SUMS-BISECT.txt нет маркера целого ISO")
    tail = text.split(marker, 1)[1]
    mm = re.search(r"([0-9a-f]{64})", tail)
    if not mm:
        return fail("хеш целого ISO не найден в PROVEN/SHA256SUMS-BISECT.txt")
    proven_hash = mm.group(1)

    att_path = ROOT / "PROVEN" / "ATTEST-0.2-BISECT.json"
    if not att_path.exists():
        return fail("нет PROVEN/ATTEST-0.2-BISECT.json")
    envdoc = json.loads(att_path.read_text())
    subj = json.loads(envdoc["payload"])["subject"][0]["digest"]["sha256"]
    if subj != proven_hash:
        return fail(f"subject конверта {subj[:16]}… != строке PROVEN {proven_hash[:16]}…")

    seals_hash = None
    for line in seals.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        h = rec.get("evidence_sha256_iso")
        if h:
            seals_hash = h
    if not seals_hash:
        return fail("в SEALS.jsonl нет поля evidence_sha256_iso")
    if seals_hash != proven_hash or subj != seals_hash:
        return fail("расхождение конверт/PROVEN/SEALS")
    print(f"D PASS: sha256 ISO совпадает в трёх местах: PROVEN-строка == SEALS.jsonl == subject конверта ({proven_hash[:16]}…)")

    print("SELFTEST PASS: цепь, пломбы, аттестации, приёмка issue #5 — всё зелёное")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
