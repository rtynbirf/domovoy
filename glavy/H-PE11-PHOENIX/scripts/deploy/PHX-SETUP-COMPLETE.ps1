# =====================================================================
# H-PE11 // PHX-SETUP-COMPLETE.ps1 - первый вход после установки
# Запускается из setupcomplete.cmd (SYSTEM) ДО логина пользователя.
# Делает ТОЛЬКО подготовку:
#   1) ярлыки на Public Desktop (CONTROL-меню + README);
#   2) аудит железа -> C:\PHX\reports\PHX-HW-REPORT.txt (+json);
#   3) TWEAKPACK v2.0 в режиме REPORT (Balanced) - ПЛАН, ничего не применено;
#   4) C:\PHX\STATUS.txt - сводка ЭВ.1.
# ПРИНЦИП ALPHA (СЕМЬ РАЗ ОТМЕРЬ): авто-применение твиков ЗАПРЕЩЕНО.
#   Хозяин открывает PHOENIX-CONTROL и сам решает профиль и момент.
# =====================================================================

$ErrorActionPreference = 'Continue'
$ts = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$phxRoot  = 'C:\PHX'
$binDir   = Join-Path $phxRoot 'bin'
$repDir   = Join-Path $phxRoot 'reports'
$logDir   = Join-Path $phxRoot 'logs'
foreach ($d in @($repDir, $logDir)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$status = @()
$script:ev = @()
function Mark([string]$item, [bool]$ok, [string]$note) {
  $line = if ($ok) { "  [x] $item :: $note" } else { "  [--] $item :: $note" }
  Write-Host $line
  $script:status += $line
  if (-not $ok) { $script:ev += "$item :: $note" }
}

Write-Host "== PHOENIX-ALPHA 0.1 // SETUP-COMPLETE $ts =="

# ---------- 1. Ярлыки (Public Desktop - видны всем учёткам) ----------
try {
  $wsh = New-Object -ComObject WScript.Shell
  $pubDesk = Join-Path $env:PUBLIC 'Desktop'
  if (-not (Test-Path $pubDesk)) { New-Item -ItemType Directory -Path $pubDesk -Force | Out-Null }
  $lnk1 = $wsh.CreateShortcut((Join-Path $pubDesk 'PHOENIX-CONTROL.lnk'))
  $lnk1.TargetPath = "$binDir\PHOENIX-CONTROL.cmd"
  $lnk1.WorkingDirectory = $binDir
  $lnk1.Description = 'H-PE11 PHOENIX ALPHA: контроль твикпака/аудита'
  $lnk1.Save()
  $lnk2 = $wsh.CreateShortcut((Join-Path $pubDesk 'PHOENIX-README.lnk'))
  $lnk2.TargetPath = "$binDir\README-ALPHA-RU.txt"
  $lnk2.WorkingDirectory = $binDir
  $lnk2.Description = 'Инструкция PHOENIX ALPHA'
  $lnk2.Save()
  Mark 'ярлыки Public Desktop' $true 'PHOENIX-CONTROL + PHOENIX-README'
} catch { Mark 'ярлыки Public Desktop' $false $_.Exception.Message }

# ---------- 2. Аудит железа (файл для Хозяина) ----------
try {
  & (Join-Path $binDir 'PHX-HW-AUDIT.ps1')
  $hwOk = Test-Path (Join-Path $repDir 'PHX-HW-REPORT.txt')
  Mark 'аудит железа' $hwOk (Join-Path $repDir 'PHX-HW-REPORT.txt')
} catch { Mark 'аудит железа' $false $_.Exception.Message }

# ---------- 3. TWEAKPACK v2.0 REPORT (только план!) ----------
try {
  & (Join-Path $binDir 'PHX-RUN.ps1') -ProfileName Balanced -Mode Report
  $logOnDesk = Get-ChildItem "$env:PUBLIC\Desktop","$env:USERPROFILE\Desktop" -Filter 'PHX_TWEAKPACK_*.log' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Mark 'TWEAKPACK REPORT (Balanced)' ($null -ne $logOnDesk) $(if ($logOnDesk) { $logOnDesk.FullName } else { 'лог не найден' })
} catch { Mark 'TWEAKPACK REPORT' $false $_.Exception.Message }

# ---------- 4. STATUS.txt ----------
$hdr = @(
  'H-PE11 // PHOENIX-ALPHA 0.1 - STATUS',
  "Сформировано: $ts",
  '',
  'ЧТО ДАЛЬШЕ (Хозяин):',
  '  1. Открой PHOENIX-CONTROL (ярлык на рабочем столе).',
  '  2. Пункт [2] - посмотри план (Report), ничего не применено.',
  '  3. Реши профиль: [3] Safe / [4] Balanced / [5] Performance / [6] PrivacyMax.',
  '  4. Отправь Хозяину: C:\PHX\reports\PHX-HW-REPORT.txt',
  '     (и последний PHX_TWEAKPACK_*.log с рабочего стола).',
  '',
  'Отчёт ЭВ.1 стартового слоя:'
)
$tail = @('')
if ($script:ev.Count -gt 0) { $tail += '  НЕ СДЕЛАНО (ЭВ.1):'; foreach ($e in $script:ev) { $tail += "    - $e" } }
$tail += 'Закон: недоступно = НЕ сделано (метка [--]).'
Set-Content -LiteralPath (Join-Path $phxRoot 'STATUS.txt') -Value ($hdr + $script:status + $tail) -Encoding UTF8
Write-Host "== STATUS.txt готов: $phxRoot\STATUS.txt =="
