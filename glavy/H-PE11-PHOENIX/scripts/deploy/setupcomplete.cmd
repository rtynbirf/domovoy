@echo off
rem ============================================================
rem  H-PE11 // PHOENIX-ALPHA 0.1 - SetupComplete entry
rem  $OEM$ \$1 -> C:\ (PHX kit already deployed to C:\PHX\bin)
rem  ASCII only: cmd codepage safety. Russian docs: README.
rem ============================================================
setlocal
if not exist "C:\PHX" mkdir "C:\PHX"
if not exist "C:\PHX\logs" mkdir "C:\PHX\logs"
if not exist "C:\PHX\reports" mkdir "C:\PHX\reports"
if not exist "C:\PHX\bin" mkdir "C:\PHX\bin"

rem local-account OOBE guard (also used by later scenarios)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f >nul 2>&1

rem Phoenix stage: HW audit + TWEAKPACK v2.0 REPORT. NOTHING applied!
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\PHX\bin\PHX-SETUP-COMPLETE.ps1" >> "C:\PHX\logs\setupcomplete.log" 2>&1

endlocal
exit /b 0
