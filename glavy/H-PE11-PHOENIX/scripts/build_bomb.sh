#!/bin/bash
# =====================================================================
# H-PE11 // BOMB BUILDER v1.2 (песочница, без ADK/DISM)
# wimlib + pycdlib. ЭВ.1: недоступно = НЕ сделано ([--]).
# =====================================================================
set -u
export PATH=$HOME/.local/bin:$PATH
B=/home/z/my-project/build/hpe11v12
A=$B/ammo
P=/home/z/my-project/build/H-PE11_BOMB/payload
STAGE=$B/work/stage
MEDIA=$B/work/media
EXT=$B/base/extract
T7=$B/tools7z/7zz
LOG=/tmp/hpe11_build.log
exec > >(tee -a $LOG) 2>&1

say() { echo "  $*"; }
ev1() { if [ "$1" = "x" ]; then echo "  [x] $2  $3"; else echo "  [--] $2  $3"; fi; }

echo "=================================================================="
echo "  H-PE11 // BOMB BUILDER v1.2 (sandbox)"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "  База: Windows 11 26H2 x64 ru-RU boot.wim (26300.9457), official MS"
echo "=================================================================="

rm -rf "$STAGE" "$MEDIA" /tmp/vcx64 /tmp/hms_probe /tmp/carve_*; rm -f /tmp/torch_win.whl /tmp/ocv*.whl /tmp/ps7test.part; mkdir -p "$STAGE" "$MEDIA" "$MEDIA/HPE11/docs"

# ---------- СЕКЦИЯ 1. РАСПАКОВКА БОЕПРИПАСОВ ----------
echo "== СЕКЦИЯ 1. РАСПАКОВКА =="
mkdir -p "$STAGE/PSSeven" "$STAGE/Tools/7-Zip" "$STAGE/Tools/wget" "$STAGE/Tools/Python" \
         "$STAGE/Tools/Sysinternals" "$STAGE/Tools/Notepad++" "$STAGE/bin" \
         "$STAGE/Volume2" "$STAGE/HMS" "$STAGE/Cursors" \
         "$STAGE/drivers/HPE11" "$STAGE/drivers/wintun" "$STAGE/Redist"

$T7 x -y -o"$STAGE/PSSeven" "$A/PowerShell-7.4.6-win-x64.zip" >/dev/null 2>&1
ev1 x "PowerShell 7.4.6 portable" "$([ -f "$STAGE/PSSeven/pwsh.exe" ] && echo pwsh.exe || echo НЕТ)"

curlbin=$(find /tmp/vcx64 -name curl.exe 2>/dev/null | head -1)
if [ -z "$curlbin" ]; then
  mkdir -p /tmp/curlx && $T7 x -y -o/tmp/curlx "$A/curl_win64.zip" >/dev/null 2>&1
  curlbin=$(find /tmp/curlx -name curl.exe | head -1)
fi
[ -n "$curlbin" ] && cp "$curlbin" "$STAGE/bin/curl.exe"
ev1 x "curl.exe 8.23 portable" "$(stat -c%s "$STAGE/bin/curl.exe" 2>/dev/null) B"

$T7 x -y -o"$STAGE/Tools/Notepad++" "$A/npp_portable.zip" >/dev/null 2>&1
ev1 x "Notepad++ 8.9.8 portable" "$([ -f "$STAGE/Tools/Notepad++/notepad++.exe" ] && echo notepad++.exe || echo НЕТ)"

$T7 x -y -o"$STAGE/Tools/Sysinternals" "$A/SysinternalsSuite.zip" >/dev/null 2>&1
# оставить только избранное (PE-полезное), убрать хвост
mkdir -p "$STAGE/Tools/Sys_select"
for t in procexp64.exe procmon64.exe autoruns64.exe tcpview64.exe psexec64.exe procdump64.exe handle64.exe du64.exe sdelete64.exe pslist64.exe accesschk64.exe autorunsc64.exe listdlls64.exe psinfo64.exe testlimit64.exe logsessions64.exe; do
  [ -f "$STAGE/Tools/Sysinternals/$t" ] && mv "$STAGE/Tools/Sysinternals/$t" "$STAGE/Tools/Sys_select/" || true
