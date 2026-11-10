@echo off
setlocal EnableDelayedExpansion
chcp 866 >nul
title PHX FIX 3.0

:: ================== PATHS ==================
set "REP="
if exist "%USERPROFILE%\Desktop\" set "REP=%USERPROFILE%\Desktop\PHX_FIX3_LOG.TXT"
if not defined REP if exist "X:\Users\Public\Desktop\" set "REP=X:\Users\Public\Desktop\PHX_FIX3_LOG.TXT"
if not defined REP if exist "X:\Users\Administrator\Desktop\" set "REP=X:\Users\Administrator\Desktop\PHX_FIX3_LOG.TXT"
if not defined REP set "REP=%TEMP%\PHX_FIX3_LOG.TXT"
set "DPW=%TEMP%\fx3_cmd.txt"
set "DPO=%TEMP%\fx3_out.txt"

> "%REP%" echo ==================================================
>>"%REP%" echo  PHOENIX-11 FIX BOOT v3.0  %date% %time%
>>"%REP%" echo  Sostoynanie: disk 0 uzhe GPT, razdel 1 = nastoyashchij ESP
>>"%REP%" echo  (tip c12a7328). Bukvy tomov sdeli mezhdu sessiyami PE:
>>"%REP%" echo  bcdboot zapisal zagruzchik na TOM WINDOWS - NTFS, a UEFI
>>"%REP%" echo  chitaet tolko ESP. Ot syuda 0xc0000001 / 0x98 pri starte.
>>"%REP%" echo  Plan v3: nayti ESP po TIPU razdela, ne po bukve; poluchit
>>"%REP%" echo  emy bukvu; bcdboot /f UEFI na ESP; fallback bootx64.efi;
>>"%REP%" echo  ruchnoy BCD esli bcdboot otkazhetsya; verifikaciya.
>>"%REP%" echo ==================================================
>>"%REP%" echo.

