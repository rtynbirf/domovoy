#!/bin/bash
# H-PE11 B-1: получение ссылки на официальный Win11 ISO через API Microsoft (метод Fido)
set -u
BASE=/home/z/my-project
MEDIA=$BASE/media
mkdir -p "$MEDIA"
JAR=$MEDIA/ms_cookies.txt
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
SVC="https://www.microsoft.com/en-us/api/controls/contentinclude/html"

# 1) первичный GET — куки сессии
curl -s -c "$JAR" -A "$UA" "https://www.microsoft.com/en-us/software-download/windows11" -o "$MEDIA/landing.html"
grep -o 'sessionId=[a-f0-9-]*' "$MEDIA/landing.html" | head -1 > "$MEDIA/session.txt" || true
SESSION=$(cat "$MEDIA/session.txt" | cut -d= -f2)
[ -z "$SESSION" ] && SESSION=$(cat /proc/sys/kernel/random/uuid)
echo "session: $SESSION"

get_page() { # $1=action $2=params-extra
  curl -s -b "$JAR" -c "$JAR" -A "$UA" -L \
    "$SVC?pageId=a8f8f489-4c7f-463a-9ca6-5cff94d8d041&host=www.microsoft.com&segments=software-download,windows11&query=&action=$1&sessionId=$SESSION&productEditionId=3526&requestType=manual&$2" \
    -o "$MEDIA/$1.html"
  wc -c "$MEDIA/$1.html"
}

# productEditionId 3526 — Win11 25H2 (проверяем по ответу; если пусто — переберём)
for ED in 3526 3426 3051; do
  curl -s -b "$JAR" -c "$JAR" -A "$UA" -L \
    "$SVC?pageId=a8f8f489-4c7f-463a-9ca6-5cff94d8d041&host=www.microsoft.com&segments=software-download,windows11&query=&action=getinfo&sessionId=$SESSION&productEditionId=$ED&requestType=manual" \
    -o "$MEDIA/info_$ED.html"
  SIZE=$(wc -c < "$MEDIA/info_$ED.html")
  SKUS=$(grep -o 'skuId=[0-9]*' "$MEDIA/info_$ED.html" | head -3 | tr '\n' ' ')
  echo "ED=$ED size=$SIZE sku:$SKUS"
  if [ "$SIZE" -gt 2000 ] && [ -n "$SKUS" ]; then
    echo "WORKING_ED=$ED" > "$MEDIA/working_ed.txt"
    grep -o '<option value="[0-9]*"[^>]*>[^<]*' "$MEDIA/info_$ED.html" | head -10 > "$MEDIA/skus_$ED.txt"
    cat "$MEDIA/skus_$ED.txt"
    break
  fi
done
