@echo off
setlocal EnableDelayedExpansion
chcp 866 >nul
title PHX FIX 2.0

:: ================== PATHS ==================
set "REP="
if exist "%USERPROFILE%\Desktop\" set "REP=%USERPROFILE%\Desktop\PHX_FIX2_LOG.TXT"
if not defined REP if exist "X:\Users\Public\Desktop\" set "REP=X:\Users\Public\Desktop\PHX_FIX2_LOG.TXT"
if not defined REP if exist "X:\Users\Administrator\Desktop\" set "REP=X:\Users\Administrator\Desktop\PHX_FIX2_LOG.TXT"
if not defined REP set "REP=%TEMP%\PHX_FIX2_LOG.TXT"
set "DPW=%TEMP%\fx2_cmd.txt"
set "DPO=%TEMP%\fx2_out.txt"

> "%REP%" echo ==================================================
>>"%REP%" echo  PHOENIX-11 FIX BOOT v2.0  %date% %time%
>>"%REP%" echo  Fix-1 itog: bcdboot ushel s kodom 0, no ni BCD, ni bootmgfw
>>"%REP%" echo  na G: tak i ne poyavilis. Razdel 1 uzhe tipa EF - eto ESP
>>"%REP%" echo  na MBR, GPT ne nuzhen. Plan v2: vidnyj vyvod bcdboot,
>>"%REP%" echo  rekon istochnikov, ruchnaya sborka bootmgfw + BCD cherez
>>"%REP%" echo  bcdedit, plyus BIOS-zapas dlya Plan B.
>>"%REP%" echo ==================================================
>>"%REP%" echo.

