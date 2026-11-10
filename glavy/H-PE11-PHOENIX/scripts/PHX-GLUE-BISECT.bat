@echo off
setlocal EnableDelayedExpansion
title PHX GLUE v5 (7-Zip) - PHOENIX-ALPHA-0.2-BISECT
cd /d "%~dp0"

set "ISO=PHOENIX-ALPHA-0.2-BISECT.iso"
set "DLDIR=%USERPROFILE%\Downloads"
for %%D in ("%~dp0..") do set "PARDIR=%%~fD"
if not defined TEMP set "TEMP=%CD%"
set /a BAD=0

echo ==============================================================
echo   PHOENIX-ALPHA-0.2-BISECT ISO  -  JOIN VIA 7-ZIP  (v5)
echo   This folder : %CD%
echo   7-Zip joins .001+.002+...+.010 into the ISO by itself.
echo ==============================================================
echo.

echo [1/5] Finding parts (this folder, parent, Downloads)...
for %%P in (00 01 02 03 04 05 06 07 08 09) do call :LOCATE %%P
if !BAD! GTR 0 goto SEARCHFAIL
echo.

echo [2/5] Renaming part00..09 into 7-Zip split names .001..010 ...
call :RENAME 00 001
call :RENAME 01 002
call :RENAME 02 003
call :RENAME 03 004
call :RENAME 04 005
call :RENAME 05 006
call :RENAME 06 007
call :RENAME 07 008
call :RENAME 08 009
call :RENAME 09 010
if !BAD! GTR 0 goto END
echo.

echo [3/5] Checking sizes...
for %%A in ("!ISO!.001" "!ISO!.002" "!ISO!.003" "!ISO!.004" "!ISO!.005" "!ISO!.006" "!ISO!.007" "!ISO!.008" "!ISO!.009") do (
  if %%~zA NEQ 463393178 (
    echo   [FAIL] %%~nxA size is %%~zA, expected 463393178
    set /a BAD+=1
  )
)
for %%A in ("!ISO!.010") do (
  if %%~zA NEQ 463393174 (
    echo   [FAIL] %%~nxA size is %%~zA, expected 463393174
    set /a BAD+=1
  )
)
if !BAD! GTR 0 goto END
echo   OK - sizes match.
echo.

echo [4/5] Joining with 7-Zip...
if exist "!ISO!" (
  echo   "!ISO!" already exists - skipping join, going to final check.
  echo.
  goto HASHFINAL
)
set "SEVEN="
if exist "%ProgramFiles%\7-Zip\7z.exe" set "SEVEN=%ProgramFiles%\7-Zip\7z.exe"
if not defined SEVEN if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" set "SEVEN=%ProgramFiles(x86)%\7-Zip\7z.exe"
if not defined SEVEN (
  echo   7-Zip not found in Program Files.
  echo.
  echo   DO IT BY HAND (10 seconds):
  echo     Right-click "!ISO!.001"  -^>  7-Zip  -^>  Extract Here
  echo   7-Zip joins all 10 pieces into "!ISO!" automatically.
  echo   Then run this bat again - it will skip to the final check.
  echo.
  goto HASHFINAL
)
echo   Using: !SEVEN!
"!SEVEN!" x -y "!ISO!.001" -o"%CD%"
if errorlevel 1 (
  echo   [FAIL] 7-Zip could not join the parts.
  echo   Check free disk space, or re-download the failing part.
  set /a BAD+=1
  goto END
)
echo.

:HASHFINAL
echo [5/5] Final check of the whole ISO (Law 4)...
if not exist "!ISO!" (
  echo   [FAIL] "!ISO!" not found after join.
  set /a BAD+=1
  goto END
)
for %%A in ("!ISO!") do echo   ISO size: %%~zA bytes  (expected 4633931776)
certutil -hashfile "!ISO!" SHA256 > "%TEMP%\phx_final.txt" 2>&1
set "H="
for /f "usebackq skip=1 delims=" %%L in ("%TEMP%\phx_final.txt") do if not defined H set "H=%%L"
if /i "!H!"=="12332871ac64bc2fb21b0139a927f6ea8972378004ebcd5d5aaaac3c8ccfd43a" (
  echo   SHA256 OK - ISO is intact.
) else (
  echo   [WARN] Hash mismatch or hash tool failed. RAW OUTPUT:
  type "%TEMP%\phx_final.txt"
  echo   If the hash line above is not 12332871ac64bc2f... then re-download
  echo   the corrupt part ^(run this bat - it will say which^).
  echo   If the ISO itself is stale - delete it and run this bat again.
)

