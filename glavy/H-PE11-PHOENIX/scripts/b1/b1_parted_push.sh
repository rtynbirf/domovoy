#!/bin/bash
# Партионный пуш блобов: 5 веток-партий, затем финальное дерево в main.
set -e
# AUDIT-2026-1030 / FINDING-C1+C4: токен из gh_auth (env/credential store),
# URL без токена (виден в ps), push через credential helper.
. "$(dirname "$0")/../lib/gh_auth.sh"
TOKEN=$(gh_token) || exit 1
export GH_TOKEN="$TOKEN"
GH_HELPER='!f(){ echo username=x-access-token; echo "password=$GH_TOKEN"; };f'
URL="https://github.com/rtynbirf/H-PE11-PHOENIX.git"
W=/home/z/my-project/b1/gitwork
cd "$W"
BATCH=21
TOTAL=103

# полный список записей (103 чанка; манифест добавится в финале)
python3 - <<'EOF' > all_lines.txt
import json
m = json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json'))
repo_dir = m.get('repo_dir', 'artifacts/iso_26100.1_pro_ru')
for p in m['parts']:
    print(f"100644 blob {p['blob_sha1']}\t{repo_dir}/{p['name']}")
EOF

PREV=""
i=0; part=1
while [ $i -lt $TOTAL ]; do
  git read-tree FETCH_HEAD
  head -n $((i + BATCH)) all_lines.txt | git update-index --index-info
  TREE=$(git write-tree)
  if [ -z "$PREV" ]; then
    COMMIT=$(git commit-tree "$TREE" -m "PHOENIX11: ISO upload part $part (blobs on server) [Task 40]")
  else
    COMMIT=$(git commit-tree "$TREE" -p "$PREV" -m "PHOENIX11: ISO upload part $part (blobs on server) [Task 40]")
  fi
  echo "part $part: tree=${TREE:0:10} commit=${COMMIT:0:10} (строк $((i + BATCH)))"
  git -c "credential.helper=$GH_HELPER" push "$URL" "$COMMIT:refs/heads/iso_tmp_$part" 2>&1 | tail -1
  PREV=$COMMIT
  i=$((i + BATCH)); part=$((part + 1))
done
echo "LAST_COMMIT=$PREV" > /home/z/my-project/b1/last_part_commit.txt
echo "ALL_PARTS_PUSHED"