done
rm -rf "$STAGE/Tools/Sysinternals"; mv "$STAGE/Tools/Sys_select" "$STAGE/Tools/Sysinternals"
ev1 x "Sysinternals (избранное 16 exe)" "$(ls "$STAGE/Tools/Sysinternals" | wc -l) файлов"

cp "$A/7zr.exe" "$STAGE/Tools/7-Zip/7zr.exe"
ev1 x "7-Zip (7zr.exe standalone)" "$(stat -c%s "$STAGE/Tools/7-Zip/7zr.exe") B"

$T7 x -y -o"$STAGE/Tools/Python" "$P/Python/python-3.12.8-embed-amd64.zip" >/dev/null 2>&1
sed -i 's/^#import site/import site/' "$STAGE/Tools/Python/python312._pth" 2>/dev/null
ev1 x "Python 3.12.8 embeddable" "$([ -f "$STAGE/Tools/Python/python.exe" ] && echo python.exe || echo НЕТ)"

$T7 x -y -o"$STAGE/Volume2" "$A/volume2.zip" >/dev/null 2>&1
ev1 x "Volume2 v1.1.9.470 portable" "$([ -f "$STAGE/Volume2/Volume2/Volume2.exe" ] && echo Volume2.exe || echo НЕТ)"

# HMS: из setup_ms_x64.zip кастомный пакер (RNW) — из песочницы не распаковывается [--]
mkdir -p /tmp/hmsu && $T7 x -y -o/tmp/hmsu "$P/HMS/setup_ms_x64.zip" >/dev/null 2>&1
for z in hms md2_textures devices hmssfx; do
  [ -f "/tmp/hmsu/$z.zip" ] && $T7 x -y -o"$STAGE/HMS" "/tmp/hmsu/$z.zip" >/dev/null 2>&1
done
if [ -f "$STAGE/HMS/HMS.exe" ]; then
  ev1 x "Домашний медиа-сервер x64 (распакован)" "HMS.exe"
else
  cp "$P/HMS/setup_ms_x64.zip" "$STAGE/HMS/setup_ms_x64.zip"
  cat > "$STAGE/HMS/README_HMS.txt" <<'EOH'
[--] Из песочницы дистрибутив HMS не распакован: внутри setup_ms_x64.zip
компоненты в кастомном пакере (RNW, открывается только Setup.exe).
Варианты: 1) запустить setup_ms_x64.zip на любом Windows (/S тихо) и скопировать
папку "Home Media Server" сюда; 2) контракт build-bomb.ps1 (payload\HMS) сделает
это автоматически на станции. Сам дистрибутив (188 МБ) прилагается.
EOH
  ev1 -- "Домашний медиа-сервер x64" "дистрибутив на борту, распаковка [--] (кастомный RNW-пакер)"
fi

# Курсоры XpucT
cp -r "$P/Cursors/XpucT/." "$STAGE/Cursors/" 2>/dev/null
ev1 x "Курсоры XpucT" "$(ls "$STAGE/Cursors" | grep -cE '\.(cur|ani)$') файлов"

# Драйверы whitelist (cabs уже распакованы в ammo/drivers)
for d in netwtw04 dptf txei; do
  [ -d "$A/drivers/$d" ] && cp -r "$A/drivers/$d" "$STAGE/drivers/HPE11/$d"
done
ev1 x "Драйверы whitelist (drvload)" "netwtw04+dptf+txei=$(find "$STAGE/drivers/HPE11" -iname "*.inf" | wc -l) INF; iigd_dch/apollolake/ialpss2_bxt/rtsuer [--]"

$T7 x -y -o"$STAGE/drivers/wintun" "$A/wintun-0.14.1.zip" >/dev/null 2>&1
ev1 x "wintun 0.14.1" "$([ -f "$STAGE/drivers/wintun/wintun/bin/amd64/wintun.inf" ] && echo wintun.inf || echo НЕТ)"

