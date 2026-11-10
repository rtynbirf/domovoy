@echo off
rem ============================================================
rem  PHX-HUB v1.2 - launcher (CP866, DOS-codepage)
rem  zapusk s avtopodiemom prav (UAC) i -STA dlya WPF
rem  NE REDAKTIRUJ V BLOKNOTE - tolko CP866!
rem ============================================================
setlocal
title PHX-HUB launcher
echo.
echo   PHX-HUB v1.2 (PHOENIX Control Center - profile engine)
echo.
net session >nul 2>&1
if errorlevel 1 goto ELEV
goto RUN
:ELEV
echo   Zapros prav administratora (UAC)...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
goto END
:RUN
cd /d "%~dp0"
if not exist "%~dp0PHX-HUB.ps1" goto NOFILE
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0PHX-HUB.ps1"
goto END
:NOFILE
echo   OSHIBKA: PHX-HUB.ps1 ne najden ryadom s launcherom!
echo   Bat i ps1 dolzhny letet odnoy paroy (PAIR RULE).
pause
:END
endlocal
