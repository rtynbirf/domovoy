#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SLSA-аттестация артефактов ФЕНИКС-11 (ПРЕДЛОЖЕНИЕ-40, issue #5) — только stdlib.

Конверт — DSSE-структура (как у cosign attestations): payload (in-toto Statement
с predicateType https://slsa.dev/provenance/v0.2), payloadType,
signatures[]. Подпись — HMAC-SHA256 по DSSE PAE:

    PAE = "DSSEv1 " || len(payloadType) || " " || payloadType || " " || len(payload) || " " || payload

HMAC вместо ECDSA — честная заготовка без внешних зависимостей: структура
конверта 1-в-1 DSSE, замена подписанта на cosign/Ed25519 не меняет payload.
Ключ: env ATTEST_KEY или файл --key (никогда не логируется). Без ключа —
режим attest-unsigned (sig: null): дайджест фиксируется, подпись добавляет
Хозяин по протоколу PROVEN/COSIGN-ATTEST-PROTOCOL.md.

Команды: attest / verify. Тампер артефакта или payload ловится verify (exit 1).
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import sys
from pathlib import Path

PAYLOAD_TYPE = "application/vnd.in-toto+json"
BUILDER_ID = "https://github.com/rtynbirf/H-PE11-PHOENIX/.github/workflows/evidence-chain.yml@main"
BUILD_TYPE = "https://github.com/rtynbirf/H-PE11-PHOENIX/proven-works/iso-bisect"


def pae(payload_type: str, payload: bytes) -> bytes:
    return (
        b"DSSEv1 " + str(len(payload_type)).encode() + b" " + payload_type.encode()
        + b" " + str(len(payload)).encode() + b" " + payload
    )


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_key(args) -> bytes | None:
    if args.key:
        return Path(args.key).read_bytes().strip()
    env = os.environ.get("ATTEST_KEY")
    return env.encode() if env else None


def cmd_attest(args) -> int:
    artifact = Path(args.artifact)
    if not artifact.exists():
        print(f"FAIL: артефакт {artifact} не найден")
        return 2
    key = load_key(args)
    if not key and not args.allow_unsigned:
        print("FAIL: нет ключа (env ATTEST_KEY / --key); для unsigned-конверта — --allow-unsigned")
        return 2

    digest = sha256_file(artifact)
    statement = {
        "_type": "https://in-toto.io/Statement/v0.1",
        "subject": [{"name": args.name, "digest": {"sha256": digest}}],
        "predicateType": "https://slsa.dev/provenance/v0.2",
        "predicate": {
            "builder": {"id": BUILDER_ID},
            "buildType": BUILD_TYPE,
            "invocation": {
                "configSource": {"uri": "https://github.com/rtynbirf/H-PE11-PHOENIX", "digest": {}, "entryPoint": "PROVEN/SHA256SUMS-BISECT.txt"},
                "parameters": {"note": args.note},
                "environment": {"law": "Law 4: сначала хеш, потом дело"},
            },
            "metadata": {"completeness": {"parameters": True, "environment": False, "materials": False}, "reproducible": False},
            "materials": [],
        },
    }
    payload = json.dumps(statement, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    env: dict = {"payloadType": PAYLOAD_TYPE, "payload": payload.decode("utf-8"), "signatures": []}
    if key:
        sig = hmac.new(key, pae(PAYLOAD_TYPE, payload), hashlib.sha256).hexdigest()
        env["signatures"] = [{"keyid": args.keyid, "sig": f"hmac-sha256:{sig}"}]
    else:
        env["signatures"] = [{"keyid": "unsigned", "sig": None}]

    out = json.dumps(env, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    Path(args.output).write_text(out, encoding="utf-8")
    mode = "HMAC-SHA256 (DSSE PAE)" if key else "unsigned (дайджест зафиксирован, подпись — по протоколу cosign)"
    print(f"OK: конверт записан: {args.output} (subject sha256={digest[:16]}…, подпись: {mode})")
    return 0


def cmd_verify(args) -> int:
    artifact = Path(args.artifact)
    env = json.loads(Path(args.envelope).read_text(encoding="utf-8"))
    digest = sha256_file(artifact)

    st = json.loads(env["payload"])
    subjects = st.get("subject", [])
    if not any(s.get("digest", {}).get("sha256") == digest for s in subjects):
        want = subjects[0]["digest"]["sha256"] if subjects else "?"
        print(f"FAIL: sha256 артефакта {digest[:16]}… != subject конверта {want[:16]}… — артефакт подменён")
        return 1
    print(f"PASS: sha256 артефакта == subject конверта ({digest[:16]}…)")

    sigs = env.get("signatures") or []
    key = load_key(args)
    sig = sigs[0] if sigs else {}
    raw = sig.get("sig")
    if raw and raw.startswith("hmac-sha256:"):
        if not key:
            print("FAIL: конверт подписан HMAC, ключ не задан (env ATTEST_KEY / --key)")
            return 1
        expect = hmac.new(key, pae(env["payloadType"], env["payload"].encode("utf-8")), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(raw.split(":", 1)[1], expect):
            print("FAIL: подпись HMAC не сходится — payload подменён")
            return 1
        print("PASS: подпись DSSE PAE (HMAC-SHA256) верна")
    else:
        if not args.allow_unsigned:
            print("FAIL: конверт без подписи; для проверки unsigned — --allow-unsigned")
            return 1
        print("WARN: конверт unsigned — целостность подтверждена только дайджестом (подпись добавляет cosign по протоколу)")
    print("VERIFY OK")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="SLSA-аттестация (DSSE-конверт, HMAC-SHA256, stdlib)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("attest")
    a.add_argument("--artifact", required=True)
    a.add_argument("--name", default=None, help="имя subject (по умолчанию имя файла)")
    a.add_argument("--note", default="")
    a.add_argument("--key", default=None, help="файл ключа HMAC (иначе env ATTEST_KEY)")
    a.add_argument("--keyid", default="hmac-env:ATTEST_KEY")
    a.add_argument("--output", default="attestation.json")
    a.add_argument("--allow-unsigned", action="store_true")
    a.set_defaults(fn=cmd_attest)

    v = sub.add_parser("verify")
    v.add_argument("--artifact", required=True)
    v.add_argument("--envelope", required=True)
    v.add_argument("--key", default=None)
    v.add_argument("--allow-unsigned", action="store_true")
    v.set_defaults(fn=cmd_verify)

    args = ap.parse_args(argv)
    if args.cmd == "attest" and not args.name:
        args.name = Path(args.artifact).name
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
