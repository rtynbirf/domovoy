@echo off
setlocal EnableDelayedExpansion
chcp 866 >nul
title PHX FIX 1.0

:: ================== PATHS ==================
set "REP="
if exist "%USERPROFILE%\Desktop\" set "REP=%USERPROFILE%\Desktop\PHX_FIX_LOG.TXT"
if not defined REP if exist "X:\Users\Public\Desktop\" set "REP=X:\Users\Public\Desktop\PHX_FIX_LOG.TXT"
if not defined REP if exist "X:\Users\Administrator\Desktop\" set "REP=X:\Users\Administrator\Desktop\PHX_FIX_LOG.TXT"
if not defined REP set "REP=%TEMP%\PHX_FIX_LOG.TXT"
set "DPW=%TEMP%\fx_cmd.txt"
set "DPO=%TEMP%\fx_out.txt"

> "%REP%" echo ==================================================
>>"%REP%" echo  PHOENIX-11 FIX BOOT  %date% %time%
>>"%REP%" echo  Diag pokazal: disk 0 MBR (465 Gb), proshivka UEFI,
>>"%REP%" echo  zagruzochnyh fajlov NET NI ODNOGO (BCD/bootmgr/ESP pusty).
>>"%REP%" echo  Windows na C: zhiva (hive OK, winload OK, 26100 Home 24H2).
>>"%REP%" echo ==================================================
>>"%REP%" echo.