echo(
echo  ==============================================
echo   PHOENIX-11 FIX BOOT v3.0
echo   Log: %REP%
echo  ==============================================
echo(
echo   Diag: disk uzhe GPT, ESP est, no zagruzchik lezhit na
echo   NTFS-tome Windows - UEFI ego ne chitaet. Bukvy tomov
echo   posle konvertacii sdeli - poetomu Fix-3 ishet ESP
echo   po TIPU razdela, a ne po bukve.
echo   Plan: bukva ESP cherez diskpart, bcdboot /f UEFI na ESP,
echo   fallback bootx64.efi, ruchnoy BCD esli bcdboot zabezet.
echo(
choice /c YN /m "  Zacepinivaem? Y - da, N - vyhod"
if errorlevel 2 goto :aborted

call :say ""
call :say "[1] WINDOWS I INSTRUMENTY"
set "WINL="
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if /i not "%%L"=="X" if exist "%%L:\Windows\System32\config\SYSTEM" if not defined WINL set "WINL=%%L"
)
if not defined WINL (
  call :say "[SBOJ] Windows s bukvoj ne najden - nichego ne delaju."
  goto :aborted
)
call :say "  Windows na %WINL%: - ok"
if exist "%WINL%:\Windows\Boot\EFI\bootmgfw.efi" (call :say "  [OK] %WINL%:\Windows\Boot\EFI\bootmgfw.efi") else (call :say "  [--] %WINL%:\Windows\Boot\EFI\bootmgfw.efi NET")
if exist "%WINL%:\Windows\System32\Boot\winload.efi" (call :say "  [OK] %WINL%:\Windows\System32\Boot\winload.efi") else (call :say "  [--] %WINL%:\Windows\System32\Boot\winload.efi NET")
set "BB="
if exist "%WinDir%\System32\bcdboot.exe" set "BB=%WinDir%\System32\bcdboot.exe"
if not defined BB if exist "%WINL%:\Windows\System32\bcdboot.exe" set "BB=%WINL%:\Windows\System32\bcdboot.exe"
if defined BB (call :say "  [OK] bcdboot: %BB%") else (call :say "  [--] bcdboot ne najden")
set "BCE="
if exist "%WinDir%\System32\bcdedit.exe" set "BCE=%WinDir%\System32\bcdedit.exe"
if not defined BCE if exist "%WINL%:\Windows\System32\bcdedit.exe" set "BCE=%WINL%:\Windows\System32\bcdedit.exe"
if defined BCE (call :say "  [OK] bcdedit: %BCE%") else (call :say "  [--] bcdedit ne najden")

call :say ""
call :say "[2] POISK ESP PO TIPU c12a7328 (disk 0)"
set "ESPPART="
for %%N in (1 2 3 4 5 6 7) do (
  if not defined ESPPART (
    > "%DPW%" echo select disk 0
    >>"%DPW%" echo select part %%N
    >>"%DPW%" echo detail part
    diskpart /s "%DPW%" > "%TEMP%\fx3_dp_%%N.txt" 2>&1
    findstr /i "c12a7328" "%TEMP%\fx3_dp_%%N.txt" >nul 2>&1 && set "ESPPART=%%N"
  )
)
if not defined ESPPART (
  call :say "[SBOJ] Razdel tipa c12a7328 na diske 0 ne najden."
  call :say "       Esli disk eshe MBR - GPT-konvertaciya ne delana."
  goto :aborted
)
call :say "  [OK] ESP = razdel !ESPPART! diska 0 - detail:"
call :dump "%TEMP%\fx3_dp_!ESPPART!.txt"

call :say ""
call :say "[3] BUKVA DLYA ESP"
set "ESPL="
if not exist "W:\" (
  > "%DPW%" echo select disk 0
  >>"%DPW%" echo select part !ESPPART!
  >>"%DPW%" echo assign letter=W noerr
  diskpart /s "%DPW%" > "%DPO%" 2>&1
  call :dump "%DPO%"
  if exist "W:\" set "ESPL=W:"
)
if defined ESPL goto :espl_ok
call :say "  W: ne poluchilsya - probuyu drugie svobodnye bukvy..."
for %%C in (Y U V Q R S T E) do (
  if not defined ESPL if not exist "%%C:\" (
    > "%DPW%" echo select disk 0
    >>"%DPW%" echo select part !ESPPART!
    >>"%DPW%" echo assign letter=%%C noerr
    diskpart /s "%DPW%" > "%DPO%" 2>&1
    if exist "%%C:\" set "ESPL=%%C:"
  )
)
if not defined ESPL (
  call :say "  [--] Bukvu ESP ne dal - bcdboot budet iskat ESP sam."
  goto :espl_done
)
:espl_ok
call :say "  [OK] ESP tom: %ESPL%"
call :say "  Tekushchee soderzhimoe ESP - v log:"
dir /a "%ESPL%\" >>"%REP%" 2>&1
:espl_done

