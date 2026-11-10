@echo off
setlocal EnableDelayedExpansion
chcp 866 >nul
title PHX DIAG 1.0

:: ================== PATHS ==================
set "REP="
if exist "%USERPROFILE%\Desktop\" set "REP=%USERPROFILE%\Desktop\PHX_DIAG.TXT"
if not defined REP if exist "X:\Users\Public\Desktop\" set "REP=X:\Users\Public\Desktop\PHX_DIAG.TXT"
if not defined REP if exist "X:\Users\Administrator\Desktop\" set "REP=X:\Users\Administrator\Desktop\PHX_DIAG.TXT"
if not defined REP set "REP=%TEMP%\PHX_DIAG.TXT"
set "DPW=%TEMP%\dx_cmd.txt"
set "DPO=%TEMP%\dx_list.txt"
set "DPO2=%TEMP%\dx_part.txt"
set "DPO3=%TEMP%\dx_det.txt"
set "BCE=%TEMP%\dx_bcd_uefi.txt"
set "BCE2=%TEMP%\dx_bcd_bios.txt"

> "%REP%" echo ==================================================
>>"%REP%" echo  PHOENIX-11 DIAGNOSTICS  %date% %time%
>>"%REP%" echo  Log po trebovaniyu: na rabochem stole.
>>"%REP%" echo ==================================================
>>"%REP%" echo.

