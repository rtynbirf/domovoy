#!/bin/bash
# H-PE11 // AMMO DOWNLOADER pass 2: curl.exe, Volume2, Notepad++, NTPWEdit
A=/home/z/my-project/build/hpe11v12/ammo
mkdir -p $A; cd $A
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"

# --- 1. curl.exe для Windows (актуальная сборка с curl.se) ---
if [ ! -s curl_win64.zip ]; then
  CURLPAGE=$(curl -sL --max-time 60 -A "$UA" https://curl.se/windows/)
  CURLURL=$(echo "$CURLPAGE" | grep -oE 'dl-[0-9._]+/curl-[0-9._]+_1-win64-mingw\.zip' | head -1)
  [ -z "$CURLURL" ] && CURLURL=$(echo "$CURLPAGE" | grep -oE 'dl-[0-9._]+/curl-[0-9._a-z]+-win64-mingw\.zip' | head -1)
  echo "curl build: $CURLURL"
  [ -n "$CURLURL" ] && curl -sL --retry 4 -A "$UA" --max-time 300 -o curl_win64.zip "https://curl.se/windows/$CURLURL"
  sz=$(stat -c%s curl_win64.zip 2>/dev/null || echo 0); m=$(head -c 4 curl_win64.zip | od -An -tx1 | tr -d ' \n')
  if [ "$sz" -lt 1000000 ] || [ "${m:0:8}" != "504b0304" ]; then echo "[--] curl_win64.zip невалиден ($sz, $m)"; rm -f curl_win64.zip; fi
fi

# --- 2. Volume2 (irzyxa) — releases.atom -> ассет zip ---
if [ ! -s volume2.zip ]; then
  ATOM=$(curl -sL --max-time 60 -A "$UA" https://github.com/irzyxa/Volume2/releases.atom)
  TAG=$(echo "$ATOM" | grep -oE 'Volume2/releases/tag/[^<"]+' | head -1 | sed 's|.*/tag/||')
  echo "Volume2 tag: $TAG"
  if [ -n "$TAG" ]; then
    PAGE=$(curl -sL --max-time 60 -A "$UA" "https://github.com/irzyxa/Volume2/releases/tag/$TAG" -H "Accept: text/html")
    ASSET=$(echo "$PAGE" | grep -oE '/irzyxa/Volume2/releases/download/[^"]+\.zip' | head -1)
    echo "Volume2 asset: $ASSET"
    [ -n "$ASSET" ] && curl -sL --retry 4 -A "$UA" --max-time 600 -o volume2.zip "https://github.com$ASSET"
    sz=$(stat -c%s volume2.zip 2>/dev/null || echo 0); m=$(head -c 4 volume2.zip | od -An -tx1 | tr -d ' \n')
    if [ "$sz" -lt 3000000 ] || [ "${m:0:8}" != "504b0304" ]; then echo "[--] volume2.zip невалиден ($sz, $m)"; rm -f volume2.zip; fi
  fi
fi

# --- 3. Notepad++ portable x64 ---
if [ ! -s npp_portable.zip ]; then
  ATOM=$(curl -sL --max-time 60 -A "$UA" https://github.com/notepad-plus-plus/notepad-plus-plus/releases.atom)
  TAG=$(echo "$ATOM" | grep -oE 'notepad-plus-plus/releases/tag/[^<"]+' | head -1 | sed 's|.*/tag/||')
  echo "NPP tag: $TAG"
  if [ -n "$TAG" ]; then
    V=$(echo "$TAG" | sed 's/^v//')
    curl -sL --retry 4 -A "$UA" --max-time 300 -o npp_portable.zip "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/$TAG/npp.$V.portable.x64.zip"
    sz=$(stat -c%s npp_portable.zip 2>/dev/null || echo 0); m=$(head -c 4 npp_portable.zip | od -An -tx1 | tr -d ' \n')
    if [ "$sz" -lt 1000000 ] || [ "${m:0:8}" != "504b0304" ]; then echo "[--] npp_portable.zip невалиден ($sz, $m)"; rm -f npp_portable.zip; fi
  fi
fi

# --- 4. NTPWEdit (замена/дубль Login Unlocker) ---
if [ ! -s ntpwedit.zip ]; then
  for U in "https://sourceforge.net/projects/ntpwedit/files/ntpwedit%200.5.zip/download" "https://downloads.sourceforge.net/project/ntpwedit/ntpwedit%200.5.zip"; do
    curl -sL --retry 3 -A "$UA" --max-time 300 -o ntpwedit.zip "$U"
    sz=$(stat -c%s ntpwedit.zip 2>/dev/null || echo 0); m=$(head -c 4 ntpwedit.zip | od -An -tx1 | tr -d ' \n')
    if [ "$sz" -ge 100000 ] && [ "${m:0:8}" = "504b0304" ]; then echo "[x] ntpwedit.zip ($sz)"; break; else rm -f ntpwedit.zip; fi
  done
  [ -s ntpwedit.zip ] || echo "[--] ntpwedit недоступен"
fi

# --- 5. VC2013 через aka.ms ---
for n in x64 x86; do
  [ -s vc2013_$n.exe ] || {
    curl -sL --retry 3 -A "$UA" --max-time 300 -o vc2013_$n.exe "https://aka.ms/vs/12/release/vc_redist.$n.exe"
    m=$(head -c 2 vc2013_$n.exe | od -An -tx1 | tr -d ' \n'); sz=$(stat -c%s vc2013_$n.exe 2>/dev/null || echo 0)
    if [ "${m:0:4}" = "4d5a" ] && [ "$sz" -ge 4000000 ]; then echo "[x] vc2013_$n.exe ($sz)"; else rm -f vc2013_$n.exe; echo "[--] vc2013_$n"; fi
  }
done

echo "=== PASS 2 DONE ==="; ls -la
