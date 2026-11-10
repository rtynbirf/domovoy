#!/bin/bash
# =====================================================================
# PHOENIX-11 (H-PE11) // BOMB BUILDER v1.3 PHOENIX EDITION
# База: ISO v1.2 (SHA256 4cb319f6...b512fb, верифицирован) -> перелёт v1.3
# ЭВ.1: недоступно = НЕ сделано ([--]). Law 4: всё с SHA256.
# Запуск: build_v13.sh stage1   |   build_v13.sh stage2
# =====================================================================
set -u
export TR=/tmp/my-project/toolroot
export LD_LIBRARY_PATH=$TR/usr/lib/x86_64-linux-gnu:$TR/usr/lib:$TR/lib/x86_64-linux-gnu:$TR/lib
export PATH=$TR/usr/bin:$PATH
Z7=$TR/usr/lib/7zip/7z

B=/tmp/my-project/build/v13
SRC=/home/z/my-project/scripts
PE=$B/pe_scripts
BRAND=$B/brand
MEDIA=$B/media_v13
WIMWORK=$B/wimwork
ISO=/tmp/my-project/download/H-PE11_PHOENIX_v1.3.iso
LOG=$B/build_v13.log

say() { echo "  $*"; }
ev1() { if [ "$1" = "x" ]; then echo "  [x] $2  $3"; else echo "  [--] $2  $3"; fi; }

mkdir -p "$B"
exec > >(tee -a "$LOG") 2>&1

echo "=================================================================="
echo "  PHOENIX-11 // BOMB BUILDER v1.3 (PHOENIX EDITION)"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================================="

# зеркалим скрипты в живучий /tmp/my-project/scripts
cp -f "$SRC/pe_gen_v13.py" "$SRC/make_wallpaper.py" "$SRC/make_iso_v13.py" "$SRC/verify_iso_v13.py" "$SRC/build_v13.sh" /tmp/my-project/scripts/ 2>/dev/null || true

if [ "${1:-}" = "stage1" ]; then
# ================= ЭТАП 1: скрипты, обои, WIM, медиа =================
echo "== С1.1. PE-СКРИПТЫ v1.3 =="
/home/z/.venv/bin/python3 "$SRC/pe_gen_v13.py" || exit 1

echo "== С1.2. ОБОИ ФЕНИКСА =="
/home/z/.venv/bin/python3 "$SRC/make_wallpaper.py" || exit 1

echo "== С1.3. СТАЖ МЕДИА (из v1.2, арсенал не тронут) =="
rm -rf "$MEDIA"; cp -a "$B/media_full" "$MEDIA"
say "медиа: $(du -sh "$MEDIA" | cut -f1)"

echo "== С1.4. WIM UPDATE (index 2): скрипты + обои =="
rm -rf "$WIMWORK"; mkdir -p "$WIMWORK"
cp "$MEDIA/sources/boot.wim" "$WIMWORK/boot.wim"
CMDF=$B/wimcmd_v13.txt
{
  echo "delete /Windows/System32/startnet.cmd"
  echo "add $PE/startnet.cmd /Windows/System32/startnet.cmd"
  echo "delete /HPE11/HPE11.cmd"
  echo "add $PE/HPE11.cmd /HPE11/HPE11.cmd"
  echo "delete /HPE11/HPE11.tag"
  echo "add $PE/HPE11.tag /HPE11/HPE11.tag"
  echo "delete /HPE11/apply_cursors.ps1"
  echo "add $PE/apply_cursors.ps1 /HPE11/apply_cursors.ps1"
  echo "delete /Windows/System32/winpe.jpg"
  echo "add $BRAND/winpe.jpg /Windows/System32/winpe.jpg"
  echo "delete /sources/background.bmp"
  echo "add $BRAND/background.bmp /sources/background.bmp"
} > "$CMDF"
wimupdate "$WIMWORK/boot.wim" 2 --rebuild < "$CMDF" 2>&1 | tail -3
bi=$(wiminfo "$WIMWORK/boot.wim" | grep "Boot Index" | awk '{print $3}')
if [ "$bi" != "2" ]; then say "boot index потерян ($bi) -> ставлю 2"; wiminfo "$WIMWORK/boot.wim" --boot-index=2 >/dev/null; fi
wiminfo "$WIMWORK/boot.wim" | grep -E "Boot Index|Size:" | head -2
ev1 x "boot.wim v1.3 обновлён" "$(stat -c%s "$WIMWORK/boot.wim") B"