echo ==============================================================
echo   === ISO IS READY ===
echo   File: %CD%\!ISO!
echo.
echo   WHAT IS DIFFERENT IN 0.2-BISECT:
echo     - NO auto-user, NO AutoLogon, NO password on media.
echo       User is created MANUALLY in OOBE.
echo     - SetupComplete = DRIVERS ONLY (pnputil C:\Drivers).
echo       TWEAKPACK does NOT auto-run. Everything manual AFTER
echo       install via C:\PHX\bin\PHOENIX-CONTROL.cmd
echo.
echo   NEXT STEPS (Rufus):
echo     1. Rufus: select this ISO
echo     2. Partition scheme: MBR
echo     3. Target system: BIOS (or UEFI-CSM)
echo     4. File system: NTFS
echo     5. START - it will erase the USB stick
echo   Then boot from USB (Legacy) and install into the UNALLOCATED
echo   ~60 GB on Drive 0. Do NOT touch E: Data / F: STREL.
echo   Pick the unallocated space - Setup creates System+C: itself.
echo ==============================================================

goto END

:LOCATE
set "PN=%1"
set "CANON=%ISO%.part%PN%"
set /a NUM=10%PN% %% 100 + 1
set "N3=00!NUM!"
set "N3=!N3:~-3!"
if exist "!CANON!" (
  echo   OK      !CANON!
  goto :eof
)
if exist "!ISO!.!N3!" (
  echo   OK      !ISO!.!N3!  (already renamed)
  goto :eof
)
set /a NCAND=0
for /f "delims=" %%F in ('dir /b /a-d "!CANON!*" 2^>nul') do call :ADDCAND "%~dp0%%F"
if /i not "!CD!"=="!DLDIR!" if /i not "!PARDIR!"=="!DLDIR!" if exist "!DLDIR!" for /f "delims=" %%F in ('dir /b /a-d "!DLDIR!\!CANON!*" 2^>nul') do call :ADDCAND "!DLDIR!\%%F"
if /i not "!PARDIR!"=="!CD!" if /i not "!PARDIR!"=="!DLDIR!" for /f "delims=" %%F in ('dir /b /a-d "!PARDIR!\!CANON!*" 2^>nul') do call :ADDCAND "!PARDIR!\%%F"
if !NCAND!==0 (
  echo   [MISS]  !CANON! - not in this folder, parent folder or Downloads
  set /a BAD+=1
  goto :eof
)
if !NCAND! GTR 1 (
  echo   [AMBIG] !CANON! - found !NCAND! candidates:
  for /l %%I in (1,1,!NCAND!) do echo           - !CAND%%I!
  echo           Keep only ONE copy of each part, delete extras, run again.
  set /a BAD+=1
  goto :eof
)
copy /y "!CAND1!" "!CANON!" >nul
if errorlevel 1 (
  echo   [FAIL]  Cannot copy !CAND1! here - check free disk space.
  set /a BAD+=1
  goto :eof
)
echo   COPIED  !CANON!   from   !CAND1!
goto :eof

:ADDCAND
set "F=%~1"
echo !F!| findstr /i ".crdownload .download .tmp" >nul && goto :eof
set /a NCAND+=1
set "CAND!NCAND!=!F!"
goto :eof

:RENAME
set "OLD=%ISO%.part%1"
set "NEW=%ISO%.%2"
if exist "!OLD!" (
  if exist "!NEW!" (
    echo   DUPLICATE: both !OLD! and !NEW! exist - removing !OLD!
    del /f /q "!OLD!"
  ) else (
    ren "!OLD!" "!NEW!"
    if errorlevel 1 (
      echo   [FAIL] cannot rename !OLD! to !NEW!
      set /a BAD+=1
      goto :eof
    )
    echo   part%1  --^>  .%2
  )
) else (
  if exist "!NEW!" (
    echo   OK      !NEW! already in place
  ) else (
    echo   [MISS]  neither !OLD! nor !NEW! found
    set /a BAD+=1
  )
)
goto :eof

:SEARCHFAIL
echo.
echo   Could not locate all 10 parts automatically.
echo.
echo   === Files actually in THIS folder now ===
dir /b /a-d 2>nul
echo   =========================================
echo   === PHOENIX files in Downloads ===
if exist "!DLDIR!" dir /b /a-d "!DLDIR!\PHOENIX*" 2>nul
echo   =========================================
echo.
echo   If the parts are nowhere: download all 10 from the release page
echo   https://github.com/rtynbirf/H-PE11-PHOENIX/releases/tag/phoenix-alpha-0.2-bisect

:END
echo.
pause
endlocal
