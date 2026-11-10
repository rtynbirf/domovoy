# W4-MERGE-EVIDENCE · влитие proven-works в main (волна ×4, W4-E)

Дата: 2026-11-09 · ворклог-доказательство для пломбы SEALS.jsonl seq 11.

## Факт

Ветка `proven-works` (6 коммитов работы 2026-10-27) влита в `main` обычным
merge-коммитом **по П-09 (SEALS как хеш-цепь), не силой**: без force-push,
история целая, обе родословные в одном графе (КОСЯКИ H-PE11-PHOENIX #4, п.1).

- Merge-коммит: `3b71f41` (full sha — `git rev-parse 3b71f41`)
- Родитель A (main до влития): `810c2c5`
- Родитель B (голова proven-works): `b9ab918`

## Влитые коммиты (родословная B)

| SHA | Суть |
|---|---|
| `b9ab918` | proven-works: состав бисекции 0.2-BISECT (что изменено против alpha-0.1) |
| `080baaa` | proven-works: свидетельства Law 4 — хеши 10 частей + целого ISO 0.2-BISECT |
| `05f8b9d` | proven-works: PHX-DISK-PREP.bat v2.0 — снос только огрызка System 100 МБ, двойное подтверждение |
| `2dc9932` | proven-works: PHX-GLUE-BISECT.bat v5 — склейка частей + Law 4 (приём проверен на alpha-0.1) |
| `0442853` | proven-works: полный алгоритм Ф0 (замысел) -> готовый Windows+WinPE на ПК, раскомментирован |
| `76bae1b` | proven-works: правило ветки (только реально работающее) + карта файлов |

## Файлы, привнесённые в main

`ALGORITM-OT-ZAMESLA-DO-SBORNIKA.md` · `PROVEN/README-BISECT-RU.txt` ·
`PROVEN/SHA256SUMS-BISECT.txt` · `scripts/PHX-DISK-PREP.bat` ·
`scripts/PHX-GLUE-BISECT.bat` (+ `PROVEN/README-PROVEN-WORKS.md` — архив
правила ветки; README main сохранён без изменений).

## Разрешение README

Автоматический merge подставил версию ветки (main не правил README с точки
ветвления). Принято решение волны: README main сохранён (канон проекта),
правило ветки и карта файлов заархивированы дословно в
`PROVEN/README-PROVEN-WORKS.md` — ничего не потеряно, канон не повреждён.

## Свидетельства Law 4 (теперь в main)

Целый ISO 0.2-BISECT: `sha256 = 12332871ac64bc2fb21b0139a927f6ea8972378004ebcd5d5aaaac3c8ccfd43a`
(строка в `PROVEN/SHA256SUMS-BISECT.txt` после маркера «целый ISO»);
аттестационный конверт: `PROVEN/ATTEST-0.2-BISECT.json` (subject digest ==
эта строка == поле `evidence_sha256_iso` пломбы seq 11).

## Как проверить

```
git log --oneline 810c2c5..3b71f41          # влитые коммиты в main
git merge-base --is-ancestor b9ab918 main   # ветка — предок main (exit 0)
python3 tools/verify_seals.py SEALS.jsonl   # цепь цела, 0 разрывов
python3 tools/selftest_evidence.py          # A/B/C/D секции selftest
```
