# =====================================================================
# H-PE11 // BOMB BUILDER v1.0 (paste-and-run)
# Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ. ЭВ.1: недоступно = НЕ сделано (метка [--]).
# Решение Хозяина: официальные матрицы поддержки НЕ ограничивают интеграцию.
# Требования: Windows 11, консоль PowerShell ОТ ИМЕНИ АДМИНИСТРАТОРА,
#             установленный ADK + WinPE-аддон (проверка в секции 0).
# Как запускать: выделить ВСЁ, скопировать, вставить в консоль admin PS,
#             Enter. Флаги ниже можно править ДО вставки.
# =====================================================================

# ==== ФЛАГИ (можно править до вставки) ====
$HpeAddSetupPkgs = $false   # $true = добавить WinPE-Setup + SRT (+~450 МБ)
$HpeWimSource    = ''       # путь к исходному boot.wim/winpe.wim; пусто = авто-поиск через copype
$HpeDriversRoot  = ''       # путь к папке WinPE_Drivers; пусто = авто-поиск на рабочем столе
$HpePayload      = ''       # путь к payload (DirectX/VC/Tools/Net35); пусто = авто-поиск
$HpeKeepMount    = $false   # $true = не размонтировать образ после сбоя (для отладки)

& {
  $ErrorActionPreference = 'Continue'
  $ts     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
  $work   = "C:\HPE11_BOMB_$ts"
  $log    = "$env:USERPROFILE\Desktop\H-PE11_BOMB_$ts.log"
  $script:HpeOk = 0; $script:HpeFail = 0
  $script:HpeEV1 = @()

  function Write-Log([string]$msg) {
    $line = "$msg"
    Write-Host $line
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
  }
  function Set-EV1([string]$item, [bool]$done, [string]$note) {
    if ($done) { Write-Log ("  [x] " + $item + "  " + $note) }
    else {
      Write-Log ("  [--] " + $item + "  " + $note)
      $script:HpeEV1 += ($item + " :: " + $note)
      $script:HpeFail++
    }
  }
  function Run-Dism {
    param([string[]]$DismArgs, [string]$What)
    $dism = "$env:SystemRoot\System32\Dism.exe"
    Write-Log ("DISM: " + $What)
    $out = & $dism @DismArgs '/NoRestart' 2>&1
    $code = $LASTEXITCODE
    $out | ForEach-Object { $s = ($_ | Out-String).TrimEnd(); if ($s.Length -gt 0) { Write-Log ("  | " + $s) } }
    if ($code -eq 0) { Write-Log ("  => OK (0)"); return $true }
    if ($code -eq 3010) { Write-Log ("  => OK (3010)"); return $true }
    Write-Log ("  => FAIL (" + $code + ")")
    return $false
  }

  Write-Log "=================================================================="
  Write-Log "  H-PE11 // BOMB BUILDER v1.0"
  Write-Log "  Дата: $ts"
  Write-Log "  ПК: $env:COMPUTERNAME | Пользователь: $env:USERDOMAIN\$env:USERNAME"
  Write-Log "  Лог: $log"
  Write-Log "  Рабочая папка: $work"
  Write-Log "  Режим: БОМБА (официальная поддержка не требуется)"
  Write-Log "=================================================================="

  # ---------- СЕКЦИЯ 0. Проверка окружения ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 0. ПРОВЕРКА ОКРУЖЕНИЯ =="
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  Set-EV1 'Права администратора' $isAdmin 'без них DISM/reg load не работают'
  if (-not $isAdmin) { Write-Log "СТОП: открой PowerShell от имени администратора и вставь скрипт снова."; return }

  $kitsRoot = $null
  try {
    $rk = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue
    if ($rk -and $rk.KitsRoot10) { $kitsRoot = $rk.KitsRoot10 }
  } catch { }
  if (-not $kitsRoot) { $kitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\" }
  $wpeRoot = Join-Path $kitsRoot 'Assessment and Deployment Kit\Windows Preinstallation Environment'
  $ocRoot  = Join-Path $wpeRoot 'amd64\WinPE_OCs'
  $copype  = Join-Path $wpeRoot 'copype.cmd'
  $hasAdk  = (Test-Path $ocRoot) -and (Test-Path $copype)
  Set-EV1 'ADK + WinPE-аддон найдены' $hasAdk ($wpeRoot)
  if (-not $hasAdk) {
    Write-Log "СТОП: ADK/WinPE-аддон не найден. Установи:"
    Write-Log "  winget install Microsoft.WindowsADK"
    Write-Log "  winget install Microsoft.ADKPEAddon"
    Write-Log "  либо вручную с https://learn.microsoft.com/windows-hardware/get-started/adk-install"
    Write-Log "ЭВ.1: сборка НЕ выполнена [--]"
    return
  }
  $dismVer = & "$env:SystemRoot\System32\Dism.exe" '/?' 2>$null | Select-Object -First 1
  Write-Log ("  DISM: " + $dismVer)

  # Язык опциональных компонентов
  $lang = ''
  foreach ($cand in @('ru-RU','en-US')) { if (Test-Path (Join-Path $ocRoot $cand)) { $lang = $cand; break } }
  Write-Log ("  Языковые cabs WinPE_OCs: " + $(if ($lang) { $lang } else { 'нет (только language-neutral)' }))

  # ---------- СЕКЦИЯ 1. Рабочая папка + media ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 1. РАБОЧАЯ ПАПКА + MEDIA =="
  try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $mount = "C:\HPE11_MNT"
    & "$env:SystemRoot\System32\Dism.exe" '/Cleanup-Wim' 2>$null | Out-Null
    if (Test-Path $mount) { Remove-Item -LiteralPath (Join-Path $mount '*') -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $mount -Force | Out-Null
    $media = "$work\media"
    if ($HpeWimSource -and (Test-Path $HpeWimSource)) {
      Write-Log "  Флаг HpeWimSource задан: $HpeWimSource"
      & cmd /c "`"$copype`" amd64 `"$media`"" | Out-Null
      Copy-Item -LiteralPath $HpeWimSource -Destination "$media\sources\boot.wim" -Force
    } else {
      Write-Log "  copype amd64 -> $media"
      & cmd /c "`"$copype`" amd64 `"$media`"" | Out-Null
    }
    $bootWimSrc = "$media\sources\boot.wim"
    $okWim = Test-Path $bootWimSrc
    Set-EV1 'Media-структура создана (boot.wim)' $okWim ($bootWimSrc)
    if (-not $okWim) { Write-Log "СТОП: нет boot.wim в media. ЭВ.1: [--]"; return }
  } catch {
    Write-Log ("СЕКЦИЯ 1 ОШИБКА: " + $_.Exception.Message)
    return
  }

  # ---------- СЕКЦИЯ 2. Монтирование ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 2. МОНТИРОВАНИЕ ОБРАЗА =="
  $mounted = $false
  try {
    $mounted = Run-Dism -DismArgs @('/Mount-Wim','/WimFile:' + $bootWimSrc,'/Index:1','/MountDir:' + $mount) -What 'Mount-Wim index 1'
    if (-not $mounted) { Write-Log "СТОП: монтирование не удалось. ЭВ.1: [--]"; return }
  } catch {
    Write-Log ("СЕКЦИЯ 2 ОШИБКА: " + $_.Exception.Message)
    return
  }

  # ---------- СЕКЦИЯ 3. Опциональные компоненты ADK (порядок зависимостей) ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 3. ADK ОПЦИОНАЛЬНЫЕ КОМПОНЕНТЫ (БОМБОВЫЙ ЗАРЯД) =="
  $pkgList = @('WinPE-WMI','WinPE-Scripting','WinPE-NetFx','WinPE-PowerShell','WinPE-StorageWMI','WinPE-DismCmdlets','WinPE-MDAC','WinPE-HTA','WinPE-FMAPI','WinPE-SecureStartup','WinPE-WDS-Tools')
  if ($HpeAddSetupPkgs) { $pkgList += @('WinPE-Setup','WinPE-Setup-Client','WinPE-SRT') }
  $pkgOk = 0; $pkgNo = @()
  try {
    if ($lang) {
      $lp = Join-Path (Join-Path $ocRoot $lang) 'lp.cab'
      if (Test-Path $lp) {
        if (Run-Dism -DismArgs @('/Image:' + $mount,'/Add-Package','/PackagePath:' + $lp) -What "Языковой пакет $lang lp.cab") { $pkgOk++ }
        else { $pkgNo += ('lp.cab(' + $lang + ')') }
      }
    }
    foreach ($p in $pkgList) {
      $cab = Join-Path $ocRoot ($p + '.cab')
      if (Test-Path $cab) {
        if (Run-Dism -DismArgs @('/Image:' + $mount,'/Add-Package','/PackagePath:' + $cab) -What $p) { $pkgOk++ }
        else { $pkgNo += $p }
      } else { $pkgNo += ($p + ' (cab не найден)') }
      if ($lang) {
        $cabL = Join-Path (Join-Path $ocRoot $lang) ($p + '.cab')
        if (Test-Path $cabL) {
          if (Run-Dism -DismArgs @('/Image:' + $mount,'/Add-Package','/PackagePath:' + $cabL) -What ($p + ' (' + $lang + ')')) { $pkgOk++ }
          else { $pkgNo += ($p + '(' + $lang + ')') }
        }
      }
    }
    Set-EV1 'Ядро ADK-заряда (WMI/PS/NetFx/Scripting/MDAC/HTA/FMAPI/SecureStartup/WDS)' ($pkgOk -ge 11) ("добавлено cab: " + $pkgOk)
    if ($pkgNo.Count -gt 0) { Write-Log ("  Не добавлено/ошибки: " + ($pkgNo -join ', ')) }
    $dism = "$env:SystemRoot\System32\Dism.exe"
    try {
      $gp = & $dism ('/Image:' + $mount) '/Get-Packages' '/English' 2>$null
      $script:HpePkgCount = ($gp | Select-String -Pattern 'WinPE-').Count
      Write-Log ("  Пакетов WinPE- в образе (пока смонтирован): " + $script:HpePkgCount)
    } catch { $script:HpePkgCount = 0 }
  } catch {
    Write-Log ("СЕКЦИЯ 3 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('ADK-компоненты :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 4. Драйверы станции (whitelist 11 INF) ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 4. ДРАЙВЕРЫ СТАНЦИИ (WHITELIST) =="
  $drvRoot = $HpeDriversRoot
  if (-not $drvRoot) {
    $cands = Get-ChildItem "$env:USERPROFILE\Desktop" -Directory -Filter 'H-PE11_Collect_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($c in $cands) { $p = Join-Path $c.FullName 'WinPE_Drivers'; if (Test-Path $p) { $drvRoot = $p; break } }
  }
  $whitelist = @('iigd_dch.inf','netwtw04.inf','wintun.inf','apollolakesystem.inf','dptf_acpi.inf','dptf_cpu.inf','esif_manager.inf','ialpss2_spi_bxt_p.inf','ialpss2_uart2_bxt_p.inf','txei.inf','rtsuer.inf')
  $drvOk = 0; $drvNo = @()
  try {
    if ($drvRoot -and (Test-Path $drvRoot)) {
      Write-Log ("  Источник драйверов: " + $drvRoot)
      foreach ($inf in $whitelist) {
        $found = Get-ChildItem $drvRoot -Recurse -Filter $inf -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
          if (Run-Dism -DismArgs @('/Image:' + $mount,'/Add-Driver','/Driver:' + $found.DirectoryName,'/ForceUnsigned') -What ('driver ' + $inf)) { $drvOk++ }
          else { $drvNo += $inf }
        } else { $drvNo += ($inf + ' (не найден в экспорте)') }
      }
      Set-EV1 'Критичные драйверы станции (11)' ($drvOk -eq 11) ("влито: " + $drvOk)
      if ($drvNo.Count -gt 0) { Write-Log ("  Пропущено: " + ($drvNo -join ', ')) }
      try {
        $gd = & "$env:SystemRoot\System32\Dism.exe" ('/Image:' + $mount) '/Get-Drivers' '/English' 2>$null
        $script:HpeDrvCount = ($gd | Select-String -Pattern 'oem\d+\.inf').Count
        Write-Log ("  Сторонних драйверов в образе (пока смонтирован): " + $script:HpeDrvCount)
      } catch { $script:HpeDrvCount = 0 }
    } else {
      Set-EV1 'Критичные драйверы станции (11)' $false 'WinPE_Drivers не найден; запусти collect-station.ps1 или задай HpeDriversRoot'
    }
  } catch {
    Write-Log ("СЕКЦИЯ 4 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('Драйверы :: исключение ' + $_.Exception.Message)
  }