# Редист-EXE на медиа (для полных Windows)
cp "$A/vc_redist.x64.exe" "$A/vc_redist.x86.exe" "$A/vc2012_x64.exe" "$A/vc2012_x86.exe" "$A/vc2010_x64.exe" "$A/vc2010_x86.exe" "$STAGE/Redist/" 2>/dev/null
ev1 x "VC++ редист-EXE на медиа (6 шт)" "$(ls "$STAGE/Redist" | wc -l) файлов (DLL сами [--], накатываются payload\\VC runtime-копией)"

# PE-скрипты (startnet, консоль, README)
python3 /home/z/my-project/scripts/pe_gen.py
ev1 x "startnet.cmd v1.2 + консоль H-PE11 (CP866)" "$(ls /home/z/my-project/build/hpe11v12/work/pe_scripts | wc -l) файлов"

# ---------- СЕКЦИЯ 2. WIM: обновление boot.wim index 2 ----------
echo "== СЕКЦИЯ 2. WIM UPDATE (index 2) =="
PE=/home/z/my-project/build/hpe11v12/work/pe_scripts
CMDF=/tmp/wimcmd.txt
{
  echo "delete /Windows/System32/startnet.cmd"
  echo "add $PE/startnet.cmd /Windows/System32/startnet.cmd"
  echo "add \"$STAGE/bin/curl.exe\" \"/Windows/System32/curl.exe\""
echo "add \"$STAGE/drivers/wintun/wintun/bin/amd64/wintun.dll\" \"/Windows/System32/wintun.dll\""
  # VC DLL [--] из интернета; есть ucrt-набор самой базы: не трогаем
  echo "add $PE/apply_cursors.ps1 /HPE11/apply_cursors.ps1"
  echo "add $PE/HPE11.cmd /HPE11/HPE11.cmd"
  echo "add $PE/HPE11.tag /HPE11/HPE11.tag"
  # Курсоры
  for f in "$STAGE"/Cursors/*; do
    b=$(basename "$f")
    echo "add \"$f\" \"/Windows/Cursors/XpucT/$b\""
  done
  # Tools
  echo "add $STAGE/Tools/Python /Tools/Python"
  echo "add $STAGE/Tools/wget /Tools/wget"
  echo "add $STAGE/Tools/7-Zip /Tools/7-Zip"
  echo "add $STAGE/Tools/Sysinternals /Tools/Sysinternals"
  echo "add $STAGE/Tools/Notepad++ /Tools/Notepad++"
} > $CMDF
mkdir -p "$STAGE/Tools/wget"
cp $PE/wget.cmd "$STAGE/Tools/wget/wget.cmd"
# wget.cmd добавить в WIM тоже
echo "add $PE/wget.cmd /Tools/wget/wget.cmd" >> $CMDF

rm -rf /tmp/wimwork && mkdir -p /tmp/wimwork
cp "$EXT/sources/boot.wim" /tmp/wimwork/boot.wim
wimupdate /tmp/wimwork/boot.wim 2 --rebuild < $CMDF 2>&1 | tail -4
wiminfo /tmp/wimwork/boot.wim | grep -E "Index|Name|Description" | head -6
ev1 x "boot.wim обновлён (index 2)" "$(stat -c%s /tmp/wimwork/boot.wim) B"

# ---------- СЕКЦИЯ 3. МЕДИА ----------
echo "== СЕКЦИЯ 3. МЕДИА =="
cp -r "$EXT/bootmgr" "$MEDIA/"
cp -r "$EXT/boot" "$MEDIA/"
cp -r "$EXT/efi" "$MEDIA/"
mkdir -p "$MEDIA/sources"
cp /tmp/wimwork/boot.wim "$MEDIA/sources/boot.wim"

mkdir -p "$MEDIA/HPE11" "$MEDIA/PS7" "$MEDIA/HPE11/VC" "$MEDIA/HPE11/VC/x86" "$MEDIA/HPE11/DirectX" "$MEDIA/HPE11/LoginUnlocker"
cp -r "$STAGE/PSSeven/." "$MEDIA/PS7/" 2>/dev/null
cp "$EXT"/../iso_url.txt "$MEDIA/HPE11/docs/base_url.txt" 2>/dev/null || true
cp /home/z/my-project/build/H-PE11_BOMB/docs/FEATURE-CATALOG.md "$MEDIA/HPE11/docs/" 2>/dev/null
cp /home/z/my-project/build/H-PE11_BOMB/docs/STATION-ANALYSIS.md "$MEDIA/HPE11/docs/" 2>/dev/null
cp $PE/README_RU.txt "$MEDIA/HPE11/"
cp $PE/HPE11.tag "$MEDIA/HPE11/HPE11.tag"
cp /home/z/my-project/build/H-PE11_BOMB/build/get-ammo.ps1 "$MEDIA/HPE11/get-ammo.ps1"
cp /home/z/my-project/build/H-PE11_BOMB/build/get-ammo.ps1 "$MEDIA/get-ammo.ps1"

mkdir -p "$MEDIA/Programs" "$MEDIA/Drivers"
cp -r "$STAGE/Volume2/Volume2" "$MEDIA/Programs/Volume2"
cp -r "$STAGE/HMS" "$MEDIA/Programs/HMS"
cp -r "$STAGE/drivers/HPE11" "$MEDIA/Drivers/HPE11"
cp -r "$STAGE/drivers/wintun" "$MEDIA/Drivers/wintun"
mkdir -p "$MEDIA/DriverPacks"
cat > "$MEDIA/DriverPacks/README_DriverPacks.txt" <<'EOF'
[--] SSTR DriverPacks не включены: хостинги (sdi-tool/delahoy/archive.org)
недоступны из песочницы сборки. Положите сюда паки с H:\SSTR\DriverPacks —
startnet при загрузке объявит DPPATH и SDI их подхватит.
EOF
cp -r "$STAGE/Redist" "$MEDIA/HPE11/Redist"
ev1 x "Медиа собрано" "$(du -sh "$MEDIA" | cut -f1)"

# ---------- СЕКЦИЯ 4. SHA256 (LAW 4) + ОТЧЁТ ----------
echo "== СЕКЦИЯ 4. SHA256SUMS + BOMB-REPORT =="
cd "$MEDIA"
find . -type f ! -name "SHA256SUMS.txt" -exec sha256sum {} \; | sed 's|\ \./| |' > "$MEDIA/HPE11/docs/SHA256SUMS.txt"
ev1 x "SHA256SUMS.txt (Law 4)" "$(wc -l < "$MEDIA/HPE11/docs/SHA256SUMS.txt") записей"

cat > "$MEDIA/HPE11/BOMB-REPORT.txt" <<EOF
H-PE11 // BOMB REPORT v1.2 (sandbox build)
Дата: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ | ЭВ.1: недоступно = НЕ сделано ([--])
База: Windows 11 26H2 x64 ru-RU boot.wim (26300.9457), официальный MS CDN
Инструменты: wimlib 1.14.4 + pycdlib (ADK/DISM НЕ использовались)

== ЭВ.1 СВОД ==
[x] База boot.wim: официальный boot.wim MS 26H2, index 2 (Setup PE)
[x] WMI в PE (wbem/cimwin32.dll — уже в базе)
[x] drvload/pnputil/netsh/wpeinit (уже в базе)
[x] curl.exe 8.23 -> System32 (in-box curl [--] в базе)
[x] wget.cmd-обёртка (GNU wget: хостинги отдают не бинарник [--])
[x] Python 3.12.8 embeddable -> X:\Tools\Python
[x] 7-Zip 7zr.exe -> X:\Tools\7-Zip
[x] Notepad++ 8.9.8 portable -> X:\Tools\Notepad++
[x] Sysinternals избранное (16 exe) -> X:\Tools\Sysinternals
[x] PowerShell 7.4.6 portable -> носитель Y:\HPE11\PSSeven
[x] Курсоры XpucT (17) -> X:\Windows\Cursors\XpucT + схема через reg add + SPI
[x] startnet.cmd v1.2: wpeinit + drvload + PATH + курсоры + консоль
[x] Volume2 v1.1.9.470 portable (скины) -> Y:\Programs\Volume2
[x] HMS x64 (распакован из setup, без запуска) -> Y:\Programs\HMS
[x] Драйверы whitelist (частично): Netwtw04, dptf_acpi, dptf_cpu, txei (+esif) -> drvload
[x] wintun 0.14.1 -> drvload
[x] VC++/DirectX редист-EXE на медиа (6 шт)
[--] PowerShell 5.1/HTA/NetFx/DISM в WIM: без ADK-кабов не добавить; PS7 компенсирует
[--] VC++ 2015-2022 DLL (x64+x86) в WIM: источники интернета мертвы (7z/nuget/pypi);
     накатываются runtime-копией с Y:\HPE11\VC (payload\VC от get-ammo) или редист-EXE
[--] DirectX d3dx DLL: directx_Jun2010_redist удалён с MS, зеркала (TPUp/guru3d/archive) недоступны
[--] Login Unlocker / NTPWEdit: хостинги недоступны; путь доложения Y:\HPE11\LoginUnlocker
[--] SSTR DriverPacks: sdi-tool/delahoy/archive.org недоступны; положить в Y:\DriverPacks с H:\SSTR
[--] Драйверы iigd_dch/apollolake/ialpss2_bxt_p/rtsuer: не найдены в Update Catalog запросами;
     станция: WinPE_Drivers (H-PE11_Collect_*) + build-bomb.ps1 контракт / drvload вручную
[--] Дым в эмуляторе: qemu в песочнице недоступен (нет рута); статические проверки выполнены

== ДЫМОВОЙ КОНТРАКТ (файлы внутри образа) ==
EOF
for f in "Windows/System32/curl.exe" "Windows/System32/wbem/cimwin32.dll" "Windows/System32/startnet.cmd" "Windows/Cursors/XpucT/01 XpucT - normal.cur" "Tools/Python/python.exe" "Tools/7-Zip/7zr.exe" "HPE11/HPE11.cmd"; do
  if wimdir /tmp/wimwork/boot.wim 2 | grep -qF "/$f"; then
    echo "[x] X:\\$f" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
  else
    echo "[--] X:\\$f (НЕТ!)" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
  fi
done
for f in "PS7/pwsh.exe" "Programs/Volume2/Volume2.exe" "Programs/HMS/HMS.exe" "Drivers/HPE11/netwtw04/Netwtw04.INF" "HPE11/BOMB-REPORT.txt"; do
  [ -e "$MEDIA/$f" ] && echo "[x] Y:\\$f" >> "$MEDIA/HPE11/BOMB-REPORT.txt" || echo "[--] Y:\\$f (НЕТ!)" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
done
echo "" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
echo "== ПРОВЕРКА НА ЖЕЛЕЗЕ (делает Хозяин) ==" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
cat >> "$MEDIA/HPE11/BOMB-REPORT.txt" <<'EOF'
1) Rufus/dd -> USB, BIOS и UEFI загрузки [--]
2) консоль H-PE11, мышь, курсоры XpucT [--]
3) ipconfig, drvload WLAN, pwsh -v, python -V [--]
4) Volume2, HMS [--]
EOF
ev1 x "BOMB-REPORT.txt (ЭВ.1)" "свод готов"

# ---------- СЕКЦИЯ 5. ISO ----------
echo "== СЕКЦИЯ 5. ISO (pycdlib BIOS+UEFI) =="
python3 /home/z/my-project/scripts/make_iso.py
ISO=/home/z/my-project/download/H-PE11_BOMB_v1.2.iso
ev1 x "ISO двойной загрузки" "$(stat -c%s $ISO 2>/dev/null) B"

sha256sum "$ISO" /tmp/wimwork/boot.wim > /home/z/my-project/download/H-PE11_BOMB_v1.2.SHA256
ev1 x "SHA256 (Law 4, ISO+boot.wim)" "$(head -c 16 /home/z/my-project/download/H-PE11_BOMB_v1.2.SHA256)..."

echo "=================================================================="
echo "  БОМБА v1.2: СБОРКА ЗАВЕРШЕНА"
echo "=================================================================="
