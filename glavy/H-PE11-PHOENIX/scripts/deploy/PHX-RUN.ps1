# =====================================================================
# H-PE11 // PHX-RUN.ps1 - исполнитель профилей PHX_TWEAKPACK v2.0
# Проблема: v2.0 - paste-and-run (профиль/режим заданы в теле скрипта,
#           не в param()). Меню должно запускать КОНКРЕТНЫЙ профиль,
#           не редактируя файл руками.
# Решение: regex-подмена строки шапки во временной копии + Invoke-Expression.
#           Тело скрипта не меняется, журнал/логи пишутся как обычно.
# ЭВ.1: если файл не найден или подмена не сработала - [--] и стоп.
# =====================================================================
param(
  [ValidateSet('Safe','Balanced','Performance','PrivacyMax','Custom')]
  [string]$ProfileName = 'Balanced',
  [ValidateSet('Report','Apply','Restore')]
  [string]$Mode = 'Report'
)

$ErrorActionPreference = 'Continue'
$srcPath = Join-Path $PSScriptRoot 'PHX_TWEAKPACK.ps1'
if (-not (Test-Path $srcPath)) {
  Write-Host "[--] PHX_TWEAKPACK.ps1 не найден: $srcPath"
  exit 1
}

# Чтение: файл в ките хранится в UTF-8 BOM (PS 5.1 читает корректно)
$src = Get-Content -LiteralPath $srcPath -Raw -Encoding UTF8

$profLine = '$PhxProfile = ' + "'" + $ProfileName + "'"
$modeLine = '$PhxMode   = ' + "'" + $Mode + "'"

$patched = $src -replace '(?m)^\$PhxProfile\s*=.*$', ([regex]::Escape($profLine).Replace('\',''))
$patched = $patched -replace '(?m)^\$PhxMode\s*=.*$', ([regex]::Escape($modeLine).Replace('\',''))

# Проверка подмены (ЭВ.1): строка шапки должна реально замениться
$check = ($patched -split "`n" | Select-String -Pattern '^\$PhxProfile\s*=' | Select-Object -First 1)
if ($check -notmatch [regex]::Escape($ProfileName)) {
  Write-Host "[--] подмена профиля не подтвердилась - СТОП (никаких действий)"
  exit 1
}

Write-Host "PHX-RUN: профиль=$ProfileName режим=$Mode"
Invoke-Expression $patched