echo(
echo  ==============================================
echo   PHOENIX-11 FIX BOOT v1.0
echo   Log: %REP%
echo  ==============================================
echo(
echo   Diag: MBR disk 0 + UEFI proshivka + NET zagruzchika.
echo   Plan: zalit zagruzchik na razdel 1 (G: FAT32 100 Mb),
echo   dobit fallback bootx64.efi, smenit tip razdela na EF.
echo   GPT-ne nuzhno, D: i F: ne torgaem.
echo(
choice /c YN /m "  Zacepinivaem? Y - da, N - vyhod"
if errorlevel 2 goto :aborted

call :say ""
call :say "[1] WINDOWS"
set "WINL="
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if /i not "%%L"=="X" if exist "%%L:\Windows\System32\config\SYSTEM" if not defined WINL set "WINL=%%L"
)
if not defined WINL (
  call :say "[SBOJ] Windows s bukvoj ne najden - nichego ne delaju."
  goto :aborted
)
call :say "  Windows na %WINL%: - ok"

call :say ""
call :say "[2] RAZDEL 1 DISKA 0 (kandidat zagruzochnogo, eto G: FAT32 100 Mb)"
> "%DPW%" echo select disk 0
>>"%DPW%" echo select part 1
>>"%DPW%" echo detail part
set "TRYASSIGN="
if not exist "S:\" (
  set "TRYASSIGN=1"
  >>"%DPW%" echo assign letter=S noerr
)
diskpart /s "%DPW%" > "%DPO%" 2>&1
call :dump "%DPO%"
set "TGT="
if defined TRYASSIGN if exist "S:\" set "TGT=S:"
if not defined TGT if exist "G:\" set "TGT=G:"
if not defined TGT if exist "S:\" set "TGT=S:"
if not defined TGT (
  call :say "[SBOJ] Ne dobilsya dostupa k razdelu 1 (ni S:, ni G:)."
  goto :aborted
)
call :say "  Cel zagruzki: %TGT%"
call :say "  Tekushchee soderzhimoe %TGT%:"
dir /a "%TGT%\" >>"%REP%" 2>&1

call :say ""
call :say "[3] PERESBORKA ZAGRUZCHIKA (bcdboot /f ALL = UEFI + BIOS vmeste)"
set "BB="
if exist "%WinDir%\System32\bcdboot.exe" set "BB=%WinDir%\System32\bcdboot.exe"
if not defined BB if exist "%WINL%:\Windows\System32\bcdboot.exe" set "BB=%WINL%:\Windows\System32\bcdboot.exe"
if not defined BB (
  call :say "[SBOJ] bcdboot.exe ne najden ni v PE, ni na %WINL%:."
  goto :aborted
)
call :say "  bcdboot: %BB%"
call :say "  Zalivayu s istochnika %WINL%:\Windows..."
"%BB%" "%WINL%:\Windows" /s %TGT% /f ALL /l ru-RU >>"%REP%" 2>&1
if errorlevel 1 (
  call :say "  /f ALL ne proshel (vozmozhno malo mesta), probuyu /f UEFI..."
  "%BB%" "%WINL%:\Windows" /s %TGT% /f UEFI /l ru-RU >>"%REP%" 2>&1
)
if errorlevel 1 (
  call :say "[SBOJ] bcdboot ne smog - smotri log vyshe."
  goto :aborted
)
if exist "%TGT%:\EFI\Microsoft\Boot\BCD" (
  call :say "  [OK] Fajly zagruzki zality, BCD sozdan."
) else (
  call :say "  [VNIMANIE] BCD ne vizno posle bcdboot - proveryu dalshe."
)

call :say ""
call :say "[4] FALLBACK bootx64.efi (chtoby boot-menu uvidelo disk bez NVRAM-zapisi)"
if exist "%TGT%:\EFI\Microsoft\Boot\bootmgfw.efi" (
  if not exist "%TGT%:\EFI\Boot\bootx64.efi" (
    mkdir "%TGT%:\EFI\Boot" >nul 2>&1
    copy /y "%TGT%:\EFI\Microsoft\Boot\bootmgfw.efi" "%TGT%:\EFI\Boot\bootx64.efi" >>"%REP%" 2>&1
  )
  if exist "%TGT%:\EFI\Boot\bootx64.efi" (call :say "  [OK] bootx64.efi na meste") else (call :say "  [NET] bootx64.efi ne skopirovalsya - ne kritichno")
) else (
  call :say "  [VNIMANIE] bootmgfw.efi ne najden - smotri log bcdboot."
)

call :say ""
call :say "[5] TIP RAZDELA 1 -> EF (choby proshivka schitala ego ESP)"
call :say "  Menyaetsya tolko bajt tipa v tablice MBR - dannye NE trogayutsya."
choice /c YN /m "  Menyat tip na EF? Y - da (rekomenduyu), N - net"
if errorlevel 2 goto :skip_ef
> "%DPW%" echo select disk 0
>>"%DPW%" echo select part 1
>>"%DPW%" echo set id=EF override
>>"%DPW%" echo detail part
diskpart /s "%DPW%" > "%DPO%" 2>&1
call :dump "%DPO%"
call :say "  [OK] Komanda vypolnena (tip smotri v detail vyshe)."
:skip_ef

call :say ""
call :say "[6] VERIFIKACIYA BCD"
set "BCDS=%TGT%:\EFI\Microsoft\Boot\BCD"
if not exist "%BCDS%" set "BCDS=%TGT%:\Boot\BCD"
if exist "%BCDS%" (
  call :say "  BCD: %BCDS%"
  bcdedit /store "%BCDS%" /enum all > "%TEMP%\fx_bcd.txt" 2>&1
  call :dump "%TEMP%\fx_bcd.txt"
  set "IDENT=0"
  set "OSDOK="
  for /f "delims=" %%A in ('type "%TEMP%\fx_bcd.txt"') do (
    set "LN=%%A"
    echo(!LN!|findstr /i /c:"identifier" >nul && set /a IDENT+=1
    echo(!LN!|findstr /i /c:"osdevice" >nul && echo(!LN!|findstr /i /c:"partition=%WINL%:" >nul && set "OSDOK=1"
  )
  call :say "  Zapisej (identifier) v BCD: %IDENT%"
  if defined OSDOK (call :say "  [OK] osdevice vedet na %WINL%: - BCD gotov k rabote") else (call :say "  [VNIMANIE] osdevice ne na %WINL%: - prishly log, razberu")
) else (
  call :say "[NET] BCD tak i ne poyavilsya - prishly log."
  goto :aborted
)

call :say ""
call :say "[7] REZULTAT"
call :say "  Zagruzchik: %TGT% (razdel 1 diska 0, tip EF)"
call :say "  BCD: %BCDS% (osdevice = %WINL%:)"
call :say "  TEPER: reboot, v boot-menu (F7/F12/Esc) vyberi etot disk"
call :say "  ili poyavivshijsya punkt Windows Boot Manager / UEFI: <tvoj disk>."
choice /c YN /m "  Reboot sejchas? Y - da, N - net"
if errorlevel 2 goto :noreboot
wpeutil reboot
goto :eof

:noreboot
call :say "  Reboot otlozhen. Zapusti sam: wpeutil reboot"
goto :fin

:aborted
call :say ""
call :say "VYPOLNENIE OSTANOVLINO - prichina vypisana vyshe."

:fin
call :say ""
call :say "[8] KOPII LOGA"
for %%D in ("%USERPROFILE%\Desktop" "X:\Users\Public\Desktop" "X:\Users\Administrator\Desktop") do (
  if exist "%%~D\" copy /y "%REP%" "%%~D\PHX_FIX_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: %%~D\PHX_FIX_LOG.TXT"
)
if defined WINL copy /y "%REP%" "%WINL%:\PHX_FIX_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: %WINL%:\PHX_FIX_LOG.TXT"
copy /y "%REP%" "%~dp0PHX_FIX_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: ryadom s batnikom"

echo(
echo  ==============================================
echo   Log sohranyon: %REP%
echo  ==============================================
echo(
pause
goto :eof

:: ================== SUBROUTINES ==================

:say
echo(%~1
>>"%REP%" echo(%~1
exit /b

:dump
if exist "%~1" (
  type "%~1"
  type "%~1">>"%REP%"
)
exit /b