call :say ""
call :say "[4] BCDBOOT NA ESP"
if not defined BB (
  call :say "[SBOJ] bcdboot net - ruchnaya sborka nevozmozhna."
  goto :aborted
)
if defined ESPL goto :bb_s
call :say "  Zapus A: bcdboot %WINL%:\Windows /f UEFI /v - sam najdet ESP"
"%BB%" "%WINL%:\Windows" /f UEFI /v > "%DPO%" 2>&1
call :say "  Kod vyhoda: %errorlevel%"
call :dump "%DPO%"
goto :bb_check
:bb_s
call :say "  Zapus A: bcdboot %WINL%:\Windows /s %ESPL% /f UEFI /v"
"%BB%" "%WINL%:\Windows" /s %ESPL% /f UEFI /v > "%DPO%" 2>&1
call :say "  Kod vyhoda: %errorlevel%"
call :dump "%DPO%"
call :chk_esp
if defined ESPBCD goto :bb_check
call :say "  Zapus B: bcdboot /f ALL - esli UEFI-chast ne vstala"
"%BB%" "%WINL%:\Windows" /s %ESPL% /f ALL /v > "%DPO%" 2>&1
call :say "  Kod vyhoda: %errorlevel%"
call :dump "%DPO%"
:bb_check
call :chk_esp
if defined ESPBCD goto :files_topup
if defined ESPL goto :manual_esp
call :say "  Ishem tom, kuda bcdboot chto-to polozhil..."
set "BCDFND="
for %%L in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if /i not "%%L"=="X" if /i not "%%L"=="%WINL%" if not defined BCDFND if exist "%%L:\EFI\Microsoft\Boot\BCD" set "BCDFND=%%L:"
)
if defined BCDFND (
  call :say "  [OK] Novyj BCD najden na tome %BCDFND% - eto i est ESP"
  set "ESPL=%BCDFND%"
  call :chk_esp
  goto :files_topup
)
call :say "  [--] BCD ne najden ni na odnom tome - bez bukvy ESP ruchnaya sborka nelzya."
goto :verify
:files_topup
if defined ESPMGFW goto :x64_check
mkdir "%ESPL%\EFI\Microsoft\Boot" >nul 2>&1
copy /y "%WINL%:\Windows\Boot\EFI\bootmgfw.efi" "%ESPL%\EFI\Microsoft\Boot\bootmgfw.efi" >nul 2>&1
:x64_check
if defined ESPX64 goto :esp_files_ok
mkdir "%ESPL%\EFI\Boot" >nul 2>&1
copy /y "%WINL%:\Windows\Boot\EFI\bootmgfw.efi" "%ESPL%\EFI\Boot\bootx64.efi" >nul 2>&1
:esp_files_ok
call :chk_esp
if defined ESPBCD (call :say "  [OK] BCD na ESP: %ESPL%\EFI\Microsoft\Boot\BCD") else (call :say "  [NET] BCD na ESP net")
if defined ESPX64 (call :say "  [OK] fallback: %ESPL%\EFI\Boot\bootx64.efi") else (call :say "  [NET] fallback bootx64.efi net")
if defined ESPBCD goto :verify
:manual_esp
call :say "  Ruchnaya sborka BCD na ESP cherez bcdedit:"
if not defined BCE (
  call :say "[SBOJ] bcdedit net - ruchnaya sborka nevozmozhna."
  goto :aborted
)
set "BUE=%ESPL%\EFI\Microsoft\Boot\BCD"
"%BCE%" /createstore "%BUE%" > "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /create {bootmgr} /d "Windows Boot Manager" >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set {bootmgr} device partition=%ESPL% >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /timeout 10 >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /create /application osloader /d "Windows 11" > "%TEMP%\fx3_guid.txt" 2>&1
set "GUID="
for /f "tokens=2 delims={}" %%A in ('findstr "{" "%TEMP%\fx3_guid.txt"') do if not "%%A"=="" set "GUID={%%A}"
if defined GUID if "%GUID:~0,1%"=="{" goto :guid_ok
call :say "  [SBOJ] bcdedit ne sozdal osloader - vyvod:"
call :dump "%TEMP%\fx3_guid.txt"
call :dump "%DPO%"
goto :aborted
:guid_ok
call :say "  Osloader: %GUID%"
"%BCE%" /store "%BUE%" /set %GUID% device partition=%WINL%: >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set %GUID% osdevice partition=%WINL%: >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set %GUID% path \Windows\system32\winload.efi >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set %GUID% systemroot \Windows >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set {bootmgr} default %GUID% >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set {bootmgr} displayorder %GUID% >> "%DPO%" 2>&1
call :dump "%DPO%"

