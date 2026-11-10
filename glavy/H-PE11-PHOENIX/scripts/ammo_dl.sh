#!/bin/bash
# H-PE11 // AMMO DOWNLOADER v1.2 (песочница) — каждый файл проверяется (грабля #2)
A=/home/z/my-project/build/hpe11v12/ammo
mkdir -p $A; cd $A
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"
dl() { # dl <url> <out> <min_bytes> [magic]
  local url="$1" out="$2" min="$3" magic="$4"
  [ -s "$out" ] && [ "$(stat -c%s "$out")" -ge "$min" ] && { echo "[skip] $out"; return 0; }
  curl -sL --retry 4 --retry-delay 3 -A "$UA" --max-time 600 -o "$out" "$url"
  local sz=$(stat -c%s "$out" 2>/dev/null || echo 0)
  if [ "$sz" -lt "$min" ]; then echo "[--] $out ($sz B < $min): $(head -c 120 "$out" | tr -d '\0' | head -1)"; rm -f "$out"; return 1; fi
  if [ -n "$magic" ]; then
    local m=$(head -c 8 "$out" | od -An -tx1 | tr -d ' \n')
    case "$magic" in
      MZ) [ "${m:0:4}" = "4d5a" ] || { echo "[--] $out: magic=$m (не MZ)"; rm -f "$out"; return 1; };;
      PK) [ "${m:0:8}" = "504b0304" ] || { echo "[--] $out: magic=$m (не PK)"; rm -f "$out"; return 1; };;
      XZ) [ "${m:0:8}" = "fd377a58" ] || { echo "[--] $out: magic=$m (не XZ)"; rm -f "$out"; return 1; };;
      EXE) [ "${m:0:4}" = "4d5a" ] || { echo "[--] $out: magic=$m (не MZ)"; rm -f "$out"; return 1; };;
    esac
  fi
  echo "[x] $out ($sz B)"
}
dl "https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.zip" "PowerShell-7.4.6-win-x64.zip" 50000000 PK &
dl "https://download.sysinternals.com/files/SysinternalsSuite.zip" "SysinternalsSuite.zip" 20000000 PK &
dl "https://www.7-zip.org/a/7zr.exe" "7zr.exe" 500000 MZ &
dl "https://www.wintun.net/builds/wintun-0.14.1.zip" "wintun-0.14.1.zip" 500000 PK &
dl "https://aka.ms/vs/17/release/vc_redist.x64.exe" "vc_redist.x64.exe" 1000000 EXE &
dl "https://aka.ms/vs/17/release/vc_redist.x86.exe" "vc_redist.x86.exe" 1000000 EXE &
dl "https://download.microsoft.com/download/2/E/6/2E61CFA4-994B-4D41-B093-E0168F017695/vcredist_x64.exe" "vc2013_x64.exe" 5000000 EXE &
dl "https://download.microsoft.com/download/2/E/6/2E61CFA4-994B-4D41-B093-E0168F017695/vcredist_x86.exe" "vc2013_x86.exe" 5000000 EXE &
dl "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe" "vc2012_x64.exe" 5000000 EXE &
dl "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe" "vc2012_x86.exe" 5000000 EXE &
dl "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe" "vc2010_x64.exe" 2000000 EXE &
dl "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe" "vc2010_x86.exe" 2000000 EXE &
dl "https://download.microsoft.com/download/8/4/A/84A35BF1-DA19-4B86-B24B-84E23B4F3E71/directx_Jun2010_redist.exe" "directx_Jun2010_redist.exe" 50000000 EXE &
dl "https://eternallybored.org/misc/wget/current/wget64.exe" "wget64.exe" 200000 MZ &
wait
# 7-Zip Linux static (для распаковки ISO здесь) + Windows 7zr уже выше
dl "https://www.7-zip.org/a/7z2601-linux-x64.tar.xz" "7z-linux.tar.xz" 1000000 XZ || \
dl "https://www.7-zip.org/a/7z2501-linux-x64.tar.xz" "7z-linux.tar.xz" 1000000 XZ
mkdir -p /home/z/my-project/build/hpe11v12/tools7z && tar -xJf 7z-linux.tar.xz -C /home/z/my-project/build/hpe11v12/tools7z 2>/dev/null && echo "[x] 7z-linux распакован: $(/home/z/my-project/build/hpe11v12/tools7z/7zz | head -2 | tail -1)"
echo "=== AMMO PASS 1 DONE ==="; ls -la $A
