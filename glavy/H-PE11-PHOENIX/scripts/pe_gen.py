#!/usr/bin/env python3
# H-PE11 // Генератор PE-скриптов (CRLF, CP866 для русской консоли)
import os

OUT = "/home/z/my-project/build/hpe11v12/work/pe_scripts"
os.makedirs(OUT, exist_ok=True)

def wr(name, text, enc="ascii"):
    data = text.replace("\r\n", "\n").replace("\n", "\r\n").encode(enc)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(data)
    print(f"[x] {name} ({len(data)} B, {enc})")

# ================= STARTNET.CMD v1.2 (ASCII, в WIM) =================
CURSORS = [
    ("", "Inspired by Adobe (XpucT) - H-PE11"),
    ("AppStarting", "XpucT\\03 XpucT - working.ani"),
    ("Arrow", "XpucT\\01 XpucT - normal.cur"),
    ("Crosshair", "XpucT\\05 XpucT - precision.cur"),
    ("Hand", "XpucT\\15 XpucT - link.cur"),
    ("Help", "XpucT\\02 XpucT - help.cur"),
    ("IBeam", "XpucT\\06 XpucT - text.cur"),
    ("No", "XpucT\\08 XpucT - unavailable.cur"),
    ("NWPen", "XpucT\\07 XpucT - handwriting.cur"),
    ("SizeAll", "XpucT\\13 XpucT - move.cur"),
    ("SizeNESW", "XpucT\\12 XpucT - diagonal2.ani"),
    ("SizeNS", "XpucT\\09 XpucT - vertical.ani"),
    ("SizeNWSE", "XpucT\\11 XpucT - diagonal1.ani"),
    ("SizeWE", "XpucT\\10 XpucT - horizontal.ani"),
    ("UpArrow", "XpucT\\14 XpucT - alternate.cur"),
    ("Wait", "XpucT\\04 XpucT - busy.ani"),
    ("Pin", "XpucT\\16 XpucT - pin.cur"),
    ("Person", "XpucT\\17 XpucT - person.cur"),
]
reg_lines = []
for name, val in CURSORS:
    if name == "":
        reg_lines.append(f'reg add "HKCU\\Control Panel\\Cursors" /ve /d "{val}" /f >nul')
    else:
        reg_lines.append(f'reg add "HKCU\\Control Panel\\Cursors" /v {name} /d "{val}" /f >nul')
reg_lines.append('reg add "HKCU\\Control Panel\\Cursors" /v "Scheme Source" /t REG_DWORD /d 2 /f >nul')

startnet = f"""@echo off
rem === H-PE11 BOMB shell v1.2 // WinPE 11 26H2 x64 ===
rem Law: CHELOVEK=SISTEMA=CELOE | EV.1: nedostupno = NE sdelano
wpeinit

rem --- 1. Poisk nositelya H-PE11 (HPE11.tag) ---
set "HPE11DRV="
for %%i in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  if not defined HPE11DRV if exist "%%i:\\HPE11\\HPE11.tag" set "HPE11DRV=%%i:"
)
if not defined HPE11DRV (
  echo [!] HPE11.tag ne nayden na nositelyah. Payload H-PE11 nedostupen.
  goto shell
)
echo [x] H-PE11 media: %HPE11DRV%

rem --- 2. Whitelist-drayvery stancii (drvload runtime) ---
rem zamenyaet DISM /Add-Driver (bez ADK): iigd_dch [--] BasicDisplay;
rem netwtw04, dptf, txei, wintun - s nositelya:
for /R "%HPE11DRV%\\Drivers\\HPE11" %%f in (*.inf) do (
  drvload "%%f" >nul 2>&1
)
rem wintun (WireGuard tunnel):
if exist "%HPE11DRV%\\Drivers\\wintun\\wintun\\bin\\amd64\\wintun.inf" drvload "%HPE11DRV%\\Drivers\\wintun\\wintun\\bin\\amd64\\wintun.inf" >nul 2>&1

rem --- 3. PATH vsekh snaryadov ---
set "PATH=%PATH%;X:\\Tools\\Python;X:\\Tools\\wget;X:\\Tools\\7-Zip;X:\\Tools\\Sysinternals;X:\\Tools\\Notepad++;%HPE11DRV%\\PS7;%HPE11DRV%\\HPE11\\bin"

rem --- 3b. VC++ runtime s nositelya (payload\\VC ot get-ammo) ---
if exist "%HPE11DRV%\\HPE11\\VC\\msvcp140.dll" (
  copy /Y "%HPE11DRV%\\HPE11\\VC\\*.dll" X:\\Windows\\System32\\ >nul 2>&1
  echo [x] VC++ runtime DLL dolozheny v System32
)
if exist "%HPE11DRV%\\HPE11\\VC\\x86\\msvcp140.dll" (
  copy /Y "%HPE11DRV%\\HPE11\\VC\\x86\\*.dll" X:\\Windows\\SysWOW64\\ >nul 2>&1
)
if exist "%HPE11DRV%\\HPE11\\DirectX\\d3dx9_43.dll" (
  copy /Y "%HPE11DRV%\\HPE11\\DirectX\\*.dll" X:\\Windows\\System32\\ >nul 2>&1
  echo [x] DirectX d3dx DLL dolozheny
)

rem --- 4. Kursor XpucT (zhivaya shema cherez reg + SPI broadcast) ---
{"\r\n".join(reg_lines)}
if exist "%HPE11DRV%\\PS7\\pwsh.exe" (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "X:\\HPE11\\apply_cursors.ps1" >nul 2>&1
)

rem --- 5. DriverPacks (esli lozhen na nositel) ---
set "DPPATH="
if exist "%HPE11DRV%\\DriverPacks\\*.7z" set "DPPATH=%HPE11DRV%\\DriverPacks"
if defined DPPATH echo [x] DriverPacks: %DPPATH%

rem --- 6. Konsol H-PE11 ---
:shell
start "" cmd /c "if exist X:\\HPE11\\HPE11.cmd (X:\\HPE11\\HPE11.cmd) else (echo [--] X:\\HPE11\\HPE11.cmd net v obraze)"
rem HOLO shell hook (Gologramma):
rem start "" mshta X:\\HPE11\\holo.hta
cmd.exe
"""
wr("startnet.cmd", startnet)

