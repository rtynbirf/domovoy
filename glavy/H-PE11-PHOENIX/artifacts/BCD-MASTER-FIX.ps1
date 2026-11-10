# ============================================================
#  H-PE11 // BCD MASTER-FIX v1.0
#  Диагноз + бэкап + меню загрузки "как в MBR" одним прогоном.
#  Отчёт и бэкап - на Рабочем столе. Права поднимает сам.
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
    exit 1
}

$desk = [Environment]::GetFolderPath('Desktop')
$rep  = Join-Path $desk ("BCD_REPORT_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
function R { param([object]$t) $s = ($t | Out-String).TrimEnd(); if ($s) { $s -split "`r?`n" | ForEach-Object { Write-Host $_ }; Add-Content -LiteralPath $rep -Value $s -Encoding UTF8 } }

R "============================================================"
R " H-PE11 // BCD MASTER-FIX   $(Get-Date)"
R " Отчёт: $rep"
R "============================================================"

# --- 1. Окружение ---
R ""
R "=== 1. ОКРУЖЕНИЕ ==="
$os = Get-CimInstance Win32_OperatingSystem
R ("Windows : {0} (build {1})" -f $os.Caption, $os.BuildNumber)
R ("Прошивка: {0}" -f $env:firmware_type)
try { Get-Disk | ForEach-Object { R ("Диск {0}: {1} | {2} | {3} ГБ" -f $_.Number, $_.FriendlyName, $_.PartitionStyle, [math]::Round($_.Size/1GB)) } } catch { R "Get-Disk недоступен: $_" }

# --- 2. Проба системного хранилища ---
R ""
R "=== 2. СИСТЕМНОЕ ХРАНИЛИЩЕ ==="
$plain = & bcdedit /enum 2>&1
$plainOK = ($LASTEXITCODE -eq 0)
R $plain
if ($plainOK) { R "ИТОГ: системное хранилище ДОСТУПНО (прав хватило - дело было в правах)." }
else         { R "ИТОГ: системное хранилище НЕДОСТУПНО - ищу файл BCD вручную..." }

# --- 3. Поиск BCD вручную ---
$ws = $null
if (-not $plainOK) {
    R ""
    R "=== 3. ПОИСК ФАЙЛА BCD ==="
    if ("$env:firmware_type" -match 'UEFI') {
        foreach ($L in 'S','T','U','V') {
            $lp = '{0}:' -f $L
            $null = & mountvol $lp /S 2>&1
            if (Test-Path $lp) {
                R ("ESP смонтирован: {0}" -f $lp)
                foreach ($c in @("$lp\EFI\Microsoft\Boot\BCD", "$lp\EFI\Boot\BCD", "$lp\Boot\BCD")) {
                    if (Test-Path $c) {
                        R ("Найден: {0} ({1} байт)" -f $c, (Get-Item $c).Length)
                        $null = & bcdedit /store $c /enum 2>&1
                        if ($LASTEXITCODE -eq 0) { $ws = $c; R "ЧИТАЕТСЯ по /store - с ним и работаем."; break }
                        else { R "Есть, но не читается (битый?) - продолжаю." }
                    }
                }
                break
            } else { $null = & mountvol $lp /D 2>&1 }
        }
    } else {
        foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter })) {
            $c = '{0}:\Boot\BCD' -f $v.DriveLetter
            if (Test-Path $c) { R "Найден: $c"; $null = & bcdedit /store $c /enum 2>&1; if ($LASTEXITCODE -eq 0) { $ws = $c; break } }
        }
    }
    if (-not $ws) { R "!!! НИ ОДНОГО читаемого BCD не найдено." }
}

$sa = @()
if ($ws) { $sa = @('/store', $ws) }
$can = ($plainOK -or ($null -ne $ws))

# --- 4. Бэкап ---
if ($can) {
    R ""
    R "=== 4. БЭКАП ХРАНИЛИЩА ==="
    $bk = Join-Path $desk ("BCD_BACKUP_{0:yyyyMMdd_HHmm}" -f (Get-Date))
    $o = & bcdedit @sa /export $bk 2>&1 | Out-String
    R $o
    if ($LASTEXITCODE -eq 0) { R "Бэкап: $bk" } else { R "БЭКАП НЕ УДАЛСЯ - правки отменяю. Пришли мне отчёт с Рабочего стола." }
} else { $can = $false }

# --- 5. Меню «как в MBR» ---
if ($can) {
    R ""
    R "=== 5. МЕНЮ ЗАГРУЗКИ (как раньше) ==="
    $o = & bcdedit @sa /set '{bootmgr}' displaybootmenu yes   2>&1 | Out-String; R $o
    $o = & bcdedit @sa /set '{bootmgr}' timeout 10            2>&1 | Out-String; R $o
    $o = & bcdedit @sa /set '{bootmgr}' bootmenupolicy legacy 2>&1 | Out-String; R $o
}

# --- 6. Резервный пункт (по желанию) ---
if ($can) {
    R ""
    R "=== 6. РЕЗЕРВНЫЙ ПУНКТ МЕНЮ ==="
    $a = Read-Host "Добавить второй пункт 'Windows 11 (резерв)'? [Y/N]"
    if ($a -match '^[YyДд]') {
        $o = & bcdedit @sa /copy '{current}' /d 'Windows 11 (резерв)' 2>&1 | Out-String
        R $o
        $g = [regex]::Match($o, '\{[0-9a-fA-F\-]{36}\}').Value
        if ($g) { $o = & bcdedit @sa /displayorder $g /addlast 2>&1 | Out-String; R $o; R "Пункт добавлен: $g" }
        else { R "GUID не распознан - смотри вывод выше." }
    } else { R "Пропущено." }
}

# --- 7. Итог ---
R ""
R "=== 7. ИТОГ ==="
if ($can) {
    $o = & bcdedit @sa /enum 2>&1 | Out-String; R $o
    R "============================================================"
    R " ГОТОВО. Перезагрузись: будет меню с выбором, пауза 10 сек."
    R " F8 во время загрузки = старое доброе меню доп.параметров."
    if ($ws) { R " Правки шли в файл: $ws" }
    R "============================================================"
} else {
    R "============================================================"
    R " BCD НЕ ЧИТАЕТСЯ НИ ПО ОДНОМУ ПУТИ."
    R " Отчёт на Рабочем столе: $rep"
    R " Пришли его мне - дам точечный фикс (bcdboot-пересоздание)."
    R "============================================================"
}
Write-Host ""
Write-Host "Отчёт: $rep" -ForegroundColor Cyan