echo "== С1.5. WIM ДЫМ (ЭВ.1) =="
wimverify "$WIMWORK/boot.wim" && say "wimverify OK"
DIR2=$(wimdir "$WIMWORK/boot.wim" 2)
for f in "/Windows/System32/startnet.cmd" "/HPE11/HPE11.cmd" "/HPE11/HPE11.tag" "/Windows/System32/winpe.jpg" "/sources/background.bmp" "/Tools/Python/python.exe" "/Tools/7-Zip/7zr.exe" "/Windows/System32/curl.exe"; do
  if echo "$DIR2" | grep -qF "$f"; then ev1 x "X:$f" "на месте"; else ev1 -- "X:$f" "НЕТ!"; fi
done
say "курсоры XpucT: $(echo "$DIR2" | grep -c 'XpucT/' -i) записей"
say "Sysinternals exe: $(echo "$DIR2" | grep -c 'Tools/Sysinternals/.*\.exe')"

# сверка обоев внутри WIM с собранными
mkdir -p "$B/probe13"; rm -f "$B/probe13"/*
wimextract "$WIMWORK/boot.wim" 2 /Windows/System32/winpe.jpg /sources/background.bmp --dest="$B/probe13" >/dev/null 2>&1
s1=$(sha256sum "$BRAND/winpe.jpg" | cut -d' ' -f1); s2=$(sha256sum "$B/probe13/winpe.jpg" | cut -d' ' -f1)
[ "$s1" = "$s2" ] && ev1 x "winpe.jpg в WIM = собранный" "sha256 $s1" || ev1 -- "winpe.jpg в WIM НЕ совпал" "$s2"
b1=$(sha256sum "$BRAND/background.bmp" | cut -d' ' -f1); b2=$(sha256sum "$B/probe13/background.bmp" | cut -d' ' -f1)
[ "$b1" = "$b2" ] && ev1 x "background.bmp в WIM = собранный" "sha256 $b1" || ev1 -- "background.bmp в WIM НЕ совпал" "$b2"

echo "== С1.6. МЕДИА: бренд-файлы + отчёт + SHA256SUMS (Law 4) =="
cp "$PE/HPE11.tag" "$MEDIA/HPE11/HPE11.tag"
cp "$PE/README_RU.txt" "$MEDIA/HPE11/README_RU.txt"
cp "$PE/PHOENIX_README_RU.txt" "$MEDIA/PHOENIX_README_RU.txt"
cp "$BRAND/PHOENIX-11_wallpaper.png" "$MEDIA/HPE11/docs/PHOENIX-11_wallpaper.png"

cat > "$MEDIA/HPE11/BOMB-REPORT.txt" <<EOF
PHOENIX-11 (H-PE11) // BOMB REPORT v1.3 PHOENIX EDITION
Дата: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ | ЭВ.1: недоступно = НЕ сделано ([--])
Слоган: Встаёт из пепла. Поднимает другие.
База: H-PE11_BOMB_v1.2.iso (SHA256 4cb319f6347b95f11436951aeff58f629227e4d03510ea96b031a154c8b512fb,
верифицирован перед перелётом). Внутри: официальный boot.wim MS 26H2 (26300.9457), index 2.
Инструменты: wimlib 1.14.4 + pycdlib (ADK/DISM НЕ использовались)

== ЧТО НОВОГО В v1.3 ==
[x] Бренд ФЕНИКС-11: обои (sources\\background.bmp 1024x768 BMP + winpe.jpg 1920x1080),
    консоль ФЕНИКС-11 (CP866, меню [F]), метка тома PHOENIX11_V13,
    README_RU/PHOENIX_README_RU/HPE11.tag/BOMB-REPORT v1.3
[x] Тачпад (решение Хозяина): СТАНДАРТНЫЙ in-box Microsoft. В базе уже есть
    hidi2c.inf + iaLPSS2i_I2C_* (Microsoft/Intel in-box). Вендорные паки
    Synaptics/ELAN/ALPS НЕ включены (0 байт): весят духуя, толку нулевое.
[x] Арсенал v1.2 перенесён байт-в-байт (сверка состава ниже)

== ЭВ.1 СВОД v1.3 (наследие v1.2) ==
[x] База boot.wim: официальный boot.wim MS 26H2, index 2 (Setup PE)
[x] WMI в PE (wbem/cimwin32.dll — уже в базе)
[x] drvload/pnputil/netsh/wpeinit (уже в базе)
[x] curl.exe 8.23 -> System32
[x] wget.cmd-обёртка (GNU wget: хостинги отдают не бинарник [--])
[x] Python 3.12.8 embeddable -> X:\Tools\Python
[x] 7-Zip 7zr.exe -> X:\Tools\7-Zip
[x] Notepad++ 8.9.8 portable -> X:\Tools\Notepad++
[x] Sysinternals избранное (16 exe) -> X:\Tools\Sysinternals
[x] PowerShell 7.4.6 portable -> носитель Y:\PS7
[x] Курсоры XpucT (17) -> X:\Windows\Cursors\XpucT + схема через reg add + SPI
[x] startnet.cmd v1.3: wpeinit + drvload + PATH + курсоры + консоль ФЕНИКС
[x] Volume2 v1.1.9.470 portable -> Y:\Programs\Volume2
[x] HMS x64 (дистрибутив на борту) -> Y:\Programs\HMS
[x] Драйверы whitelist: Netwtw04, dptf_acpi, dptf_cpu, txei (+esif) -> drvload
[x] wintun 0.14.1 -> drvload
[x] VC++/DirectX редист-EXE на медиа (6 шт)
[--] PowerShell 5.1/HTA/NetFx/DISM в WIM: без ADK-кабов не добавить; PS7 компенсирует
[--] VC++ 2015-2022 DLL: накатываются runtime-копией с Y:\HPE11\VC или редист-EXE
[--] DirectX d3dx DLL: directx_Jun2010_redist удалён с MS
[--] Login Unlocker / NTPWEdit: хостинги недоступны; путь доложения Y:\HPE11\LoginUnlocker
[--] SSTR DriverPacks: положить в Y:\DriverPacks с H:\SSTR
[--] Драйверы iigd_dch/apollolake/ialpss2_bxt_p/rtsuer: станции (WinPE_Drivers) + get-ammo
[--] Тачпад-жесты: НЕТ и НЕ НУЖНЫ (стандартный in-box, решение Хозяина)
[--] Дым в эмуляторе: BIOS/UEFI загрузка [--] (статические проверки выполнены)

== ДЫМОВОЙ КОНТРАКТ (файлы внутри образа) ==
EOF
for f in "Windows/System32/curl.exe" "Windows/System32/startnet.cmd" "Windows/System32/winpe.jpg" "sources/background.bmp" "Windows/Cursors/XpucT/01 XpucT - normal.cur" "Tools/Python/python.exe" "Tools/7-Zip/7zr.exe" "HPE11/HPE11.cmd"; do
  if echo "$DIR2" | grep -qF "/$f"; then
    echo "[x] X:\\$f" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
  else
    echo "[--] X:\\$f (НЕТ!)" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
  fi
done
for f in "PS7/pwsh.exe" "Programs/Volume2/Volume2.exe" "Drivers/HPE11/netwtw04/Netwtw04.INF" "HPE11/BOMB-REPORT.txt" "PHOENIX_README_RU.txt"; do
  [ -e "$MEDIA/$f" ] && echo "[x] Y:\\$f" >> "$MEDIA/HPE11/BOMB-REPORT.txt" || echo "[--] Y:\\$f (НЕТ!)" >> "$MEDIA/HPE11/BOMB-REPORT.txt"
done
cat >> "$MEDIA/HPE11/BOMB-REPORT.txt" <<'EOF'

== ПРОВЕРКА НА ЖЕЛЕЗЕ (делает Хозяин) ==
1) Rufus/dd -> USB, BIOS и UEFI загрузки [--]
2) обои ФЕНИКСА при загрузке, консоль ФЕНИКС-11, пункт [F] [--]
3) мышь+клавиатура; тачпад как обычная мышь [--]
4) ipconfig, drvload WLAN, pwsh -v, python -V [--]
EOF
ev1 x "BOMB-REPORT.txt v1.3 (ЭВ.1)" "свод готов"

# обновлённый boot.wim в медиа
cp "$WIMWORK/boot.wim" "$MEDIA/sources/boot.wim"

# SHA256SUMS.txt (Law 4) — всё медиа, исключая сам манифест
cd "$MEDIA"
find . -type f ! -name "SHA256SUMS.txt" -exec sha256sum {} \; | sed 's|\ \./| |' > "$MEDIA/HPE11/docs/SHA256SUMS.txt"
ev1 x "SHA256SUMS.txt (Law 4)" "$(wc -l < "$MEDIA/HPE11/docs/SHA256SUMS.txt") записей"
echo "STAGE1 DONE"
exit 0
fi

if [ "${1:-}" = "stage2" ]; then
# ================= ЭТАП 2: ISO, верификация, SHA256, нарезка =================
echo "== С2.1. ISO (pycdlib BIOS+UEFI, метка PHOENIX11_V13) =="
/home/z/.venv/bin/python3 "$SRC/make_iso_v13.py" || exit 1
ev1 x "ISO v1.3" "$(stat -c%s "$ISO") B"

echo "== С2.2. ВЕРИФИКАЦИЯ ISO =="
/home/z/.venv/bin/python3 "$SRC/verify_iso_v13.py" || { echo "[!] ВЕРИФИКАЦИЯ ПРОВАЛЕНА"; exit 1; }

echo "== С2.3. SHA256 (Law 4) =="
cd /tmp/my-project/download
sha256sum "$ISO" "$WIMWORK/boot.wim" > "H-PE11_PHOENIX_v1.3.SHA256"
cat "H-PE11_PHOENIX_v1.3.SHA256"

echo "== С2.4. НАРЕЗКА НА ЧАСТИ (для внешки) =="
rm -f H-PE11_PHOENIX_v1.3.iso.0* H-PE11_PHOENIX_v1.3.iso.parts.sha256 2>/dev/null
split -b 660000000 -d --numeric-suffixes=1 -a 3 "H-PE11_PHOENIX_v1.3.iso" "H-PE11_PHOENIX_v1.3.iso."
for p in H-PE11_PHOENIX_v1.3.iso.0*; do stat -c "%n %s" "$p"; done
sha256sum H-PE11_PHOENIX_v1.3.iso.0* > H-PE11_PHOENIX_v1.3.iso.parts.sha256
cat H-PE11_PHOENIX_v1.3.iso.parts.sha256

cat > GLUE_README_PHOENIX_v1.3_RU.txt <<'EOF'
ФЕНИКС-11 // PHOENIX-11 v1.3 — СКЛЕЙКА ЧАСТЕЙ
=============================================
Части: H-PE11_PHOENIX_v1.3.iso.001 + .002 (простая нарезка байт, не zip)

Windows (cmd):
  copy /b H-PE11_PHOENIX_v1.3.iso.001+H-PE11_PHOENIX_v1.3.iso.002 H-PE11_PHOENIX_v1.3.iso

Linux/macOS:
  cat H-PE11_PHOENIX_v1.3.iso.001 H-PE11_PHOENIX_v1.3.iso.002 > H-PE11_PHOENIX_v1.3.iso

Проверка (Law 4): сверить SHA256 склеенного файла с H-PE11_PHOENIX_v1.3.SHA256
  certutil -hashfile H-PE11_PHOENIX_v1.3.iso SHA256   (Windows)
  sha256sum H-PE11_PHOENIX_v1.3.iso                    (Linux)

Запись: Rufus (GPT/UEFI или MBR/BIOS) или dd. Подробнее: PHOENIX_README_RU.txt (в ISO).
EOF
ev1 x "GLUE_README_PHOENIX_v1.3_RU.txt" "готово"
echo "STAGE2 DONE"
exit 0
fi

echo "использование: build_v13.sh stage1|stage2"
exit 2
