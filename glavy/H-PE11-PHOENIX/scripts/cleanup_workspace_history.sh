#!/bin/bash
# ============================================================================
# cleanup_workspace_history.sh — очистка локальной git-истории workspace от
# токен-блобов (AUDIT-2026-1030 / HIGH: историческое хранение PAT).
#
# ЗАЧЕМ: в локальном workspace (/home/z/my-project) токен-файлы (.gh_token,
# .phx_gh_token, upload/Pasted Content*.txt) отслеживались git-индексом на
# протяжении ~55 коммитов. Любой будущий первый push разложит историю с
# токенами на GitHub. Запусти ЭТОТ скрипт ДО первого push.
#
# ЧТО ДЕЛАЕТ:
#   0. Спрашивает подтверждение (или запускай: YES=1 bash cleanup_workspace_history.sh)
#   1. Бэкап всей истории в bundle рядом с workspace (откат возможен всегда)
#   2. Сохраняет .gh_token/.phx_gh_token в байт-копии и возвращает на диск
#      с правами 600 (было 755 — world-readable)
#   3. git rm --cached токен-файлов + .gitignore уже покрывает их
#   4. git filter-repo --invert-paths вычищает блобы из ВСЕЙ истории
#   5. git gc — физически удаляет мёртвые объекты
#
# ТРЕБОВАНИЯ: pip install git-filter-repo (скрипт установит сам при нужде)
# ЗАПУСК:     bash cleanup_workspace_history.sh   (из любого места)
# ============================================================================
set -euo pipefail

WS="${WS:-/home/z/my-project}"
BACKUP_DIR="${BACKUP_DIR:-$WS/backups}"
STAMP=$(date +%Y%m%d_%H%M%S)

echo "== Очистка git-истории workspace: $WS =="
echo "   Будут вычищены из истории: .gh_token, .phx_gh_token, upload/Pasted Content*.txt"
echo "   Бэкап: $BACKUP_DIR/workspace_history_$STAMP.bundle"

if [ "${YES:-0}" != "1" ]; then
  read -r -p "Продолжить? (введи ДА): " ans
  [ "$ans" = "ДА" ] || { echo "отменено"; exit 1; }
fi

cd "$WS"
[ -d .git ] || { echo "ОШИБКА: $WS не git-репозиторий"; exit 1; }

mkdir -p "$BACKUP_DIR"

# --- 1. Бэкап ---
echo "== 1/5 Бэкап истории =="
git bundle create "$BACKUP_DIR/workspace_history_$STAMP.bundle" --all
git status --porcelain > "$BACKUP_DIR/workspace_status_$STAMP.txt" || true
echo "   бэкап готов: $(du -h "$BACKUP_DIR/workspace_history_$STAMP.bundle" | cut -f1)"

# --- 2. Сохранить живые токен-файлы (они нужны скриптам вне git) ---
echo "== 2/5 Сохранение живых файлов с диска =="
KEEP=()
for f in .gh_token .phx_gh_token; do
  if [ -f "$WS/$f" ]; then
    cp "$WS/$f" "$BACKUP_DIR/$(basename "$f").$STAMP"
    chmod 600 "$BACKUP_DIR/$(basename "$f").$STAMP"
    KEEP+=("$f")
    echo "   сохранён $f (права в бэкапе 600)"
  fi
done

# --- 3. git rm --cached (снять с отслеживания в HEAD) ---
echo "== 3/5 Снятие с отслеживания =="
git rm --cached --ignore-unmatch .gh_token .phx_gh_token 'upload/Pasted Content*.txt' 2>/dev/null || true
# вернуть файлы на диск, если rm --cached их не тронул (не должен), и зафиксировать права
for f in "${KEEP[@]:-}"; do
  [ -n "$f" ] && [ -f "$BACKUP_DIR/$(basename "$f").$STAMP" ] && [ ! -f "$WS/$f" ] && \
    cp "$BACKUP_DIR/$(basename "$f").$STAMP" "$WS/$f" && chmod 600 "$WS/$f" || true
done
[ -f "$WS/.gh_token" ] && chmod 600 "$WS/.gh_token" || true
[ -f "$WS/.phx_gh_token" ] && chmod 600 "$WS/.phx_gh_token" || true

# --- 4. filter-repo: вычистить блобы из всей истории ---
echo "== 4/5 Переписывание истории (git filter-repo) =="
python3 -c "import git_filter_repo" 2>/dev/null || pip install --quiet git-filter-repo
git filter-repo --force --invert-paths \
  --path .gh_token \
  --path .phx_gh_token \
  --path-glob 'upload/Pasted Content*.txt'

# --- 5. Сборка мусора + контроль ---
echo "== 5/5 git gc + контроль =="
git reflog expire --expire=now --all 2>/dev/null || true
git gc --prune=now --aggressive 2>/dev/null || git gc --prune=now
LEFT=$(git log --all --oneline -- .gh_token .phx_gh_token | wc -l)
echo "   коммитов с токен-файлами в истории осталось: $LEFT (должно быть 0)"
if [ "$LEFT" != "0" ]; then
  echo "ВНИМАНИЕ: остались следы — сверься с бэкапом и повтори вручную."
  exit 2
fi

cat <<'EOF'

ГОТОВО. Что дальше:
  - история workspace чиста от токен-блобов (проверка выше);
  - живые токен-файлы на диске (права 600), в git больше не отслеживаются;
  - .gitignore уже покрывает .gh_token/.phx_gh_token/cred.sh (см. репо H-PE11-PHOENIX);
  - скрипты репы теперь берут токен из GH_TOKEN/credential store (scripts/lib/gh_auth.*);
  - бэкап истории лежит в backups/ — после уверенной проверки можно удалить.
Рекомендация: секреты больше не хранить plaintext в workspace; GH_TOKEN — в
окружении или git credential store (git config --global credential.helper store).
EOF
