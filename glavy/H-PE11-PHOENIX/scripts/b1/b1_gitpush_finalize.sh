#!/bin/bash
# Финализация main через нативный git push. v4 (AUDIT-2026-1030 / FINDING-C2):
#   - токен из gh_auth (env/credential store), plaintext-файлы не читаются
#   - credential helper во временном файле mktemp с правами 700, путь уникален
#   - trap-очистка при ЛЮБОМ исходе (EXIT/INT/TERM) — cred-файл не остаётся на диске
#   - set -euo pipefail: неудачный push реально роняет скрипт (раньше маскировался tail)
set -euo pipefail
W=/home/z/my-project/b1/gitwork
CRED_FILE=""

cleanup() {
  if [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then rm -f "$CRED_FILE"; fi
  if [ -f "$W/.git/config" ]; then git config --unset credential.helper 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

. "$(dirname "$0")/../lib/gh_auth.sh"
TOKEN=$(gh_token) || exit 1

rm -rf "$W"
mkdir -p "$W"
cd "$W"
git init -q
git config user.name "PHOENIX11"
git config user.email "phoenix11@noreply.local"
CRED_FILE=$(mktemp "${TMPDIR:-/tmp}/phx_cred.XXXXXX")
chmod 700 "$CRED_FILE"
printf '#!/bin/bash\necho username=x-access-token\necho password=%s\n' "$TOKEN" > "$CRED_FILE"
git config credential.helper "$CRED_FILE"
URL=https://github.com/rtynbirf/H-PE11-PHOENIX.git
git fetch --quiet "$URL" main
PARENT=$(git rev-parse FETCH_HEAD)
echo "parent=$PARENT"

MAN_BLOB_SHA=$(python3 -c "
import json,hashlib
m=json.dumps(json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json')),indent=1).encode()
print(hashlib.sha1(f'blob {len(m)}\0'.encode()+m).hexdigest())")

python3 - <<EOF > tree_input.txt
import json
m = json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json'))
repo_dir = m.get('repo_dir', 'artifacts/iso_26100.1_pro_ru')
for p in m['parts']:
    print(f"100644 blob {p['blob_sha1']}\t{repo_dir}/{p['name']}")
print(f"100644 blob ${MAN_BLOB_SHA}\t{repo_dir}/MANIFEST.json")
EOF

TREE=$(git mktree --missing < tree_input.txt)
echo "tree=$TREE"
COMMIT=$(git commit-tree "$TREE" -p "$PARENT" -m "PHOENIX11: WILLIAM B1 ISO 26100.1_PROFESSIONAL_X64_RU-RU.ISO (26300.9807 ru-RU Pro, 26H2, uupdump converter v0.7.3, 103 чанка x 40MiB, sha256 f08f504ee044e83942b79660b773021ebadf66b3d45195f2156237a2a771e1c0) [Task 40]")
echo "commit=$COMMIT"
git push "$URL" "$COMMIT:refs/heads/main" 2>&1 | tail -3
echo "PUSH_DONE"