echo(
echo  ==============================================
echo   PHOENIX-11 FIX BOOT v2.0
echo   Log: %REP%
echo  ==============================================
echo(
echo   Fix-1: bcdboot molcha ne polozhil fajly na G:.
echo   Plan v2: vyvod bcdboot vidno v konsoli i v log.
echo   Esli bcdboot snova otkazhetsya - sobirayu zagruzchik
echo   VRUCHNUYU: bootmgfw.efi s diska + BCD cherez bcdedit.
echo   Plyus BIOS-zapas: bootmgr + BCD + active + MBR-kod.
echo   Razdel 1 uzhe tipa EF. D: i F: ne torgaem.
echo(
choice /c YN /m "  Zacepinivaem? Y - da, N - vyhod"
if errorlevel 2 goto :aborted

call :say ""
call :say "[1] WINDOWS I ISTOCHNIKI FAJLOV ZAGRUZCHIKA"
set "WINL="
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if /i not "%%L"=="X" if exist "%%L:\Windows\System32\config\SYSTEM" if not defined WINL set "WINL=%%L"
)
if not defined WINL (
  call :say "[SBOJ] Windows s bukvoj ne najden - nichego ne delaju."
  goto :aborted
)
call :say "  Windows na %WINL%: - ok"
if exist "%WINL%:\Windows\System32\Boot\winload.efi" (call :say "  [OK] %WINL%:\Windows\System32\Boot\winload.efi") else (call :say "  [--] %WINL%:\Windows\System32\Boot\winload.efi NET")
if exist "%WINL%:\Windows\System32\Boot\winload.exe" (call :say "  [OK] %WINL%:\Windows\System32\Boot\winload.exe") else (call :say "  [--] %WINL%:\Windows\System32\Boot\winload.exe NET")
if exist "%WINL%:\Windows\Boot\EFI\bootmgfw.efi" (call :say "  [OK] %WINL%:\Windows\Boot\EFI\bootmgfw.efi") else (call :say "  [--] %WINL%:\Windows\Boot\EFI\bootmgfw.efi NET")
if exist "%WINL%:\Windows\Boot\PCAT\bootmgr" (call :say "  [OK] %WINL%:\Windows\Boot\PCAT\bootmgr") else (call :say "  [--] %WINL%:\Windows\Boot\PCAT\bootmgr NET")
if exist "%WINL%:\Windows\System32\Config\BCD-Template" (call :say "  [OK] BCD-Template na %WINL%:") else (call :say "  [--] BCD-Template na %WINL%: NET")
if exist "%WinDir%\Boot\EFI\bootmgfw.efi" (call :say "  [OK] v PE: %WinDir%\Boot\EFI\bootmgfw.efi") else (call :say "  [--] v PE net %WinDir%\Boot\EFI\bootmgfw.efi")
if exist "J:\EFI\Boot\bootx64.efi" (call :say "  [OK] J:\EFI\Boot\bootx64.efi - s ISO") else (call :say "  [--] J:\EFI\Boot\bootx64.efi NET")
call :say "  Instrumenty:"
set "BCE="
if exist "%WinDir%\System32\bcdedit.exe" set "BCE=%WinDir%\System32\bcdedit.exe"
if not defined BCE if exist "%WINL%:\Windows\System32\bcdedit.exe" set "BCE=%WINL%:\Windows\System32\bcdedit.exe"
if defined BCE (call :say "  [OK] bcdedit: %BCE%") else (call :say "  [--] bcdedit ne najden")
set "BB="
if exist "%WinDir%\System32\bcdboot.exe" set "BB=%WinDir%\System32\bcdboot.exe"
if not defined BB if exist "%WINL%:\Windows\System32\bcdboot.exe" set "BB=%WINL%:\Windows\System32\bcdboot.exe"
if defined BB (call :say "  [OK] bcdboot: %BB%") else (call :say "  [--] bcdboot ne najden")
set "BSX="
if exist "%WinDir%\System32\bootsect.exe" set "BSX=%WinDir%\System32\bootsect.exe"
if defined BSX (call :say "  [OK] bootsect: %BSX%") else (call :say "  [--] bootsect net - MBR-kod ostalsya kak byl")
if exist "%WINL%:\Windows\Boot" (
  >>"%REP%" echo --- dir %WINL%:\Windows\Boot ---
  dir /b "%WINL%:\Windows\Boot" >>"%REP%" 2>&1
  if exist "%WINL%:\Windows\Boot\EFI" dir /b "%WINL%:\Windows\Boot\EFI" >>"%REP%" 2>&1
  if exist "%WINL%:\Windows\Boot\PCAT" dir /b "%WINL%:\Windows\Boot\PCAT" >>"%REP%" 2>&1
  call :say "  Listing %WINL%:\Windows\Boot - smotri log."
)
if defined BB dir "%BB%" >>"%REP%" 2>&1
if exist "%WinDir%\Boot" (
  >>"%REP%" echo --- dir %WinDir%\Boot ---
  dir /b /s "%WinDir%\Boot" >>"%REP%" 2>&1
)

call :say ""
call :say "[2] CEL: RAZDEL 1 DISKA 0 - TOM G:"
if not exist "G:\" (
  call :say "[SBOJ] Toma G: net - smotri diag. Nichego ne delaju."
  goto :aborted
)
> "G:\phx2_wr.tmp" echo test
if exist "G:\phx2_wr.tmp" goto :wr_ok
call :say "  Zapisi net - probuyu snyat readonly s toma G: ..."
> "%DPW%" echo select volume G
>>"%DPW%" echo attributes volume clear readonly
diskpart /s "%DPW%" > "%DPO%" 2>&1
call :dump "%DPO%"
> "G:\phx2_wr.tmp" echo test
if exist "G:\phx2_wr.tmp" goto :wr_ok
call :say "[SBOJ] Zapis na G: ne rabotaet dazhe posle readonly-clear. Prishly log."
goto :aborted
:wr_ok
del /f /q "G:\phx2_wr.tmp" >nul 2>&1
call :say "  [OK] G: dostupen, zapis rabotaet."
> "%DPW%" echo select disk 0
>>"%DPW%" echo select part 1
>>"%DPW%" echo detail part
diskpart /s "%DPW%" > "%DPO%" 2>&1
call :dump "%DPO%"
call :say "  Tekushchee soderzhimoe G: - smotri log:"
dir /a "G:\" >>"%REP%" 2>&1

call :say ""
call :say "[3] BCDBOOT - POPYTKI S VIDNYM VYVODOM"
if not defined BB (
  call :say "  [--] bcdboot net - srazu v ruchnuyu sborku [4]."
  goto :manual
)
call :chkuefi
if defined UEOK (
  call :say "  [OK] Fajly UEFI uzhe na meste - bcdboot propuskayu."
  goto :bios_stage
)
call :say "  Zapus 1: bcdboot %WINL%:\Windows /s G: /f ALL /v"
"%BB%" "%WINL%:\Windows" /s G: /f ALL /v > "%DPO%" 2>&1
call :say "  Kod vyhoda: %errorlevel%"
call :dump "%DPO%"
call :chkuefi
if defined UEOK goto :ok1
call :say "  Zapus 1 fajlov UEFI ne dal."
call :say "  Zapus 2: bcdboot /f UEFI - tolko UEFI-chast"
"%BB%" "%WINL%:\Windows" /s G: /f UEFI /v > "%DPO%" 2>&1
call :say "  Kod vyhoda: %errorlevel%"
call :dump "%DPO%"
call :chkuefi
if defined UEOK goto :ok2
call :say "  Zapus 2 fajlov UEFI ne dal."
if "%BB%"=="%WINL%:\Windows\System32\bcdboot.exe" goto :bb_done
if not exist "%WINL%:\Windows\System32\bcdboot.exe" goto :bb_done
call :say "  Zapus 3: bcdboot s %WINL%: - versiya samoj Windows"
"%WINL%:\Windows\System32\bcdboot.exe" "%WINL%:\Windows" /s G: /f ALL /v > "%DPO%" 2>&1
call :say "  Kod vyhoda: %errorlevel%"
call :dump "%DPO%"
call :chkuefi
if defined UEOK goto :ok3
call :say "  Zapus 3 fajlov UEFI ne dal."
:bb_done
call :say "  [VNIMANIE] bcdboot tak i ne polozhil fajly - ruchnaya sborka."
goto :manual
:ok1
call :say "  [OK] Zapus 1 dal fajly UEFI."
goto :bios_stage
:ok2
call :say "  [OK] Zapus 2 dal fajly UEFI."
goto :bios_stage
:ok3
call :say "  [OK] Zapus 3 dal fajly UEFI."
goto :bios_stage

:manual
call :say ""
call :say "[4] RUCHNAYA SBORKA ZAGRUZCHIKA UEFI"
set "SRCB="
if exist "%WINL%:\Windows\Boot\EFI\bootmgfw.efi" set "SRCB=%WINL%:\Windows\Boot\EFI\bootmgfw.efi"
if not defined SRCB if exist "%WinDir%\Boot\EFI\bootmgfw.efi" set "SRCB=%WinDir%\Boot\EFI\bootmgfw.efi"
if not defined SRCB if exist "J:\EFI\Boot\bootx64.efi" set "SRCB=J:\EFI\Boot\bootx64.efi"
if defined SRCB goto :src_ok
call :say "[SBOJ] bootmgfw.efi ne najden nigda: ni na diske, ni v PE, ni na J:."
goto :aborted
:src_ok
call :say "  Istochnik: %SRCB%"
if defined BCE goto :bce_ok
call :say "[SBOJ] bcdedit net - ruchnaya sborka nevozmozhna."
goto :aborted
:bce_ok
mkdir "G:\EFI\Microsoft\Boot" >nul 2>&1
mkdir "G:\EFI\Boot" >nul 2>&1
if exist "G:\EFI\Microsoft\Boot\bootmgfw.efi" goto :mgfw_ok
copy /y "%SRCB%" "G:\EFI\Microsoft\Boot\bootmgfw.efi" >nul 2>&1
:mgfw_ok
if exist "G:\EFI\Boot\bootx64.efi" goto :bx64_ok
copy /y "%SRCB%" "G:\EFI\Boot\bootx64.efi" >nul 2>&1
:bx64_ok
if exist "G:\EFI\Microsoft\Boot\bootmgfw.efi" (call :say "  [OK] bootmgfw.efi na G:") else (call :say "  [NET] bootmgfw.efi NE skopirovalsya")
if exist "G:\EFI\Boot\bootx64.efi" (call :say "  [OK] bootx64.efi na G:") else (call :say "  [NET] bootx64.efi NE skopirovalsya")
if exist "G:\EFI\Microsoft\Boot\BCD" (
  call :say "  [OK] BCD uzhe est - ne torgayu ego, proverka dalshe."
  goto :bcd_made
)
call :say "  Sobirayu BCD cherez bcdedit s nulya:"
set "BUE=G:\EFI\Microsoft\Boot\BCD"
"%BCE%" /createstore "%BUE%" > "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /create {bootmgr} /d "Windows Boot Manager" >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /set {bootmgr} device partition=G: >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /timeout 10 >> "%DPO%" 2>&1
"%BCE%" /store "%BUE%" /create /application osloader /d "Windows 11" > "%TEMP%\fx2_guid.txt" 2>&1
set "GUID="
for /f "tokens=2 delims={}" %%A in ('findstr "{" "%TEMP%\fx2_guid.txt"') do if not "%%A"=="" set "GUID={%%A}"
if defined GUID if "%GUID:~0,1%"=="{" goto :guid_ok
call :say "  [SBOJ] bcdedit ne sozdal osloader - vyvod:"
call :dump "%TEMP%\fx2_guid.txt"
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
:bcd_made
:bios_stage
call :say ""
call :say "[5] BIOS-ZAPAS dlya CSM/Legacy rezhima - Plan B"
if exist "G:\bootmgr" if exist "G:\Boot\BCD" (
  call :say "  [OK] BIOS-fajly uzhe zality - propuskayu."
  goto :bios_done
)
if not exist "%WINL%:\Windows\Boot\PCAT\bootmgr" (
  call :say "  [--] %WINL%:\Windows\Boot\PCAT\bootmgr NET - BIOS-zapas propuskaetsya."
  goto :bios_done
)
if not defined BCE (
  call :say "  [--] bcdedit net - BIOS-zapas propuskaetsya."
  goto :bios_done
)
copy /y "%WINL%:\Windows\Boot\PCAT\bootmgr" "G:\bootmgr" >nul 2>&1
if exist "G:\bootmgr" (call :say "  [OK] G:\bootmgr na meste") else (call :say "  [NET] G:\bootmgr ne skopirovalsya")
mkdir "G:\Boot" >nul 2>&1
if exist "G:\Boot\BCD" goto :bios_bcd_made
call :say "  Sobirayu BIOS-BCD cherez bcdedit:"
set "BBI=G:\Boot\BCD"
"%BCE%" /createstore "%BBI%" > "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /create {bootmgr} /d "Windows Boot Manager" >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /set {bootmgr} device partition=G: >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /timeout 10 >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /create /application osloader /d "Windows 11" > "%TEMP%\fx2_guid2.txt" 2>&1
set "GUID2="
for /f "tokens=2 delims={}" %%A in ('findstr "{" "%TEMP%\fx2_guid2.txt"') do if not "%%A"=="" set "GUID2={%%A}"
if defined GUID2 if "%GUID2:~0,1%"=="{" goto :guid2_ok
call :say "  [--] bcdedit ne dal GUID dlya BIOS BCD - propuskayu. Vyvod v log:"
call :dump "%TEMP%\fx2_guid2.txt"
call :dump "%DPO%"
goto :bios_done
:guid2_ok
"%BCE%" /store "%BBI%" /set %GUID2% device partition=%WINL%: >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /set %GUID2% osdevice partition=%WINL%: >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /set %GUID2% path \Windows\system32\winload.exe >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /set %GUID2% systemroot \Windows >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /set {bootmgr} default %GUID2% >> "%DPO%" 2>&1
"%BCE%" /store "%BBI%" /set {bootmgr} displayorder %GUID2% >> "%DPO%" 2>&1
call :dump "%DPO%"
:bios_bcd_made
if defined BSX (
  call :say "  Bootsect: menyaet tolko zagruzochnyj kod, tablicu razdelov NE torgaet."
  "%BSX%" /nt60 G: /mbr /force > "%DPO%" 2>&1
  call :dump "%DPO%"
) else (
  call :say "  [--] bootsect net - MBR i VBR kod ostalsya kak byl."
)
> "%DPW%" echo select disk 0
>>"%DPW%" echo select part 1
>>"%DPW%" echo active
diskpart /s "%DPW%" > "%DPO%" 2>&1
call :dump "%DPO%"
call :say "  [OK] Razdel 1 pomechen aktivnym - esli diskpart vyshe bez oshibok."
:bios_done

call :say ""
call :say "[6] VERIFIKACIYA"
if not defined BCE set "BCE=bcdedit"
call :chkuefi
if defined UEOK (call :say "  [OK] Fajly UEFI: BCD + bootmgfw.efi + bootx64.efi") else (call :say "  [NET] Fajly UEFI ne sobralis")
if not exist "G:\EFI\Microsoft\Boot\BCD" goto :no_bcduefi
"%BCE%" /store "G:\EFI\Microsoft\Boot\BCD" /enum all > "%TEMP%\fx2_bcd.txt" 2>&1
call :dump "%TEMP%\fx2_bcd.txt"
set "IDENT=0"
set "OSDOK="
set "WLEFI="
for /f "delims=" %%A in ('type "%TEMP%\fx2_bcd.txt"') do (
  set "LN=%%A"
  echo(!LN!|findstr /i /c:"identifier" >nul && set /a IDENT+=1
  echo(!LN!|findstr /i /c:"osdevice" >nul && echo(!LN!|findstr /i /c:"partition=%WINL%:" >nul && set "OSDOK=1"
  echo(!LN!|findstr /i /c:"winload.efi" >nul && set "WLEFI=1"
)
call :say "  Identifier-ov v BCD: !IDENT!"
if defined OSDOK (call :say "  [OK] osdevice vedet na %WINL%:") else (call :say "  [NET] osdevice ne na %WINL%:")
if defined WLEFI (call :say "  [OK] put k winload.efi v BCD est") else (call :say "  [NET] v BCD net winload.efi")
goto :bcduefi_done
:no_bcduefi
call :say "  [NET] BCD UEFI otsutstvuet"
:bcduefi_done
if exist "G:\bootmgr" (call :say "  [OK] G:\bootmgr est") else (call :say "  [--] G:\bootmgr net")
if not exist "G:\Boot\BCD" goto :no_bcdbios
"%BCE%" /store "G:\Boot\BCD" /enum all > "%TEMP%\fx2_bcd2.txt" 2>&1
call :dump "%TEMP%\fx2_bcd2.txt"
goto :bcdbios_done
:no_bcdbios
call :say "  [--] BIOS BCD - G:\Boot\BCD net"
:bcdbios_done

call :say ""
call :say "=================================================="
call :say " VERDIKT"
call :say "=================================================="
call :chkuefi
if defined UEOK (call :say "  UEFI: ZAGRUZCHIK SOBRAN - G:\EFI\Microsoft\Boot\BCD + bootx64.efi") else (call :say "  UEFI: NE SOBRALSYA - prishly log")
if exist "G:\Boot\BCD" (call :say "  BIOS-zapas: EST - G:\bootmgr + G:\Boot\BCD + active + MBR-kod") else (call :say "  BIOS-zapas: NET")
call :say "  CHto delat:"
call :say "   1. Reboot - predlozhu srazu posle sohraneniya loga."
call :say "   2. V boot-menu vyberi disk 0: punkt Windows Boot Manager"
call :say "      ili UEFI: tvoy disk. Est CSM/Legacy - poprobuy i ego:"
call :say "      BIOS-zapas uzhe zality, on lovit BIOS-zagruzku."
call :say "   3. Dolzhen poyavitsya menedzher zagruzki s punktom Windows 11."
call :say "   4. Ne pojdet - prishly PHX_FIX2_LOG.TXT tekstom."
choice /c YN /m "  Reboot sejchas? Y - da, N - snachala log"
if errorlevel 2 goto :noreboot
wpeutil reboot
goto :eof

:noreboot
call :say "  Reboot otlozhen: zapusti sam - wpeutil reboot"

:fin
call :say ""
call :say "[7] KOPII LOGA"
for %%D in ("%USERPROFILE%\Desktop" "X:\Users\Public\Desktop" "X:\Users\Administrator\Desktop") do (
  if exist "%%~D\" copy /y "%REP%" "%%~D\PHX_FIX2_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: %%~D\PHX_FIX2_LOG.TXT"
)
if defined WINL copy /y "%REP%" "%WINL%:\PHX_FIX2_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: %WINL%:\PHX_FIX2_LOG.TXT"
copy /y "%REP%" "%~dp0PHX_FIX2_LOG.TXT" >nul 2>&1 && call :say "  Kopiya: ryadom s batnikom"

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

:chkuefi
set "UEOK="
if exist "G:\EFI\Microsoft\Boot\BCD" if exist "G:\EFI\Microsoft\Boot\bootmgfw.efi" if exist "G:\EFI\Boot\bootx64.efi" set "UEOK=1"
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