# ================= apply_cursors.ps1 =================
wr("apply_cursors.ps1", """Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class HPE11User32{[DllImport("user32.dll")]public static extern bool SystemParametersInfo(uint uiAction,uint uiParam,uint pvParam,uint fWinIni);}'
[HPE11User32]::SystemParametersInfo(0x0057,0,0,3)
""", enc="utf-8")

# ================= wget.cmd (obertka nad curl.exe) =================
wr("wget.cmd", """@echo off
rem H-PE11 wget wrapper (GNU wget: hosting dead -> curl.exe in-box)
curl.exe -L %*
""")

# ================= HPE11.CMD (CP866, v WIM) =================
hpe11 = r"""@echo off
title H-PE11 BOMB v1.2 console
if not "%HPE11DRV%"=="" set "HPE11MEDIA=%HPE11DRV%"
chcp 866 >nul
color 0A
:menu
cls
echo ==============================================================
echo   H-PE11 BOMB v1.2  //  WinPE 11 26H2 x64  //  ..О..О..
echo   ..Ч..: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ   ЭВ.1: недоступно = НЕ сделано
echo ==============================================================
echo   Медиа: %HPE11MEDIA%   RAM: X:   DriverPacks: %DPPATH%
echo.
echo   [1] ЭВ.1 отчёт сборки
echo   [2] Volume2 - громкость и скины
echo   [3] Домашний медиа-сервер (UPnP, DLNA, HTTP)
echo   [4] Сеть: ipconfig / renew / netsh
echo   [5] Догрузить драйверы (drvload whitelist)
echo   [6] Python 3.12
echo   [7] PowerShell 7
echo   [8] Sysinternals
echo   [9] Notepad++
echo   [0] 7-Zip (7zr.exe)
echo   [L] Login Unlocker / сброс пароля (если доложен)
echo   [C] Выйти в cmd
echo.
set /p ch=  Выбор: 
if "%ch%"=="1" goto ev1
if "%ch%"=="2" goto v2
if "%ch%"=="3" goto hms
if "%ch%"=="4" goto net
if "%ch%"=="5" goto drv
if "%ch%"=="6" goto py
if "%ch%"=="7" goto ps7
if "%ch%"=="8" goto sin
if "%ch%"=="9" goto npp
if "%ch%"=="0" goto seven
if /i "%ch%"=="L" goto wlu
if /i "%ch%"=="C" goto out
goto menu
:ev1
if exist X:\HPE11\BOMB-REPORT.txt type X:\HPE11\BOMB-REPORT.txt
if not exist X:\HPE11\BOMB-REPORT.txt echo [--] BOMB-REPORT.txt не найден
echo.
pause
goto menu
:v2
if exist "%HPE11MEDIA%\Programs\Volume2\Volume2.exe" (
  start "" "%HPE11MEDIA%\Programs\Volume2\Volume2.exe"
) else echo [--] Volume2 не найден
goto menu
:hms
if exist "%HPE11MEDIA%\Programs\HMS\HMS.exe" (
  start "" "%HPE11MEDIA%\Programs\HMS\HMS.exe"
  echo [i] HMS запущен. Внимание: требует .NET 4.x [--] в этом PE
) else echo [--] HMS не найден
pause
goto menu
:net
ipconfig /all
echo.
echo renew...
ipconfig /renew >nul 2>&1
ipconfig | findstr /i "IPv4"
pause
goto menu
:drv
echo Догрузка whitelist-драйверов...
for /R "%HPE11MEDIA%\Drivers\HPE11" %%f in (*.inf) do drvload "%%f"
echo Готово.
pause
goto menu
:py
python --version 2>nul || set PATH=%PATH%;X:\Tools\Python
python
goto menu
:ps7
if exist "%HPE11MEDIA%\PS7\pwsh.exe" (
  "%HPE11MEDIA%\PS7\pwsh.exe" -NoLogo
) else echo [--] PS7 не найден
goto menu
:sin
echo Sysinternals: X:\Tools\Sysinternals
dir /b X:\Tools\Sysinternals\*.exe 2>nul
echo Запуск: procexp64, procmon64, autoruns64, tcpview64...
cmd
goto menu
:npp
if exist X:\Tools\Notepad++\notepad++.exe start "" X:\Tools\Notepad++\notepad++.exe
goto menu
:seven
7zr.exe
goto menu
:wlu
if exist "%HPE11MEDIA%\HPE11\LoginUnlocker\*.exe" (
  start /max "" explorer "%HPE11MEDIA%\HPE11\LoginUnlocker"
  echo Внимание: работа с SAM требует оффлайн-режима, используйте утилиты внутри.
) else (
  echo [--] Login Unlocker не включён в сборку (хостинги недоступны).
  echo     Положите его на флешку: \HPE11\LoginUnlocker\
)
pause
goto menu
:out
cmd
"""
wr("HPE11.cmd", hpe11, enc="cp866")