echo(
echo  ==============================================
echo   PHOENIX-11 DIAG v1.0
echo   Sbor informacii. Log: %REP%
echo  ==============================================
echo(
echo   Zhdi, idet sbor (10-60 sek)...
echo(

call :say "[1] SREDA WINPE"
for /f "delims=" %%A in ('ver') do call :say "  %%A"
wpeutil UpdateBootInfo >nul 2>&1
set "FW=?"
for /f "tokens=3" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control" /v PEFirmwareType 2^>nul ^| findstr /i PEFirmwareType') do (
  if "%%A"=="0x1" set "FW=BIOS-Legacy"
  if "%%A"=="0x2" set "FW=UEFI"
)
reg query "HKLM\SYSTEM\CurrentControlSet\Control" /v PEFirmwareType >>"%REP%" 2>&1
call :say "  Rezhim zagruzki etogo PE (proshivka): %FW%"

call :say ""
call :say "[2] DISKI I TOMA (dump)"
> "%DPW%" echo list disk
>>"%DPW%" echo list vol
diskpart /s "%DPW%" > "%DPO%" 2>&1
call :dump "%DPO%"
set "GPT0="
for /f "delims=" %%A in ('type "%DPO%"') do (
  set "LN=%%A"
  echo(!LN!|findstr /c:"*" >nul && for /f "tokens=1,2" %%B in ("!LN!") do if "%%C"=="0" set "GPT0=1"
)
if defined GPT0 (call :say "  Disk 0: GPT") else (call :say "  Disk 0: MBR (ili net marki GPT)")

call :say ""
call :say "[3] POISK WINDOWS NA BUKVAH"
set "WINL="
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if /i not "%%L"=="X" if exist "%%L:\Windows\System32\config\SYSTEM" (
    call :say "  Najden Windows: disk %%L:"
    if not defined WINL set "WINL=%%L"
  )
)
if not defined WINL (
  call :say "  [NET] Windows ne najden ni na odnoj bukve."
  call :say "  (Vozmozhno razdel bez bukvy - smotri spisok tomov v dump.)"
)

call :say ""
call :say "[4] RAZDELY DISKA 0 (esli diskov neskolko - analiz po dumpu)"
> "%DPW%" echo select disk 0
>>"%DPW%" echo list part
diskpart /s "%DPW%" > "%DPO2%" 2>&1
call :dump "%DPO2%"
set "ACTP="
for /f "delims=" %%A in ('type "%DPO2%"') do (
  set "LN=%%A"
  echo(!LN!|findstr /c:"*" >nul && for /f "tokens=2" %%N in ("!LN!") do set "ACTP=%%N"
)
if defined ACTP (
  call :say "  Aktivnyj razdel na disk 0: nomer %ACTP%"
) else (
  call :say "  [NET] Aktivnyj razdel ne najden (dlya MBR-zagruzki eto kritichno)."
)

call :say ""
call :say "[5] POISK ESP (EFI System Partition, GUID c12a7328)"
set "ESPP="
set "ESPD="
for %%D in (0 1 2 3) do if not defined ESPP (
  > "%DPW%" echo select disk %%D
  >>"%DPW%" echo list part
  diskpart /s "%DPW%" > "%DPO2%" 2>&1
  for /f "delims=" %%A in ('type "%DPO2%"') do (
    set "LN=%%A"
    if not defined ESPP for /f "tokens=1,2" %%B in ("!LN!") do (
      echo %%C|findstr /r /c:"^[0-9][0-9]*$" >nul && call :chkesp %%D %%C
    )
  )
)
set "STOU="
if defined ESPP (
  call :say "  ESP najden: disk %ESPD%, razdel %ESPP%"
  > "%DPW%" echo select disk %ESPD%
  >>"%DPW%" echo select part %ESPP%
  >>"%DPW%" echo assign letter=S noerr
  diskpart /s "%DPW%" >nul 2>&1
  if exist "S:\" (
    if exist "S:\EFI\Microsoft\Boot\BCD" (
      set "STOU=S:\EFI\Microsoft\Boot\BCD"
      call :say "  [OK] BCD na ESP: %STOU%"
    ) else (
      call :say "  [NET] S:\EFI\Microsoft\Boot\BCD otsutstvuet"
    )
    if exist "S:\EFI\Microsoft\Boot\bootmgfw.efi" (call :say "  [OK] bootmgfw.efi est") else (call :say "  [NET] bootmgfw.efi otsutstvuet")
    if exist "S:\EFI\Boot\bootx64.efi" (call :say "  [OK] bootx64.efi (fallback) est") else (call :say "  [NET] bootx64.efi (fallback) otsutstvuet")
    call :say "  Listing kornya ESP:"
    dir /a "S:\" >>"%REP%" 2>&1
    if exist "S:\EFI" dir /a /b "S:\EFI" >>"%REP%" 2>&1
  ) else (
    call :say "  [VNIMANIE] Buku S: naznachit ne udalos - smotri dump tomov."
  )
) else (
  call :say "  [NET] ESP ne najden na diskah 0-3."
)

call :say ""
call :say "[6] BIOS-ZAGRUZKA: bootmgr I BCD na aktivnom"
set "STOB="
if defined ACTP (
  > "%DPW%" echo select disk 0
  >>"%DPW%" echo select part %ACTP%
  >>"%DPW%" echo detail part
  diskpart /s "%DPW%" > "%DPO3%" 2>&1
  call :dump "%DPO3%"
  > "%DPW%" echo select disk 0
  >>"%DPW%" echo select part %ACTP%
  >>"%DPW%" echo assign letter=T noerr
  diskpart /s "%DPW%" >nul 2>&1
)
if exist "T:\bootmgr" (call :say "  [OK] T:\bootmgr est") else (call :say "  [--] T:\bootmgr net (T: mozhet byt ne sistemnym)")
if exist "T:\Boot\BCD" (
  set "STOB=T:\Boot\BCD"
  call :say "  [OK] BCD: T:\Boot\BCD"
)
if defined WINL if exist "%WINL%:\Boot\BCD" (
  if not defined STOB set "STOB=%WINL%:\Boot\BCD"
  call :say "  [OK] BCD: %WINL%:\Boot\BCD"
)
if defined WINL if exist "%WINL%:\bootmgr" call :say "  [OK] bootmgr lezhit na %WINL%:\"

call :say ""
call :say "[7] HIVE I VERSIYA WINDOWS"
if defined WINL (
  reg load HKLM\PHX "%WINL%:\Windows\System32\config\SYSTEM" >nul 2>&1
  if errorlevel 1 (
    set "HIVEBAD=1"
    call :say "  [SBOJ] SYSTEM hive NE gruzitsya - veroyatno povrezhden."
  ) else (
    call :say "  [OK] SYSTEM hive chitaetsya."
    reg query "HKLM\PHX\Select" /v Current >>"%REP%" 2>&1
    reg query "HKLM\PHX\ControlSet001\Control" /v SystemStartOptions >>"%REP%" 2>&1
    reg unload HKLM\PHX >nul 2>&1
  )
  reg load HKLM\PHXS "%WINL%:\Windows\System32\config\SOFTWARE" >nul 2>&1
  if not errorlevel 1 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\PHXS\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul ^| findstr /i ProductName') do call :say "  ProductName: %%B"
    for /f "tokens=2*" %%A in ('reg query "HKLM\PHXS\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| findstr /i DisplayVersion') do call :say "  DisplayVersion: %%B"
    for /f "tokens=2*" %%A in ('reg query "HKLM\PHXS\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| findstr /i CurrentBuild') do call :say "  Build: %%B"
    for /f "tokens=2*" %%A in ('reg query "HKLM\PHXS\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr /i EditionID') do call :say "  Edition: %%B"
    reg unload HKLM\PHXS >nul 2>&1
  ) else (
    call :say "  [SBOJ] SOFTWARE hive ne gruzitsya."
  )
  if exist "%WINL%:\Windows\System32\winload.exe" (call :say "  [OK] winload.exe est") else (call :say "  [NET] winload.exe otsutstvuet")
  if exist "%WINL%:\Windows\System32\winload.efi" (call :say "  [OK] winload.efi est") else (call :say "  [NET] winload.efi otsutstvuet")
  if exist "%WINL%:\Windows\MEMORY.DMP" call :say "  [VNIMANIE] MEMORY.DMP est - proshlyj start padal v BSOD."
  call :say "  Listing kornya %WINL%:\ (iskat bootmgr, Boot, EFI):"
  dir /a "%WINL%:\" >>"%REP%" 2>&1
) else (
  call :say "  Propusk: Windows ne najden."
)

call :say ""
call :say "[8] ANALIZ BCD"
if defined STOU (
  call :say "  BCD UEFI: %STOU%"
  bcdedit /store "%STOU%" /enum all > "%BCE%" 2>&1
  call :dump "%BCE%"
)
if defined STOB (
  call :say "  BCD BIOS: %STOB%"
  bcdedit /store "%STOB%" /enum all > "%BCE2%" 2>&1
  call :dump "%BCE2%"
)
if not defined STOU if not defined STOB call :say "  [NET] BCD ne najden nigde."
set "PICK="
if "%FW%"=="UEFI" if defined STOU set "PICK=UEFI"
if "%FW%"=="BIOS-Legacy" if defined STOB set "PICK=BIOS"
if not defined PICK if defined STOU set "PICK=UEFI"
if not defined PICK if defined STOB set "PICK=BIOS"
if "%PICK%"=="UEFI" call :bcdparse "%BCE%" "UEFI"
if "%PICK%"=="BIOS" call :bcdparse "%BCE2%" "BIOS"

call :say ""
call :say "=================================================="
call :say "VERDIKT: CHTO MESHAET STARTU"
call :say "=================================================="
if not defined WINL (
  call :say "PRICHINA: Windows s bukvoj ne najden. Razdel bez bukvy, ili obraz leg ne na tot disk."
  call :say "DEJSTVIE: prishly mne etot otchet - po dumpu tomov najdem razdel i dam komandy."
  goto verdict_done
)
if defined HIVEBAD (
  call :say "PRICHINA: SYSTEM-hive na %WINL%: povrezhden - sistema ne startuet dazhe s zhivym BCD."
  call :say "SIMPTOM: 0xc000000e / 0xc000000f / INACCESSIBLE_BOOT_DEVICE."
  call :say "DEJSTVIE: esli %WINL%:\Windows\System32\config\RegBack\SYSTEM bolshe 1 MB - vosstanovit, inache pere-apply obraza."
  goto verdict_done
)
if "%FW%"=="UEFI" (
  if not defined ESPP (
    if defined GPT0 (
      call :say "PRICHINA: proshivka UEFI, disk 0 GPT, no ESP-razdela net - UEFI nechego gruzit."
      call :say "DEJSTVIE: prishly otchet - dam shagi sozdaniya ESP i bcdboot."
    ) else (
      call :say "PRICHINA: proshivka UEFI, a disk 0 - MBR. UEFI bez CSM s MBR ne sovmestim."
      call :say "DEJSTVIE: zagruzis v PE v Legacy-rezhime i stav zagruzchik pod BIOS, ili konvert disk v GPT."
    )
    goto verdict_done
  )
  if not defined STOU (
    call :say "PRICHINA: ESP est, no BCD na nem otsutstvuet - eto i est kartina 'vstavte disk'."
    call :say "LECHENIE: bcdboot %WINL%:\Windows /s S: /f UEFI"
    goto verdict_done
  )
  if "%IDENT%"=="0" (
    call :say "PRICHINA: BCD na ESP pust ili ne chitaetsya."
    call :say "LECHENIE: peresobrat: bcdboot %WINL%:\Windows /s S: /f UEFI"
    goto verdict_done
  )
  if not defined OSDOK (
    call :say "PRICHINA: BCD est, no osdevice ne ukazyvaet na %WINL%: - zagruzchik ishet Windows ne tam."
    call :say "LECHENIE: bcdboot %WINL%:\Windows /s S: /f UEFI"
    goto verdict_done
  )
  call :say "BOOT-FAJLY VYGLYADYAT ZHIVYMI: ESP est, BCD est, osdevice vedet na %WINL%:, winload v BCD est."
  call :say "DALEE: 1) V BOOT-menu (F12/F11/F8) vybrat IMENNO etot disk / Windows Boot Manager."
  call :say "2) V UEFI-nastroykah proverit prioritet diskov. 3) Esli opyat 'vstavte disk' - prishly otchet."
  goto verdict_done
)
if "%FW%"=="BIOS-Legacy" (
  if defined GPT0 (
    call :say "PRICHINA: PE gruzitsya v Legacy/BIOS, a disk 0 - GPT. BIOS s GPT ne gruzitsya."
    call :say "DEJSTVIE: zagruzis v PE v UEFI-rezhime i stav zagruzchik pod UEFI, ili konvert disk v MBR."
    goto verdict_done
  )
  if not defined ACTP (
    call :say "PRICHINA: MBR-disk, no ni odin razdel ne ACTIVE - BIOS ne vidit zagruzchika."
    call :say "LECHENIE: sdelat razdel aktivnym, potom bcdboot %WINL%:\Windows /s <bukva_aktivnogo>: /f BIOS."
    goto verdict_done
  )
  if not defined STOB (
    call :say "PRICHINA: aktivnyj razdel est, no bootmgr/Boot\BCD na nem net."
    call :say "LECHENIE: bcdboot %WINL%:\Windows /s <bukva_aktivnogo>: /f BIOS."
    goto verdict_done
  )
  if "%IDENT%"=="0" (
    call :say "PRICHINA: BCD pust ili ne chitaetsya."
    call :say "LECHENIE: bcdboot %WINL%:\Windows /s <bukva_aktivnogo>: /f BIOS."
    goto verdict_done
  )
  if not defined OSDOK (
    call :say "PRICHINA: BCD est, no osdevice ne ukazyvaet na %WINL%:."
    call :say "LECHENIE: bcdboot %WINL%:\Windows /s <bukva_aktivnogo>: /f BIOS."
    goto verdict_done
  )
  call :say "BOOT-FAJLY VYGLYADYAT ZHIVYMI: prover prioritet zagruzki v BIOS i vybor diska (F12)."
  goto verdict_done
)
call :say "Rezhim proshivki ne opredelilsya - prishly mne otchet, razberu vruchnuyu."
:verdict_done
call :say ""
call :say "Konec verdikta. Prishly fail otcheta tekstom - skazhu tochno i dam FIX-batnik."

call :say ""
call :say "[9] KOPII OTHETA"
for %%D in ("%USERPROFILE%\Desktop" "X:\Users\Public\Desktop" "X:\Users\Administrator\Desktop" "X:\Users\Default\Desktop") do (
  if exist "%%~D\" copy /y "%REP%" "%%~D\PHX_DIAG.TXT" >nul 2>&1 && call :say "  Kopiya: %%~D\PHX_DIAG.TXT"
)
if defined WINL copy /y "%REP%" "%WINL%:\PHX_DIAG.TXT" >nul 2>&1 && call :say "  Kopiya: %WINL%:\PHX_DIAG.TXT"
copy /y "%REP%" "%~dp0PHX_DIAG.TXT" >nul 2>&1 && call :say "  Kopiya: ryadom s batnikom"

echo(
echo  ==============================================
echo   GOTOVO. Otchet (log) zdes:
echo    %REP%
echo  ==============================================
echo(
echo   Prishly mne etot fail tekstom - skazhu tochnuyu prichinu.
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

:chkesp
if defined ESPP exit /b
> "%DPW%" echo select disk %~1
>>"%DPW%" echo select part %~2
>>"%DPW%" echo detail part
diskpart /s "%DPW%" > "%DPO3%" 2>&1
findstr /i "c12a7328" "%DPO3%" >nul 2>&1 && (
  set "ESPP=%~2"
  set "ESPD=%~1"
  type "%DPO3%" >>"%REP%"
)
exit /b

:bcdparse
set "IDENT=0"
set "OSDOK="
set "WLFOUND="
call :say "  Razbor BCD (%~2):"
for /f "delims=" %%A in ('type "%~1"') do (
  set "LN=%%A"
  echo(!LN!|findstr /i /c:"identifier" >nul && set /a IDENT+=1
  echo(!LN!|findstr /i /c:"osdevice" >nul && echo(!LN!|findstr /i /c:"partition=%WINL%:" >nul && set "OSDOK=1"
  echo(!LN!|findstr /i /c:"winload" >nul && set "WLFOUND=1"
)
call :say "  Zapisej (identifier) v BCD: %IDENT%"
if "%IDENT%"=="0" call :say "  [SBOJ] BCD pust ili ne chitaetsya."
if defined OSDOK (call :say "  [OK] osdevice ukazyvaet na %WINL%:") else (call :say "  [NET] osdevice NE ukazyvaet na %WINL%:")
if defined WLFOUND (call :say "  [OK] v BCD est winload-path") else (call :say "  [NET] v BCD net winload-path")
exit /b
