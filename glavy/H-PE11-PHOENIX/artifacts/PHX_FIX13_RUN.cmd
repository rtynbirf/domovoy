@echo off
REM ============================================================
REM PHX_FIX13_RUN.cmd  |  H-PE11  |  launcher FIX13 (UAC)
REM Use: PHX_FIX13_RUN.cmd [timeout_sek]   (default 7)
REM ============================================================
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel%==0 goto RUN
echo Proshu prava administratora (UAC)...
if "%~1"=="" (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
) else (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
)
exit /b
:RUN
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PHX_FIX13_MENU_FORCE.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PHX_FIX13_MENU_FORCE.ps1" %~1
)
echo.
pause