# ================= HPE11.tag (маркер носителя для startnet) =================
wr("HPE11.tag", """H-PE11 BOMB v1.2 // GOLOGRAMMA
Base: WinPE 11 26H2 x64 ru-RU (26300.9457) official MS boot.wim
""", enc="utf-8")

# ================= README_RU.txt =================
readme = """H-PE11 BOMB v1.2 // WinPE 11 26H2 x64 (26300.9457 ru-RU)
=============================================================
Закон проекта: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ. ЭВ.1: недоступно = НЕ сделано ([--]).
Режим: БОМБА — официальные матрицы поддержки не ограничивают интеграцию.

ЧТО ЭТО
  Оригинальная сборка WinPE 11 на базе официального boot.wim Microsoft
  (Windows 11 26H2 ru-RU, ISO собран в песочнице, без ADK/DISM:
  wimlib + pycdlib; стартовые записи BIOS+UEFI — подлинные файлы MS).

КАК ЗАГРУЗИТЬСЯ
  1) Rufus (GPT/UEFI или MBR/BIOS) -> записать H-PE11_BOMB_v1.2.iso на USB 4 ГБ+.
     Либо dd if=...iso of=/dev/sdX bs=4M status=progress.
  2) Загрузиться с USB (F7/F8/F11/Boot Menu).
  3) После wpeinit откроется консоль H-PE11 (меню). Мышь работает.

СОСТАВ
  В WIM (X:): curl.exe, VC++ runtime DLL, курсоры XpucT (схема активна
  с загрузки), X:\\Tools: Python 3.12, wget(обёртка curl), 7-Zip (7zr),
  Notepad++, Sysinternals, консоль H-PE11.
  На носителе (Y:\\HPE11): PowerShell 7.4.6 portable, отчёты ЭВ.1, SHA256SUMS.
  \\Programs\\Volume2 (v1.1.9.470, скины), \\Programs\\HMS (медиа-сервер).
  \\Drivers\\HPE11: whitelist драйверы станции (drvload при загрузке).
  \\DriverPacks: положите сюда паки SSTR (H:\\SSTR\\DriverPacks) — при
  наличии папки startnet объявит DPPATH.

ЭВ.1 ОГОВОРКИ (честно)
  -- PowerShell 5.1/HTA/NetFx/DISM в WIM НЕТ (без ADK их не добавить):
     компенсировано PowerShell 7 portable на носителе.
  -- HMS требует .NET 4.x [--]: размещён, но полноценный запуск ограничен.
  -- DirectX d3dx, Login Unlocker, SSTR DriverPacks, часть драйверов
     whitelist [--]: хостинги недоступны из песочницы; пути доложения в README.
  -- Драйверы грузятся через drvload (runtime), не через DISM /Add-Driver.

ПРОВЕРКИ НА ЖЕЛЕЗЕ (делает Хозяин)
  1) BIOS-загрузка USB;  2) UEFI-загрузка;
  3) мышь+клавиатура (USB/тачпад Apollo Lake);  4) сеть (ipconfig);
  5) WLAN (netwtw04 drvload);  6) Volume2;  7) pwsh -v;  8) python -V.

SHA256SUMS.txt — Law 4: рядом с ISO и в \\HPE11\\docs.
"""
wr("README_RU.txt", readme, enc="utf-8")

print("PE-скрипты готовы:", OUT)
