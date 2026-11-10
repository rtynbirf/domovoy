@echo off
rem ============================================================
rem  PHX-DISK-PREP.bat  v2.0  26.10.2026
rem  PHOENIX / H-PE11: remove stale boot stub on Disk 0 so that
rem  Windows Setup creates a FRESH System partition + fresh BCD.
rem
rem  DELETES: Disk 0, partition 1 only (~100 MB FAT32 System
rem  stub, confirmed by PHX-DISK-SCAN 26.10 13:20).
rem  NEVER TOUCHES: extended/logical (E: Data, F: STREL) on
rem  Disk 0, and all of Disk 1 (Ventoy).
rem  Two manual confirmations required. No PowerShell. ASCII.
rem  Log saved next to this file.
rem ============================================================
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "TS=%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%"
set "TS=%TS: =0%"
set "OUT=PHX_DISKPREP_%TS%.txt"
set "DP=%TEMP%\phx_prep.txt"
set "SHOW=%TEMP%\phx_show.txt"

>"%OUT%" echo ==============================================
>>"%OUT%" echo PHX-DISK-PREP %DATE% %TIME%
>>"%OUT%" echo Computer: %COMPUTERNAME%  User: %USERNAME%
>>"%OUT%" echo ==============================================

echo ==============================================
echo  PHX-DISK-PREP v2.0 - fresh boot stage prep
echo ==============================================
echo Will delete: Disk 0, PARTITION 1 (100 MB System stub)
echo Will NOT touch: E: Data, F: STREL, Disk 1 (Ventoy)
echo.

echo [1/4] Disk 0 partition map BEFORE:
>>"%OUT%" echo ============ BEFORE: DISK 0 MAP ============
(echo rescan
echo select disk 0
echo list partition
echo exit)>"%DP%"
diskpart /s "%DP%" >"%SHOW%" 2>&1
type "%SHOW%"
type "%SHOW%" >>"%OUT%"

echo.
echo Expected per scan 26.10 13:20:
echo   Partition 1 = System, 100 MB  (the stub to delete)
echo   Partition 0 = Extended 872 GB (container for E:/F:)
echo   Partition 2 = Logical 850 GB (E: Data)
echo   Partition 3 = Logical 21 GB  (F: STREL)
echo If the map above does NOT match - press Enter to abort.
echo.
set "ANS="
set /p "ANS=Type Y to delete Disk 0 Partition 1 (100 MB): "
if /i not "!ANS!"=="Y" goto ABORT

echo.
echo [2/4] Forensic detail of partition 1 before deletion:
>>"%OUT%" echo ============ DETAIL PARTITION 1 ============
(echo select disk 0
echo select partition 1
echo detail partition
echo exit)>"%DP%"
diskpart /s "%DP%" >"%SHOW%" 2>&1
type "%SHOW%"
type "%SHOW%" >>"%OUT%"

echo.
set "ANS2="
set /p "ANS2=Final: type DELETE to wipe it now: "
if /i not "!ANS2!"=="DELETE" goto ABORT

echo.
echo [3/4] Deleting Disk 0 Partition 1 ...
>>"%OUT%" echo ============ DELETE PARTITION 1 ON DISK 0 ============
(echo select disk 0
echo select partition 1
echo delete partition
echo exit)>"%DP%"
diskpart /s "%DP%" >"%SHOW%" 2>&1
type "%SHOW%"
type "%SHOW%" >>"%OUT%"

echo.
echo [4/4] Disk 0 partition map AFTER:
>>"%OUT%" echo ============ AFTER: DISK 0 MAP ============
(echo select disk 0
echo list partition
echo exit)>"%DP%"
diskpart /s "%DP%" >"%SHOW%" 2>&1
type "%SHOW%"
type "%SHOW%" >>"%OUT%"

>>"%OUT%" echo ============ END ============
echo.
echo DONE. Expected: Partition 1 gone, ~60 GB unallocated total.
echo.
echo NEXT STEPS:
echo  1) MemTest86+ first if not done yet (RAM is suspect No.1).
echo  2) Boot PHOENIX ISO from Ventoy (legacy boot - proven).
echo  3) In Setup pick UNALLOCATED ~60 GB on Drive 0.
echo     Do NOT touch E: Data / F: STREL.
echo  4) Setup creates fresh System partition + C: by itself.
echo.
echo Log: %CD%\%OUT%
goto END

:ABORT
>>"%OUT%" echo ============ ABORTED BY USER ============
echo.
echo ABORTED. Nothing was deleted. Log: %CD%\%OUT%

:END
endlocal
