# ============================================================
#  H-PE11 // BCD MASTER-FIX v1.1
#  Меню уже включено в v1.0 (displaybootmenu + timeout - ОК).
#  v1.1: бэкап ФАЙЛА BCD, старый стиль меню + F8, резервный
#  пункт, рабочий отчёт (баг с алиасом R устранён).
# ============================================================
$ErrorActionPreference = 'Continue'

# --- 0. Самоповыжение ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"{0}"' -f $PSCommandPath))
        exit
    }
    Write-Host "НЕТ ПРАВ АДМИНА. Win+X -> 'Терминал (Администратор)' и вставь блок заново." -ForegroundColor Red
    return
}

$desk = [Environment]::GetFolderPath('Desktop')
$rep  = Join-Path $desk ("BCD_REPORT_v11_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
function Log { param([object]$t) $s = ($t | Out-String).TrimEnd(); if ($s) { $s -split "`r?`n" | ForEach-Object { Write-Host $_ }; Add-Content -LiteralPath $rep -Value $s -Encoding UTF8 } }

Log "============================================================"
Log " H-PE11 // BCD MASTER-FIX v1.1   $(Get-Date)"
Log " Отчёт: $rep"
Log "============================================================"

# --- 1. Хранилище: системное или файл на ESP ---
Log ""
Log "=== 1. ПОИСК ХРАНИЛИЩА ==="
$plain = & bcdedit /enum 2>&1
$plainOK = ($LASTEXITCODE -eq 0)
$ws = $null
if ($plainOK) {
    Log "Системное хранилище ДОСТУПНО."
} else {
    Log "Системное недоступно - монтирую ESP и ищу файл BCD..."
    foreach ($L in 'S','T','U','V') {
        $lp = '{0}:' -f $L
        $null = & mountvol $lp /S 2>&1
        if (Test-Path $lp) {
            Log ("ESP смонтирован: {0}" -f $lp)
            foreach ($c in @("$lp\EFI\Microsoft\Boot\BCD", "$lp\EFI\Boot\BCD", "$lp\Boot\BCD")) {
                if (Test-Path $c) {
                    $null = & bcdedit /store $c /enum 2>&1
                    if ($LASTEXITCODE -eq 0) { $ws = $c; Log ("Хранилище: {0} ({1} байт)" -f $c, (Get-Item $c).Length); break }
                }
            }
            break
        } else { $null = & mountvol $lp /D 2>&1 }
    }
}
$sa = @()
if ($ws) { $sa = @('/store', $ws) }
$can = ($plainOK -or ($null -ne $ws))
if (-not $can) {
    Log "!!! Хранилище не найдено. Пришли отчёт: $rep"
    return
}

# --- 2. Бэкап (на этот раз честный: копия файла или /export) ---
Log ""
Log "=== 2. БЭКАП ==="
$bk = Join-Path $desk ("BCD_BACKUP_{0:yyyyMMdd_HHmm}" -f (Get-Date))
if ($ws) {
    Copy-Item -LiteralPath $ws -Destination $bk -Force
    if (Test-Path $bk) { Log ("Бэкап-файл: {0} ({1} байт)" -f $bk, (Get-Item $bk).Length) }
    else { Log "БЭКАП НЕ УДАЛСЯ - стоп. Пришли отчёт."; return }
} else {
    $o = & bcdedit /export $bk 2>&1 | Out-String; Log $o
    if ($LASTEXITCODE -ne 0) { Log "БЭКАП НЕ УДАЛСЯ - стоп. Пришли отчёт."; return }
    Log ("Бэкап: {0}" -f $bk)
}

# --- 3. Меню: подтверждаем включение + старый стиль ---
Log ""
Log "=== 3. МЕНЮ ЗАГРУЗКИ ==="
$o = & bcdedit @sa /set '{bootmgr}' displaybootmenu yes 2>&1 | Out-String; Log $o
$o = & bcdedit @sa /set '{bootmgr}' timeout 10            2>&1 | Out-String; Log $o
$o = & bcdedit @sa /set '{default}' bootmenupolicy legacy 2>&1 | Out-String; Log $o
Log "(если строка выше ругнулась 'Элемент не найден' - не страшно:"
Log " останется современное меню, выбор и пауза 10 сек всё равно будут)"

# --- 4. Резервный пункт ---
Log ""
Log "=== 4. РЕЗЕРВНЫЙ ПУНКТ МЕНЮ ==="
$a = Read-Host "Добавить 'Windows 11 (резерв)' вторым пунктом? [Y/N]"
if ($a -match '^[YyДд]') {
    $o = & bcdedit @sa /copy '{default}' /d 'Windows 11 (резерв)' 2>&1 | Out-String
    Log $o
    $g = [regex]::Match($o, '\{[0-9a-fA-F\-]{36}\}').Value
    if ($g) {
        $o = & bcdedit @sa /displayorder $g /addlast 2>&1 | Out-String; Log $o
        Log ("Пункт добавлен: {0}" -f $g)
    } else { Log "GUID не распознан - смотри вывод выше." }
} else { Log "Пропущено." }

# --- 5. Итог ---
Log ""
Log "=== 5. ИТОГОВОЕ СОСТОЯНИЕ ==="
$o = & bcdedit @sa /enum 2>&1 | Out-String; Log $o
Log "============================================================"
Log " ГОТОВО. Перезагрузись: меню с выбором, пауза 10 сек."
Log " Бэкап на Рабочем столе: $bk"
Log " (откат: bcdedit /import <файл бэкапа> или копией на S:)"
Log "============================================================"
Write-Host ""
Write-Host "Отчёт: $rep" -ForegroundColor Cyan
