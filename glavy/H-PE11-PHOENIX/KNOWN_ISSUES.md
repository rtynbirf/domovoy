# KNOWN ISSUES · H-PE11-PHOENIX — известные красные и шрамы
> Снимок Волны ×5 (2026-11-09). Живые красные прогоны + известные квирки.

| Что | Статус | Детали | Run/ссылка |
|---|---|---|---|
| evidence-chain 19:47 (64a7c0b) | 🟢 вылечено | Failed to CreateArtifact: Artifact storage quota has been hit — квота аккаунта, не баг цепи | [42516765261](https://github.com/rtynbirf/H-PE11-PHOENIX/actions/runs/42516765261) |
| evidence-chain 19:50 (1243ff6) | 🟢 вылечено | та же квотная стена на шаге «Память прогона — отчёт артефактом» | [42517010805](https://github.com/rtynbirf/H-PE11-PHOENIX/actions/runs/42517010805) |
| фикс: шаг upload-artifact снят | ✅ в main | Волна ×4 commit 7b75747; witness = сам прогон + голова цепочки в summary; зелёный push-прогон | [42517215938](https://github.com/rtynbirf/H-PE11-PHOENIX/actions/runs/42517215938) |
| ⬜ квота Artifact storage аккаунта | 🟜 честный хвост | нужен хозяин/биллинг: расчистить хранилище или поднять квоту; до того upload-artifact в этом репо (и по аккаунту) красит воркфлоу | docs.github.com/billing |
| Квирк: cosign verify с ключом | ℹ️ шаг хозяина | PROVEN/COSIGN-ATTEST-PROTOCOL.md — ключ не может быть в рое | issue #3 / П-09 |
