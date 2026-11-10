# Протокол cosign-аттестации ISO 0.2-BISECT (ПРЕДЛОЖЕНИЕ-40, issue #5)

ISO не живёт в репозитории (`.gitignore: *.iso` — Law 4 живёт в хешах:
`PROVEN/SHA256SUMS-BISECT.txt`), а cosign/ключи — внешние зависимости.
Поэтому машина подготовила всё, что можно сделать без внешнего сервиса,
и документировала оставшийся шаг — он выполняется вручную при наличии
артефакта и ключа.

## Что уже исполняется автоматически (CI `evidence-chain`)

- `PROVEN/ATTEST-0.2-BISECT.json` — DSSE-конверт (структура 1-в-1 как у
  cosign attestations): payload = in-toto Statement с `predicateType
  https://slsa.dev/provenance/v0.2`, subject digest = sha256 целого ISO
  `12332871ac64…43a` == строке PROVEN == полю `evidence_sha256_iso` пломбы
  seq 11 в SEALS.jsonl.
- Конверт unsigned (sig: null): дайджест зафиксирован машиной, подпись
  в конверт добавляет Хозяин (ниже). `tools/iso_attest.py verify
  --allow-unsigned` проверяет дайджест; с ключом — и подпись (HMAC-SHA256
  по DSSE PAE, stdlib-заготовка).

## Ручной шаг Хозяина (когда ISO и cosign под рукой)

```bash
# 0. Собрать/склеить ISO и сверить Law 4:
sha256sum -c <(grep -E 'iso(\.part[0-9]+)?' PROVEN/SHA256SUMS-BISECT.txt)

# 1. Ключ cosign (Local Key Pairs достаточно):
COSIGN_PASSWORD=... cosign generate-key-pair --output-key-prefix phx-cosign

# 2. Аттестация блоба (SLSA-провенанс; predicate можно взять из payload
#    PROVEN/ATTEST-0.2-BISECT.json, заменив HMAC-подписанта на cosign):
cosign attest-blob --yes --key phx-cosign.key \
  --predicate PROVEN/ATTEST-0.2-BISECT.json \
  --type slsaprovenance \
  PHOENIX-ALPHA-0.2-BISECT.iso

# 3. Проверка (приёмка issue #5):
cosign verify-blob --key phx-cosign.pub \
  --signature PHOENIX-ALPHA-0.2-BISECT.iso.bundle \
  --certificate-identity-regexp '.' --certificate-oidc-issuer-regexp '.' \
  PHOENIX-ALPHA-0.2-BISECT.iso
# sha256 из verify обязан совпасть со строкой ISO в PROVEN/SHA256SUMS-BISECT.txt
# и с полем evidence_sha256_iso пломбы seq 11 (SEALS.jsonl).
```

## Правила

- Подпись добавляется ТОЛЬКО к артефакту, чей sha256 уже стоит в PROVEN и
  SEALS (сначала хеш — потом дело, Law 4).
- Конверт и пломбы append-only: перегенерация payload после подписи = новая
  пломба в SEALS.jsonl, не правка старой.
- `.gitignore` не принимает `*.key/*.pem` — ключи никогда не попадают в репо.
