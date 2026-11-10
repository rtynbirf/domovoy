@echo off
rem ============================================================
rem  H-PE11 // PHOENIX-ALPHA 0.1 - CONTROL MENU
rem  ASCII only (cmd codepage safety). Russian docs: README + PS.
rem  Elevation: requires admin (auto-relaunch via RunAs).
rem ============================================================
setlocal
title PHOENIX-ALPHA 0.1 CONTROL

net session >nul 2>&1
if errorlevel 1 (
  echo [!] Admin rights required - relaunching elevated...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

:MENU
cls
echo ============================================================
echo   PHOENIX-ALPHA 0.1 // CONTROL  (kit: C:\PHX\bin)
echo   Rule: measure seven times, cut once.
echo ============================================================
echo   [1] Hardware audit          - full report to C:\PHX\reports
echo   [2] TweakPack REPORT        - Balanced plan, NOTHING applied
echo   [3] TweakPack APPLY Safe    - telemetry/WU/AI only
echo   [4] TweakPack APPLY Balanced- Safe + perf + light debloat
echo   [5] TweakPack APPLY Performance - Balanced + debloat Default
echo   [6] TweakPack APPLY PrivacyMax  - telemetry + Edge + debloat
echo   [7] RESTORE from journal    - rollback reg/svc/task/appx
echo   [8] Open reports folder     - send HW-REPORT to the Master
echo   [0] Exit
echo ============================================================
set /p CHOICE=Select: 
if "%CHOICE%"=="1" goto AUDIT
if "%CHOICE%"=="2" goto REPORT
if "%CHOICE%"=="3" goto SAFE
if "%CHOICE%"=="4" goto BAL
if "%CHOICE%"=="5" goto PERF
if "%CHOICE%"=="6" goto PRIV
if "%CHOICE%"=="7" goto RESTORE
if "%CHOICE%"=="8" goto REPORTS
if "%CHOICE%"=="0" goto END
goto MENU

:AUDIT
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-HW-AUDIT.ps1"
echo.
echo Done. Report: C:\PHX\reports\PHX-HW-REPORT.txt
pause
goto MENU

:REPORT
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-RUN.ps1" -Profile Balanced -Mode Report
echo.
echo Done. Log on Desktop: PHX_TWEAKPACK_*.log
pause
goto MENU

:SAFE
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-RUN.ps1" -Profile Safe -Mode Apply
echo.
echo Done. Rollback: menu [7] or PHX_TWEAKBACKUP_*\rollback.ps1
pause
goto MENU

:BAL
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-RUN.ps1" -Profile Balanced -Mode Apply
echo.
echo Done. Rollback: menu [7] or PHX_TWEAKBACKUP_*\rollback.ps1
pause
goto MENU

:PERF
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-RUN.ps1" -Profile Performance -Mode Apply
echo.
echo Done. Rollback: menu [7] or PHX_TWEAKBACKUP_*\rollback.ps1
pause
goto MENU

:PRIV
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-RUN.ps1" -Profile PrivacyMax -Mode Apply
echo.
echo Done. Rollback: menu [7] or PHX_TWEAKBACKUP_*\rollback.ps1
pause
goto MENU

:RESTORE
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-RUN.ps1" -Profile Balanced -Mode Restore
echo.
pause
goto MENU

:REPORTS
start "" explorer "C:\PHX\reports"
goto MENU

:END
endlocal
exit /b 0
