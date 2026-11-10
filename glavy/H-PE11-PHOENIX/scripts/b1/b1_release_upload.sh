#!/bin/bash
# Заливка ISO в релиз ассетами ~1GB (26 блобов по 40MiB каждый).
set -e
# AUDIT-2026-1030 / FINDING-C1 + EXTRA: токен из gh_auth; заголовок авторизации
# подаётся в curl через временный файл (-H @file), чтобы токен не светился в argv/ps.
. "$(dirname "$0")/../lib/gh_auth.sh"
TOKEN=$(gh_token) || exit 1
HDR_FILE=$(mktemp "${TMPDIR:-/tmp}/phx_hdr.XXXXXX")
trap 'rm -f "$HDR_FILE"' EXIT INT TERM
printf 'Authorization: Bearer %s\n' "$TOKEN" > "$HDR_FILE"
chmod 600 "$HDR_FILE"
REL=423072681
UP="https://uploads.github.com/repos/rtynbirf/H-PE11-PHOENIX/releases/${REL}/assets?name="
W=/home/z/my-project/b1/gitwork
ADIR=/home/z/my-project/b1/asset
mkdir -p "$ADIR"

declare -a NAMES=(iso.part00.iso iso.part01.iso iso.part02.iso iso.part03.iso)
declare -a RANGES=("0:25" "26:51" "52:77" "78:102")

for k in 0 1 2 3; do
  NAME=${NAMES[$k]}
  IFS=':' read -r A B <<< "${RANGES[$k]}"
  echo "=== ASSET $NAME (блобы $A..$B) $(date -u +%H:%M:%S) ==="
  rm -f "$ADIR/$NAME"
  for i in $(seq $A $B); do
    SHA=$(python3 -c "import json; m=json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json')); print(m['parts'][$i]['blob_sha1'])")
    git -C "$W" cat-file blob "$SHA" >> "$ADIR/$NAME"
  done
  SIZE=$(stat -c %s "$ADIR/$NAME")
  SHA256=$(sha256sum "$ADIR/$NAME" | awk '{print $1}')
  echo "собран: $SIZE байт, sha256=${SHA256:0:16}..."
  echo "$SHA256  $NAME" >> "$ADIR/SHA256SUMS_ASSETS.txt"
  echo "upload $NAME..."
  HTTP=$(curl -sS -X POST -H @"$HDR_FILE" -H "Content-Type: application/octet-stream" \
    --data-binary "@$ADIR/$NAME" \
    "${UP}${NAME}" -w "%{http_code}" -o /home/z/my-project/b1/asset/upload_resp_$k.json)
  echo "upload HTTP=$HTTP $(date -u +%H:%M:%S)"
  if [ "$HTTP" != "201" ]; then cat /home/z/my-project/b1/asset/upload_resp_$k.json | head -c 300; echo; exit 1; fi
  rm -f "$ADIR/$NAME"
  echo "=== $NAME DONE ==="
done
echo "ALL_ASSETS_UPLOADED"