call :say ""
call :say "[5] VERIFIKACIYA"
:verify
call :chk_esp
if defined ESPBCD (call :say "  [OK] Fajly UEFI na ESP") else (call :say "  [NET] Fajly UEFI na ESP net - prishly log")
if not defined ESPBCD goto :no_enum
if not defined BCE set "BCE=bcdedit"
"%BCE%" /store "%ESPL%\EFI\Microsoft\Boot\BCD" /enum all > "%TEMP%\fx3_bcd.txt" 2>&1
call :dump "%TEMP%\fx3_bcd.txt"
set "IDENT=0"
set "WLEFI="
set "OSD="
for /f "delims=" %%A in ('type "%TEMP%\fx3_bcd.txt"') do (
  set "LN=%%A"
  echo(!LN!|findstr /c:"{" >nul && set /a IDENT+=1
  echo(!LN!|findstr /i /c:"winload" >nul && set "WLEFI=1"
  echo(!LN!|findstr /i /c:"osdevice" >nul && set "OSD=1"
)
call :say "  Zapisej s figurymi skobkami v BCD: !IDENT!"
if defined WLEFI (call :say "  [OK] winload v BCD est") else (call :say "  [NET] winload v BCD NET")
if defined OSD (call :say "  [OK] osdevice v BCD est") else (call :say "  [NET] osdevice v BCD NET")
goto :verdict
:no_enum
call :say "  [--] Enum BCD propuschen - net dostupa k ESP"
:verdict

call :say ""
call :say "=================================================="
call :say " VERDIKT"
call :say "=================================================="
call :chk_esp
if defined ESPBCD (call :say "  ESP: zagruzchik UEFI sobran - %ESPL%\EFI\Microsoft\Boot\BCD") else (call :say "  ESP: NE SOBRALSYA - prishly log")
call :say "  Starye fajly na tome Windows: %WINL%:\EFI, %WINL%:\Boot, %WINL%:\bootmgr -"
call :say "  mozhno ne torgat: GPT-disk po BIOS vse ravno ne gruzitsya."
call :say "  CHto delat:"
call :say "   1. Reboot - predlozhu srazu posle sohraneniya loga."
call :say "   2. V boot-menu: punkt Windows Boot Manager ili UEFI: disk 0."
call :say "   3. Dolzhen poyavitsya menedzher zagruzki s punktom Windows 11."
call :say "   4. Esli snova 0xc0000001 - prishly PHX_FIX3_LOG.TXT tekstom."
choice /c YN /m "  Reboot sejchas? Y - da, N - snachala log"
if errorlevel 2 goto :noreboot
wpeutil reboot
goto :eof

:noreboot
call :say "  Reboot otlozhen: zapusti sam - wpeutil reboot"

:fin
call :say ""
call :say "[6] KOPII LOGA"
for %%D in ("%USERPROFILE%\Desktop" "X:\Users\Public\Desktop" "X:\Users\Administrator\Desktop") do (
  if exist "%%~D\" copy /y "%REP%" "%%~D\PHX_FIX3_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: %%~D\PHX_FIX3_LOG.TXT"
)
if defined WINL copy /y "%REP%" "%WINL%:\PHX_FIX3_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: %WINL%:\PHX_FIX3_LOG.TXT"
copy /y "%REP%" "%~dp0PHX_FIX3_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: ryadom s batnikom"

echo(
echo  ==============================================
echo   Log sohranyon: %REP%
echo  ==============================================
echo(
pause
goto :eof

:aborted
call :say ""
call :say "VYPOLNENIE OSTANOVLINO - prichina vypisana vyshe."
goto :fin

:: ================== SUBROUTINES ==================

:chk_esp
set "ESPBCD="
set "ESPMGFW="
set "ESPX64="
if not defined ESPL exit /b
if exist "%ESPL%\EFI\Microsoft\Boot\BCD" set "ESPBCD=1"
if exist "%ESPL%\EFI\Microsoft\Boot\bootmgfw.efi" set "ESPMGFW=1"
if exist "%ESPL%\EFI\Boot\bootx64.efi" set "ESPX64=1"
exit /b

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
