#requires -Version 5.1
<#
  PHX-HUB v1.3  (PHOENIX / H-PE11-PHOENIX project)
  Единый центр управления системой: твики, профили, устройства, энергия,
  сеть, приложения, службы, журнал с полным откатом.
  v1.2: PHX PROFILE ENGINE - движок внешних профилей по образцу TweakHub
  1.5.0 (плейбуки Version=1: Steps Tweak/Script, builtin:/custom:,
  CustomTweaks/CustomScripts), но сильнее: КОНСТИТУЦИЯ-СТРАЖ (шаги, вредные
  для HDD, блокируются с явной причиной), DRY-RUN (полный прогон без записи),
  SHA256 профиля в журнале, бэкап реестра перед каждым значением,
  откат прогона одним кликом. builtin-каталог TweakHub вшит из его
  открытых исходников. Практики мира: WinUtil/CTT, Sophia Script,
  privacy.sexy, O&O ShutUp10++. Ноль внешних зависимостей.
  v1.3: КАРТА СТАНЦИИ - методология Хозяина (карта железа + карта системы
  = полная карта территории) одним кликом: срез ОС/железа/служб/автозагрузки/
  задач/процессов/софта БЕЗ единой записи в систему, сверка HDD-конституции
  по карте (ТРЕВОГИ), диф с предыдущей картой (детект дрейфа - мировая
  практика configuration drift 2026). Карты: %ProgramData%\PHX-HUB\maps.
  PowerShell 5.1 + WPF. Каждый шаг пишется в журнал,
  каждый твик реестра заранее экспортируется в резервный .reg.
#>

param(
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- Урок TweakHub: не наследовать PSModulePath (ломает модули при запуске из PS7)
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath','Machine')

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:PhxVersion = '1.3'

# --- Элевация (практика O&O ShutUp10: самоподъём через UAC)
$wid  = [Security.Principal.WindowsIdentity]::GetCurrent()
$prp  = New-Object Security.Principal.WindowsPrincipal($wid)
$script:IsAdmin = $prp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $script:IsAdmin -and -not $NoElevate) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', ('"{0}"' -f $PSCommandPath)
        ) | Out-Null
        exit 0
    } catch {
        # пользователь отказался от UAC - продолжаем без прав (только просмотр)
        $script:IsAdmin = $false
    }
}

# --- STA-гарантия для WPF (критично: без STA XAML не построится)
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', ('"{0}"' -f $PSCommandPath)
    ) | Out-Null
    exit 0
}

# --- Папки данных
$script:Root     = Join-Path $env:ProgramData 'PHX-HUB'
$script:BackupDir= Join-Path $script:Root 'backup'
$script:JournalF = Join-Path $script:Root 'journal.jsonl'
$script:LogFile  = Join-Path $script:Root 'phx-hub.log'
foreach ($d in @($script:Root, $script:BackupDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# диск HKU: не смонтирован в PS 5.1 по умолчанию - нужен для HKU\.DEFAULT (NumLock)
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
}

# ============================================================
#  ЖУРНАЛ / ЛОГ
# ============================================================

function Write-PhxLog {
    param([string]$Msg)
    $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg)
    try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
}

function Add-PhxJournal {
    param([hashtable]$Entry)
    $Entry['ts'] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $Entry['group'] = $script:OpGroup
    try {
        Add-Content -Path $script:JournalF -Value ($Entry | ConvertTo-Json -Compress) -Encoding UTF8
    } catch {
        Write-PhxLog ('JOURNAL FAIL: ' + $_.Exception.Message)
    }
}

# группа операций (один клик = одна группа отката)
$script:OpGroup = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')

function New-PhxOpGroup { $script:OpGroup = [DateTime]::Now.ToString('yyyyMMdd-HHmmss') }

# ============================================================
#  БЭКПАП РЕЕСТРА (перед КАЖДОЙ записью - практика TweakHub)
# ============================================================

function Backup-PhxRegKey {
    param([string]$RegPath)   # например HKLM:\SOFTWARE\X\Y

    $dir = Join-Path $script:BackupDir $script:OpGroup
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

    $psPath  = $RegPath
    $regPath = $RegPath -replace '^HKLM:','HKLM'  -replace '^HKCU:','HKCU' -replace '^HKU:','HKU'

    if (-not (Test-Path $psPath)) { return $null }   # ключа нет - создавать, бэкап не нужен

    $stamp  = Get-Date -Format 'HHmmss-fff'
    $safe   = ($regPath -replace '[\\/:*?"<>| ]','_')
    if ($safe.Length -gt 120) { $safe = $safe.Substring($safe.Length-120) }
    $file   = Join-Path $dir ('{0}_{1}.reg' -f $stamp, $safe)

    try { $null = & reg.exe export $regPath $file /y 2>&1 } catch { return $null }
    if ((Test-Path $file) -and (Get-Item $file).Length -gt 0) { return $file }
    return $null
}


# ============================================================
#  ДВИЖОК: РЕЕСТР (запись с бэкапом + журнал)
# ============================================================

function Set-PhxReg {
    param(
        [string]$Path,    # HKLM:\... или HKCU:\... или HKU:\...
        [string]$Name,
        [object]$Value,
        [string]$Type = 'DWord'
    )
    $backup = Backup-PhxRegKey -RegPath $Path

    $existed = Test-Path $Path
    if (-not $existed) { New-Item -Path $Path -Force | Out-Null }

    $old = $null
    try {
        $cur = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        $old = $cur.$Name
    } catch { $old = $null }

    if ($Name -eq '(Default)') {
        # значение по умолчанию - только через reg.exe (провайдер PS его не пишет)
        $regpath = $Path -replace '^HKLM:','HKLM' -replace '^HKCU:','HKCU' -replace '^HKU:','HKU'
        $rt = 'REG_SZ'; if ($Type -eq 'ExpandString') { $rt = 'REG_EXPAND_SZ' }
        try { $null = & reg.exe add $regpath /ve /t $rt /d $Value /f 2>&1 } catch { Write-PhxLog ('REG ADD FAIL: ' + $_.Exception.Message) }
    } else {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
    Write-PhxLog ('REG SET {0} :: {1} = {2} ({3})' -f $Path, $Name, $Value, $Type)

    Add-PhxJournal -Entry @{
        kind='reg'; path=$Path; name=$Name; newv=[string]$Value; type=$Type;
        oldv=$(if ($null -ne $old) {[string]$old} else {$null});
        existed=[bool]$existed; backup=$backup
    }
}

function Remove-PhxRegKey {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $backup = Backup-PhxRegKey -RegPath $Path
    Remove-Item -Path $Path -Recurse -Force
    Write-PhxLog ('REG DEL {0}' -f $Path)
    Add-PhxJournal -Entry @{ kind='regdel'; path=$Path; backup=$backup }
}

function Restore-PhxReg {
    param($j)
    if ($j.kind -eq 'reg') {
        if ($j.backup -and (Test-Path $j.backup)) {
            $null = & reg.exe import $j.backup 2>&1
            Write-PhxLog ('REG UNDO {0} :: {1}' -f $j.path, $j.name)
        }
        elseif (-not $j.existed) {
            if ($j.name -eq '(Default)') {
                try { Remove-Item -Path $j.path -Recurse -Force -ErrorAction Stop } catch {}
            } else {
                try { Remove-ItemProperty -Path $j.path -Name $j.name -Force -ErrorAction Stop } catch {}
            }
            Write-PhxLog ('REG UNDO-DEL {0} :: {1}' -f $j.path, $j.name)
        }
        elseif ($null -ne $j.oldv) {
            if ($j.name -eq '(Default)') {
                Set-Item -Path $j.path -Value $j.oldv
            } else {
                New-ItemProperty -Path $j.path -Name $j.name -Value $j.oldv -PropertyType $j.type -Force | Out-Null
            }
        }
    }
    elseif ($j.kind -eq 'regdel') {
        if ($j.backup -and (Test-Path $j.backup)) { $null = & reg.exe import $j.backup 2>&1 }
    }
}

# ============================================================
#  ДВИЖОК: СЛУЖБЫ
# ============================================================

function Set-PhxService {
    param([string]$Name,[string]$StartType)
    $svc = Get-Service -Name $Name -ErrorAction Stop
    $old = [string]$svc.StartType
    if ($old -eq $StartType) { return }
    if ($svc.Status -eq 'Running' -and $StartType -eq 'Disabled') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
    Set-Service -Name $Name -StartupType $StartType
    Write-PhxLog ('SVC {0}: {1} -> {2}' -f $Name, $old, $StartType)
    Add-PhxJournal -Entry @{ kind='svc'; name=$Name; old=$old; new=$StartType }
}

function Restore-PhxService {
    param($j)
    try { Set-Service -Name $j.name -StartupType $j.old -ErrorAction Stop } catch {}
    Write-PhxLog ('SVC UNDO {0} -> {1}' -f $j.name, $j.old)
}

# ============================================================
#  ДВИЖОК: КОМАНДЫ (с явным откатом)
# ============================================================

function Invoke-PhxCmd {
    param([string]$Run,[string]$Undo,[string]$Desc)
    try { $null = & cmd.exe /c $Run 2>&1 } catch { Write-PhxLog ('CMD FAIL: ' + $_.Exception.Message) }
    Write-PhxLog ('CMD: {0}' -f $Desc)
    Add-PhxJournal -Entry @{ kind='cmd'; run=$Run; undo=$Undo; desc=$Desc }
}

function Restore-PhxCmd {
    param($j)
    if ($j.undo) { $null = & cmd.exe /c $j.undo 2>&1 }
    Write-PhxLog ('CMD UNDO: {0}' -f $j.desc)
}

# PowerShell-команда с журналом (откат обычно не требуется)
function Invoke-PhxCmdPS {
    param([string]$Command,[string]$Desc)
    $null = Invoke-Expression -Command $Command 2>&1
    Write-PhxLog ('CMDPS: {0}' -f $Desc)
    Add-PhxJournal -Entry @{ kind='cmdps'; run=$Command; undo=''; desc=$Desc }
}

# ============================================================
#  ДВИЖОК: DNS
# ============================================================

function Set-PhxDns {
    param([int]$IfIndex,[string[]]$Servers,[string]$IfName)
    $oldRec = Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $old = @()
    if ($oldRec) { $old = @($oldRec.ServerAddresses) }
    if ($Servers.Count -eq 0) {
        Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ResetServerAddresses
    } else {
        Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $Servers
    }
    Write-PhxLog ('DNS {0}: {1}' -f $IfName, ($Servers -join ', '))
    Add-PhxJournal -Entry @{ kind='dns'; ifindex=$IfIndex; name=$IfName; old=($old -join ' '); new=($Servers -join ' ') }
}

function Restore-PhxDns {
    param($j)
    try {
        if ([string]::IsNullOrWhiteSpace($j.old)) {
            Set-DnsClientServerAddress -InterfaceIndex ([int]$j.ifindex) -ResetServerAddresses
        } else {
            Set-DnsClientServerAddress -InterfaceIndex ([int]$j.ifindex) -ServerAddresses ($j.old -split ' ')
        }
    } catch {}
    Write-PhxLog ('DNS UNDO {0}' -f $j.name)
}

# ============================================================
#  ДВИЖОК: APPX (только текущий пользователь, честное описание)
# ============================================================

function Remove-PhxAppx {
    param([string]$PkgName)
    $pkgs = Get-AppxPackage -Name $PkgName -ErrorAction SilentlyContinue
    if (-not $pkgs) { return $false }
    foreach ($p in $pkgs) {
        try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { continue }
        Write-PhxLog ('APPX REMOVED {0}' -f $p.PackageFullName)
        Add-PhxJournal -Entry @{ kind='appx'; name=$PkgName; full=$p.PackageFullName }
    }
    return $true
}

# ============================================================
#  ПОЛНЫЙ ОТКАТ (обратный порядок журнала)
# ============================================================

function Invoke-PhxUndoAll {
    param([string]$OnlyGroup)   # $null = откатить ВСЁ
    if (-not (Test-Path $script:JournalF)) { return 0 }
    $lines = @(Get-Content -Path $script:JournalF -Encoding UTF8 | Where-Object { $_.Trim() -ne '' })
    $entries = @()
    foreach ($l in $lines) {
        try { $entries += ($l | ConvertFrom-Json) } catch {}
    }
    if ($OnlyGroup) {
        $entries = @($entries | Where-Object { $_.group -eq $OnlyGroup })
    }
    [array]::Reverse($entries)
    $done = 0
    foreach ($j in $entries) {
        try {
            switch ($j.kind) {
                'reg'    { Restore-PhxReg $j }
                'regdel' { Restore-PhxReg $j }
                'svc'    { Restore-PhxService $j }
                'cmd'    { Restore-PhxCmd $j }
                'cmdps'  { Write-PhxLog ('CMDPS UNDO (пропуск): ' + $j.desc) }
                'dns'    { Restore-PhxDns $j }
                'appx'   { Write-PhxLog ('APPX SKIP (возврат - из Microsoft Store): ' + $j.name) }
            }
        } catch {
            Write-PhxLog ('UNDO FAIL (' + $j.kind + '): ' + $_.Exception.Message)
        }
        $done++
    }
    # вычёркиваем отработанные строки из журнала
    if ($done -gt 0) {
        $out = @()
        foreach ($l in $lines) {
            try { $e = $l | ConvertFrom-Json } catch { $out += $l; continue }
            if ($OnlyGroup) {
                if ($e.group -eq $OnlyGroup) { continue }
            } else {
                continue   # откат всего - журнал пустеет
            }
            $out += $l
        }
        Set-Content -Path $script:JournalF -Value $out -Encoding UTF8
    }
    return $done
}


# ============================================================
#  КАТАЛОГ ТВНКОВ (декларативный; каждый шаг = запись в журнал)
# ============================================================

$script:Tweaks = @(
    # ---------- ПРИВАТНОСТЬ И ТЕЛЕМЕТРИЯ ----------
    @{ Id='tel0'; Group='Приватность и телеметрия'; Name='Телеметрия: минимальный уровень';
       Desc='Диагностические данные = 0 (только безопасность). Отключает задачи CEIP и службу DiagTrack.';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; n='AllowTelemetry'; t='DWord'; v=0}
         @{k='cmd'; run='schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /Disable 2>nul & schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /Disable 2>nul & exit /b 0'; undo='schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /Enable 2>nul & schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /Enable 2>nul & exit /b 0'; desc='Задачи CEIP отключены'}
         @{k='svc'; n='DiagTrack'; s='Disabled'}
       )}
    @{ Id='adv'; Group='Приватность и телеметрия'; Name='Рекламный ID: выключить';
       Desc='Приложения не смогут показывать персональную рекламу по вашему ID.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; n='Enabled'; t='DWord'; v=0}
       )}
    @{ Id='acthist'; Group='Приватность и телеметрия'; Name='Журнал действий: выключить';
       Desc='Windows перестаёт собирать историю действий и не отправляет её в облако.';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; n='EnableActivityFeed'; t='DWord'; v=0}
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; n='PublishUserActivities'; t='DWord'; v=0}
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; n='UploadUserActivities'; t='DWord'; v=0}
       )}
    @{ Id='feedback'; Group='Приватность и телеметрия'; Name='Запросы отзывов: никогда';
       Desc='Windows больше не будет спрашивать оценку и мнение.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Siuf\Rules'; n='NumberOfSIUFInPeriod'; t='DWord'; v=0}
       )}
    @{ Id='inp'; Group='Приватность и телеметрия'; Name='Персонализация ввода: выключить';
       Desc='Отключает сбор рукописного и текстового ввода, контактов для словаря.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\InputPersonalization'; n='RestrictImplicitInkCollection'; t='DWord'; v=1}
         @{k='reg'; p='HKCU:\Software\Microsoft\InputPersonalization'; n='RestrictImplicitTextCollection'; t='DWord'; v=1}
         @{k='reg'; p='HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; n='HarvestContacts'; t='DWord'; v=0}
       )}
    @{ Id='errrep'; Group='Приватность и телеметрия'; Name='Отчёты об ошибках: выключить';
       Desc='WER не отправляет отчёты в Microsoft.';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; n='Disabled'; t='DWord'; v=1}
       )}
    @{ Id='bing'; Group='Приватность и телеметрия'; Name='Веб-поиск в меню Пуск: выключить';
       Desc='Поиск в Пуске ищет только локально, без Bing и без подсказок.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Policies\Microsoft\Windows\Explorer'; n='DisableSearchBoxSuggestions'; t='DWord'; v=1}
       )}

    # ---------- ИИ / COPILOT ----------
    @{ Id='copilot'; Group='ИИ и Copilot'; Name='Copilot: выключить';
       Desc='Убирает Copilot с панели задач и блокирует его политикой.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; n='TurnOffWindowsCopilot'; t='DWord'; v=1}
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; n='TurnOffWindowsCopilot'; t='DWord'; v=1}
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='ShowCopilotButton'; t='DWord'; v=0}
       )}
    @{ Id='wai'; Group='ИИ и Copilot'; Name='Windows AI / Recall: заблокировать';
       Desc='Политикой запрещает ИИ-анализ экрана и действия ИИ-компонентов Windows.';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; n='DisableAIDataAnalysis'; t='DWord'; v=1}
         @{k='reg'; p='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; n='DisableAIDataAnalysis'; t='DWord'; v=1}
       )}

    # ---------- ИГРЫ И ПРОИЗВОДИТЕЛЬНОСТЬ ----------
    @{ Id='wps26'; Group='Игры и производительность'; Name='Планировщик CPU: приоритет активному окну';
       Desc='Win32PrioritySeparation = 0x26 - короткие кванты, усиленный форграунд (практика TweakHub).';
       Acts=@(
         @{k='reg'; p='HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; n='Win32PrioritySeparation'; t='DWord'; v=38}
       )}
    @{ Id='gamedvr'; Group='Игры и производительность'; Name='GameDVR / запись фона: выключить';
       Desc='Отключает фоновую запись игр Xbox Game Bar - освобождает ресурсы.';
       Acts=@(
         @{k='reg'; p='HKCU:\System\GameConfigStore'; n='GameDVR_Enabled'; t='DWord'; v=0}
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; n='AllowGameDVR'; t='DWord'; v=0}
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; n='AppCaptureEnabled'; t='DWord'; v=0}
       )}
    @{ Id='fso'; Group='Игры и производительность'; Name='Оптимизация во весь экран: выключить';
       Desc='Классический эксклюзивный полноэкранный режим вместо FSO (практика CTT/Atlas).';
       Acts=@(
         @{k='reg'; p='HKCU:\System\GameConfigStore'; n='GameDVR_FSEBehaviorMode'; t='DWord'; v=2}
         @{k='reg'; p='HKCU:\System\GameConfigStore'; n='GameDVR_HonorUserFSEBehaviorMode'; t='DWord'; v=1}
       )}
    @{ Id='mouse'; Group='Игры и производительность'; Name='Ускорение мыши: выключить';
       Desc='Прямое соответствие движения мыши 1:1 - стандарт киберспорта.';
       Acts=@(
         @{k='reg'; p='HKCU:\Control Panel\Mouse'; n='MouseSpeed'; t='String'; v='0'}
         @{k='reg'; p='HKCU:\Control Panel\Mouse'; n='MouseThreshold1'; t='String'; v='0'}
         @{k='reg'; p='HKCU:\Control Panel\Mouse'; n='MouseThreshold2'; t='String'; v='0'}
       )}
    @{ Id='netthr'; Group='Игры и производительность'; Name='Сетевое троттлирование: выключить';
       Desc='NetworkThrottlingIndex = 0xFFFFFFFF - медиа-трафик не душит сеть.';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; n='NetworkThrottlingIndex'; t='DWord'; v=4294967295}
       )}
    @{ Id='sysresp'; Group='Игры и производительность'; Name='Системная отзывчивость MMCSS: максимум';
       Desc='SystemResponsiveness = 0 - планировщик мультимедиа не резервирует CPU под фон.';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; n='SystemResponsiveness'; t='DWord'; v=0}
       )}
    @{ Id='hags'; Group='Игры и производительность'; Name='Планирование GPU (HAGS): включить';
       Desc='Аппаратное ускорение планирования GPU. Требуется перезагрузка.';
       Acts=@(
         @{k='reg'; p='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; n='HwSchMode'; t='DWord'; v=2}
       )}
    @{ Id='startupdelay'; Group='Игры и производительность'; Name='Задержка автозапуска приложений: 0';
       Desc='Убирает встроенную задержку Serial: старт приложений сразу после входа.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; n='StartupDelayInMSec'; t='DWord'; v=0}
       )}

    # ---------- ПРОВОДНИК И ИНТЕРФЕЙС ----------
    @{ Id='ctxmenu'; Group='Проводник и интерфейс'; Name='Классическое контекстное меню';
       Desc='Полное меню Win10 вместо урезанного Win11. Применится после перезапуска Проводника.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; n='(Default)'; t='String'; v=''}
       )}
    @{ Id='filext'; Group='Проводник и интерфейс'; Name='Расширения файлов: показывать';
       Desc='Скрывать расширения известных типов = выкл.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='HideFileExt'; t='DWord'; v=0}
       )}
    @{ Id='hidden'; Group='Проводник и интерфейс'; Name='Скрытые файлы: показывать';
       Desc='Показывать скрытые файлы и папки.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='Hidden'; t='DWord'; v=1}
       )}
    @{ Id='launchto'; Group='Проводник и интерфейс'; Name='Проводник открывать на Этот компьютер';
       Desc='Вместо Быстрого доступа.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'; n='LaunchTo'; t='DWord'; v=1}
       )}
    @{ Id='tbal'; Group='Проводник и интерфейс'; Name='Панель задач: слева (стиль Win10)';
       Desc='Выравнивание значков панели задач по левому краю.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='TaskbarAl'; t='DWord'; v=0}
       )}
    @{ Id='tbwidgets'; Group='Проводник и интерфейс'; Name='Виджеты панели: выключить';
       Desc='Убирает кнопку виджетов (погода/новости).';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='TaskbarDa'; t='DWord'; v=0}
       )}
    @{ Id='tbchat'; Group='Проводник и интерфейс'; Name='Кнопка Чат: убрать';
       Desc='Убирает кнопку чата/команд с панели задач.';
       Acts=@(
         @{k='reg'; p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='TaskbarMn'; t='DWord'; v=0}
       )}
    @{ Id='numlock'; Group='Проводник и интерфейс'; Name='NumLock при входе: включён';
       Desc='Цифровая клавиатура активна сразу после логона.';
       Acts=@(
         @{k='reg'; p='HKU:\.DEFAULT\Control Panel\Keyboard'; n='InitialKeyboardIndicators'; t='String'; v='2'}
         @{k='reg'; p='HKCU:\Control Panel\Keyboard'; n='InitialKeyboardIndicators'; t='String'; v='2'}
       )}

    # ---------- СЕТЬ ----------
    @{ Id='tcpack'; Group='Сеть и задержки'; Name='TCP-задержки: минимальные (Nagle off)';
       Desc='TcpAckFrequency=1 и TCPNoDelay=1 на активных интерфейсах - классика снижения пинга (CTT).';
       Acts=@(
         @{k='tcpack'}
       )}
    @{ Id='do0'; Group='Сеть и задержки'; Name='Delivery Optimization: выключить P2P';
       Desc='Обновления не качаются с чужих ПК и не раздаются (DODownloadMode=0).';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; n='DODownloadMode'; t='DWord'; v=0}
       )}

    # ---------- ОБНОВЛЕНИЯ ----------
    @{ Id='wudrv'; Group='Обновления'; Name='Драйверы через Windows Update: выключить';
       Desc='Качество-обновления не подтягивают драйверы (ExcludeWUDriversInQualityUpdate).';
       Acts=@(
         @{k='reg'; p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; n='ExcludeWUDriversInQualityUpdate'; t='DWord'; v=1}
       )}
)

# ---------- СЛУЖБЫ: безопасный пресет ----------
$script:SvcPreset = @(
    @{ n='DiagTrack';        d='Диагностика/телеметрия Connected User Experiences' },
    @{ n='dmwappushservice'; d='Маршрутизация WAP-сообщений (телеметрия)' },
    @{ n='MapsBroker';       d='Загрузчик карт (Downloader)' },
    @{ n='lfsvc';            d='Геолокация' },
    @{ n='RetailDemo';       d='Демо-режим магазина' },
    @{ n='WMPNetworkSvc';    d='Общий доступ WMP' },
    @{ n='RemoteRegistry';   d='Удалённый доступ к реестру' },
    @{ n='PhoneSvc';         d='Телефония (модем)' },
    @{ n='Fax';              d='Факс' }
)

# ---------- APPX: мусор (безопасный список, возврат - из Microsoft Store) ----------
$script:AppxBloat = @(
    @{ n='Microsoft.549981C3F5F10';              d='Cortana';                              def=1 },
    @{ n='MSTeams';                              d='Microsoft Teams (личный)';             def=1 },
    @{ n='MicrosoftTeams';                       d='Microsoft Teams (старый)';             def=1 },
    @{ n='Microsoft.MicrosoftOfficeHub';         d='Office-витрина (Начало работы)';       def=1 },
    @{ n='Clipchamp.Clipchamp';                  d='Clipchamp (видеоредактор)';            def=1 },
    @{ n='Microsoft.BingNews';                   d='Bing News';                            def=1 },
    @{ n='Microsoft.BingWeather';                d='Bing Weather';                         def=1 },
    @{ n='Microsoft.BingSearch';                 d='Bing Search';                          def=1 },
    @{ n='Microsoft.GetHelp';                    d='Получить помощь';                      def=1 },
    @{ n='Microsoft.GetStarted';                 d='Начало работы (советы)';               def=1 },
    @{ n='Microsoft.WindowsFeedbackHub';         d='Центр отзывов';                        def=1 },
    @{ n='Microsoft.MicrosoftSolitaireCollection';d='Пасьянсы';                            def=1 },
    @{ n='Microsoft.Microsoft3DViewer';          d='Просмотр 3D-объектов';                 def=1 },
    @{ n='Microsoft.Print3D';                    d='3D-печать';                            def=1 },
    @{ n='Microsoft.ZuneMusic';                  d='Media: музыка (Groove)';               def=1 },
    @{ n='Microsoft.ZuneVideo';                  d='Media: кино (Film&TV)';                def=1 },
    @{ n='Microsoft.PowerAutomateDesktop';       d='Power Automate';                       def=0 },
    @{ n='Microsoft.YourPhone';                  d='Связь с телефоном';                    def=0 },
    @{ n='MicrosoftCorporationII.QuickAssist';   d='Быстрая помощь (ассистент)';           def=0 }
)


# ============================================================
#  ПРИМЕНЕНИЕ ТВНКА ИЗ КАТАЛОГА
# ============================================================

function Invoke-PhxTweak {
    param($Tweak)
    foreach ($a in $Tweak.Acts) {
        switch ($a.k) {
            'reg' { Set-PhxReg -Path $a.p -Name $a.n -Value $a.v -Type $a.t }
            'svc' { Set-PhxService -Name $a.n -StartType $a.s }
            'cmd' { Invoke-PhxCmd -Run $a.run -Undo $a.undo -Desc $a.desc }
            'tcpack' {
                $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback|WAN Miniport' })
                foreach ($ad in $adapters) {
                    $key = ('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $ad.InterfaceGuid)
                    Set-PhxReg -Path $key -Name 'TcpAckFrequency' -Value 1 -Type 'DWord'
                    Set-PhxReg -Path $key -Name 'TCPNoDelay'     -Value 1 -Type 'DWord'
                }
            }
        }
    }
    Write-PhxLog ('TWEAK APPLIED: ' + $Tweak.Id)
}

# ============================================================
#  PHX PROFILE ENGINE v1.2 (PHOENIX)
#  Движок внешних профилей: плейбуки TweakHub 1.5.0 (Version=1)
#  и родные PHX-профили. Против TweakHub - четыре наших:
#   1) КОНСТИТУЦИЯ-СТРАЖ: шаги, ломающие HDD-конституцию
#      (отключение дефрагментации, SysMain/Prefetch, TRIM,
#      кэш записи, отключение диска по питанию) - БЛОКИРУЮТСЯ
#      с явной причиной, а не исполняются вслепую.
#   2) DRY-RUN: полный прогон плейбука без единой записи.
#   3) SHA256 профиля пишется в журнал (Law 4 внутри движка).
#   4) Бэкап реестра перед КАЖДЫМ значением (Backup-PhxRegKey)
#      + откат группы одним кликом (Invoke-PhxUndoAll).
#  builtin-каталог TweakHub 1.5.0 вшит из его открытых исходников
#  (TweakService.cs): каждый builtin:<slug> -> конкретные значения
#  реестра. Незнакомый builtin честно SKIP с причиной.
# ============================================================

$script:ExtProfile   = $null
$script:LastExtGroup = $null

# ---------- builtin-карта TweakHub 1.5.0 (из открытых исходников) ----------
$script:BuiltinMap = @{
  'cpu_priority_separation' = @(
    @{ p='HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; n='Win32PrioritySeparation'; t='DWord'; v=38 }
  )
  'disable_telemetry' = @(
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; n='AllowTelemetry'; t='DWord'; v=0 }
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; n='DoNotShowFeedbackNotifications'; t='DWord'; v=1 }
    @{ p='HKCU:\Software\Microsoft\Siuf\Rules'; n='NumberOfSIUFInPeriod'; t='DWord'; v=0 }
    @{ p='HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack'; n='Start'; t='DWord'; v=4 }
  )
  'disable_activity_history' = @(
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; n='EnableActivityFeed'; t='DWord'; v=0 }
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; n='PublishUserActivities'; t='DWord'; v=0 }
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; n='UploadUserActivities'; t='DWord'; v=0 }
  )
  'disable_advertising_id' = @(
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; n='Enabled'; t='DWord'; v=0 }
  )
  'disable_tailored_experiences' = @(
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; n='TailoredExperiencesWithDiagnosticDataEnabled'; t='DWord'; v=0 }
  )
  'disable_consumer_content' = @(
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; n='DisableWindowsConsumerFeatures'; t='DWord'; v=1 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SilentInstalledAppsEnabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SystemPaneSuggestionsEnabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SoftLandingEnabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SubscribedContent-338388Enabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SubscribedContent-338389Enabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SubscribedContent-353694Enabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; n='SubscribedContent-353696Enabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; n='ScoobeSystemSettingEnabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; n='Start_IrisRecommendations'; t='DWord'; v=0 }
  )
  'disable_bing_search' = @(
    @{ p='HKCU:\Software\Policies\Microsoft\Windows\Explorer'; n='DisableSearchBoxSuggestions'; t='DWord'; v=1 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; n='BingSearchEnabled'; t='DWord'; v=0 }
    @{ p='HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; n='IsDynamicSearchBoxEnabled'; t='DWord'; v=0 }
  )
  'disable_fullscreen_optimizations' = @(
    @{ p='HKCU:\System\GameConfigStore'; n='GameDVR_FSEBehaviorMode'; t='DWord'; v=2 }
  )
  'disable_game_bar' = @(
    @{ p='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; n='AppCaptureEnabled'; t='DWord'; v=0 }
  )
  'disable_animations' = @(
    @{ p='HKCU:\Control Panel\Desktop\WindowMetrics'; n='MinAnimate'; t='String'; v='0' }
  )
  'disable_transparency' = @(
    @{ p='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'; n='EnableTransparency'; t='DWord'; v=0 }
  )
  'optimize_visual_effects' = @(
    @{ p='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; n='VisualFXSetting'; t='DWord'; v=2 }
  )
  'reduce_menu_delay' = @(
    @{ p='HKCU:\Control Panel\Desktop'; n='MenuShowDelay'; t='String'; v='0' }
  )
  'disable_startup_delay' = @(
    @{ p='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; n='StartupDelayInMSec'; t='DWord'; v=0 }
  )
  'limit_background_updates' = @(
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; n='DOPercentageMaxBackgroundBandwidth'; t='DWord'; v=30 }
  )
  'disable_automatic_driver_updates' = @(
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; n='ExcludeWUDriversInQualityUpdate'; t='DWord'; v=1 }
  )
  'disable_device_coinstallers' = @(
    @{ p='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'; n='SearchOrderConfig'; t='DWord'; v=0 }
    @{ p='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer'; n='DisableCoInstallers'; t='DWord'; v=1 }
  )
  'prevent_device_metadata' = @(
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'; n='PreventDeviceMetadataFromNetwork'; t='DWord'; v=1 }
  )
  'disable_wpbt' = @(
    @{ p='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; n='DisableWpbtExecution'; t='DWord'; v=1 }
  )
  'detailed_bsod' = @(
    @{ p='HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'; n='DisplayParameters'; t='DWord'; v=1 }
  )
  'disable_fast_startup' = @(
    @{ p='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; n='HiberbootEnabled'; t='DWord'; v=0 }
  )
  'disable_windows_ai_policies' = @(
    @{ p='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; n='SettingsPageVisibility'; t='String'; v='hide:aicomponents' }
    @{ p='HKLM:\SOFTWARE\Policies\WindowsNotepad'; n='DisableAIFeatures'; t='DWord'; v=1 }
    @{ p='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; n='TurnOffWindowsCopilot'; t='DWord'; v=1 }
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; n='DisableAIDataAnalysis'; t='DWord'; v=1 }
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; n='AllowRecallEnablement'; t='DWord'; v=0 }
    @{ p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; n='DisableClickToDo'; t='DWord'; v=1 }
  )
}

# ---------- утилиты ----------
function Get-PhxSha256 {
    param([string]$Path)
    try { return (Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { return '' }
}

function Convert-PhxHivePath {
    param([string]$Path)
    $p = $Path -replace '^HKEY_LOCAL_MACHINE', 'HKLM' -replace '^HKEY_CURRENT_USER', 'HKCU' -replace '^HKEY_USERS', 'HKU'
    if ($p -notmatch ':') { $p = $p -replace '^(HKLM|HKCU|HKU)\\', '$1:\' }
    return $p
}

function Convert-PhxRegType {
    param([string]$T)
    switch ($T) {
        'REG_DWORD'     { return 'DWord' }
        'REG_QWORD'     { return 'QWord' }
        'REG_SZ'        { return 'String' }
        'REG_EXPAND_SZ' { return 'ExpandString' }
        'REG_BINARY'    { return 'Binary' }
        'REG_MULTI_SZ'  { return 'MultiString' }
        default         { return $T }
    }
}

# ---------- КОНСТИТУЦИЯ-СТРАЖ ----------
# Возвращает $null если шаг чист, иначе строку-причину блокировки.
function Test-PhxConstitution {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.ToLowerInvariant()

    # 1) Дефрагментация: отключать НЕЛЬЗЯ (HDD 7200rpm живёт на дефрагментаторе)
    if ($t -match 'defrag' -and $t -match 'disabl|stop|turn\s*off|\/disable') {
        return 'HDD-конституция: отключение дефрагментации запрещено (Seagate HDD 7200.12 - дефрагментатор нужен)'
    }

    # 2) SysMain / Superfetch: НЕ отключать (на HDD помогают)
    if ($t -match 'sysmain|superfetch' -and $t -match 'disabl|stop|start\s*[=:]\s*4|turn\s*off') {
        return 'HDD-конституция: SysMain/Superfetch на HDD помогает - отключение запрещено'
    }
    if ($t -match 'enable(prefetcher|superfetch|sysmain)[^0-9]*0\b') {
        return 'HDD-конституция: Prefetch/SysMain на HDD помогает - выключение запрещено'
    }

    # 3) TRIM: физически не поддерживается диском
    if ($t -match 'disabledeletenotify\s*[=: ]\s*(1|true|on)\b') {
        return 'HDD-конституция: TRIM-твики не применять - диск TRIM не поддерживает'
    }

    # 4) Кэш записи: не трогать
    if ($t -match 'write\s*cache' -and $t -match 'disabl|turn\s*off|\b0\b') {
        return 'HDD-конституция: кэш записи диска не трогать'
    }

    # 5) Диск от питания не отключать
    if ($t -match 'turnoffharddisk|turn\s*off\s*hard\s*disk') {
        return 'HDD-конституция: диск от питания не отключать'
    }
    $m = [regex]::Match($t, 'disk[-_ ]?timeout[-_ ]?(ac|dc)?\s*[=: ]\s*([1-9][0-9]*)')
    if ($m.Success) {
        return ('HDD-конституция: диск от питания не отключать (disk timeout = {0})' -f $m.Groups[2].Value)
    }

    return $null
}

# ---------- ИМПОРТ ПРОФИЛЯ ----------
# Понимает два формата:
#  A) плейбук TweakHub 1.5.0: { Version:1, Playbook:{ Steps[] }, CustomTweaks[], CustomScripts[] }
#     Type 0 = Tweak (builtin:<slug> | custom:<id>), Type 2 = Script (PS inline)
#  B) родной PHX-профиль: { ver, tweaks[], appx[] } (id из каталога PHX-HUB)
function Import-PhxExternalProfile {
    param([string]$JsonPath)
    if (-not (Test-Path $JsonPath)) { throw ('Файл не найден: ' + $JsonPath) }
    $sha = Get-PhxSha256 -Path $JsonPath
    $raw = [System.IO.File]::ReadAllText($JsonPath)
    $j = $raw | ConvertFrom-Json
    $steps = New-Object System.Collections.ArrayList

    $isTh  = ($null -ne $j.PSObject.Properties['Version'] -and $null -ne $j.PSObject.Properties['Playbook'])
    $isPhx = ($null -ne $j.PSObject.Properties['tweaks'])

    if ($isTh) {
        $pb = $j.Playbook
        $customT = @{}
        foreach ($c in @($j.CustomTweaks))  { if ($c) { $customT[$c.Id] = $c } }
        $customS = @{}
        foreach ($s in @($j.CustomScripts)) { if ($s) { $customS[$s.Id] = $s } }

        foreach ($st in @($pb.Steps)) {
            $title = [string]$st.Name
            $kind = 'skip'; $detail = ''; $why = ''; $payload = $null
            $ref = [string]$st.ReferenceId

            if ($st.Type -eq 0 -and $ref.StartsWith('custom:')) {
                $cid = $ref.Substring(7)
                if ($customT.ContainsKey($cid)) {
                    $c = $customT[$cid]
                    $rt = Convert-PhxRegType -T ([string]$c.ValueType)
                    if ($rt -eq 'Binary' -or $rt -eq 'MultiString') {
                        $why = ('тип значения {0} движком не исполняется' -f $rt)
                    } else {
                        $v = $c.Data
                        if ($rt -eq 'DWord' -or $rt -eq 'QWord') {
                            $iv = [long]0
                            if ([long]::TryParse([string]$v, [ref]$iv)) {
                                if ($iv -lt 0 -and $rt -eq 'DWord') { $iv = $iv + 4294967296 }
                                $v = $iv
                            }
                        }
                        $payload = @(@{ p=(Convert-PhxHivePath -Path ([string]$c.RegistryPath)); n=[string]$c.RegistryKey; t=$rt; v=$v })
                        $kind = 'reg'
                        $detail = ('{0} :: {1} = {2} ({3})' -f $c.RegistryPath, $c.RegistryKey, $c.Data, $c.ValueType)
                    }
                } else { $why = 'custom-твик отсутствует в теле плейбука' }
            }
            elseif ($st.Type -eq 0 -and $ref.StartsWith('builtin:')) {
                $slug = $ref.Substring(8)
                if ($script:BuiltinMap.ContainsKey($slug) -and @($script:BuiltinMap[$slug]).Count -gt 0) {
                    $kind = 'builtin'
                    $payload = @($script:BuiltinMap[$slug])
                    $detail = ('builtin:{0} -> {1} значений реестра' -f $slug, @($script:BuiltinMap[$slug]).Count)
                } else {
                    $why = ('builtin-твик "{0}" не в карте движка - исполняется только самим TweakHub' -f $slug)
                }
            }
            elseif ($st.Type -eq 2) {
                if ($customS.ContainsKey($ref)) {
                    $sc = $customS[$ref]
                    if ([int]$sc.Language -eq 0) {
                        $kind = 'script'
                        $payload = [string]$sc.Content
                        $detail = ('PowerShell-скрипт, {0} символов' -f $payload.Length)
                    } else {
                        $why = 'скрипт не PowerShell - движком не исполняется'
                    }
                } else { $why = 'скрипт отсутствует в теле плейбука' }
            }
            elseif ($st.Type -eq 1) {
                $why = ('winget-шаг ({0}) движком не исполняется' -f [string]$st.WingetId)
            }
            else { $why = ('неизвестный тип шага: {0}' -f $st.Type) }

            if ($st.TargetEnabled -eq $false) {
                $kind = 'skip'; $payload = $null; $why = 'в плейбуке помечен TargetEnabled=false'
            }

            $status = 'OK'
            if ($kind -eq 'skip') { $status = 'SKIP' }
            else {
                $sig = $title + ' ' + $detail
                if ($kind -eq 'script') { $sig += ' ' + $payload }
                else { foreach ($a in $payload) { $sig += (' {0} :: {1} = {2}' -f $a.p, $a.n, $a.v) } }
                $g = Test-PhxConstitution -Text $sig
                if ($g) { $status = 'BLOCK'; $why = $g; $payload = $null }
            }
            [void]$steps.Add(@{ Idx=($steps.Count + 1); Kind=$kind; Title=$title; Detail=$detail; Status=$status; Reason=$why; Payload=$payload })
        }
        return @{ Name=[string]$pb.Name; Desc=[string]$pb.Description; Sha=$sha; Source=(Split-Path $JsonPath -Leaf); Steps=$steps.ToArray() }
    }
    elseif ($isPhx) {
        foreach ($id in @($j.tweaks)) {
            $t = $script:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
            $kind = 'our'; $detail = ''; $why = ''; $payload = $t
            $grpName = '?'
            if ($null -eq $t) {
                $kind = 'skip'; $payload = $null
                $why = ('твик "{0}" не найден в каталоге этой версии PHX-HUB' -f $id)
            } else {
                $grpName = [string]$t.Group
                $detail = ('{0}: {1} действий' -f $t.Name, @($t.Acts).Count)
            }
            $status = 'OK'; if ($kind -eq 'skip') { $status = 'SKIP' }
            [void]$steps.Add(@{
                Idx = ($steps.Count + 1); Kind = $kind
                Title = ('{0}  [{1}]' -f $id, $grpName); Detail = $detail
                Status = $status; Reason = $why; Payload = $payload
            })
        }
        foreach ($nm in @($j.appx)) {
            [void]$steps.Add(@{
                Idx = ($steps.Count + 1); Kind = 'appx'
                Title = ('Удалить Store-приложение: {0}' -f $nm)
                Detail = 'возврат - Microsoft Store'
                Status = 'OK'; Reason = ''; Payload = [string]$nm
            })
        }
        if ($j.PSObject.Properties['services'] -and $null -ne $j.services) {
            foreach ($sv in @($j.services)) {
            if ($null -eq $sv) { continue }
            $sn = [string]$sv.name; $ss = [string]$sv.start
            $known = ($script:SvcPreset | Where-Object { $_.n -eq $sn } | Select-Object -First 1)
            $kind = 'svc'; $why = ''; $payload = @{ Name = $sn; Start = $ss }
            if ($null -eq $known) {
                $kind = 'skip'; $payload = $null
                $why = ('служба вне безопасного списка: {0}' -f $sn)
            }
            elseif ($ss -ne 'Automatic' -and $ss -ne 'Manual' -and $ss -ne 'Disabled') {
                $kind = 'skip'; $payload = $null
                $why = ('служба {0}: тип {1} запрещён' -f $sn, $ss)
            }
            $status = 'OK'
            if ($kind -eq 'skip') { $status = 'SKIP' }
            else {
                $g = Test-PhxConstitution -Text ('службе {0} ставим тип запуска {1}' -f $sn, $ss)
                if ($g) { $status = 'BLOCK'; $why = $g; $payload = $null }
            }
            [void]$steps.Add(@{
                Idx = ($steps.Count + 1); Kind = $kind
                Title = ('Служба {0} -> {1}' -f $sn, $ss)
                Detail = $(if ($known) { [string]$known.d } else { '' })
                Status = $status; Reason = $why; Payload = $payload
            })
            }
        }
        return @{ Name=('PHX-профиль: {0}' -f (Split-Path $JsonPath -Leaf)); Desc=('вер={0}, хост={1}' -f $j.ver, $j.host); Sha=$sha; Source=(Split-Path $JsonPath -Leaf); Steps=$steps.ToArray() }
    }
    else { throw 'Формат не распознан: это не плейбук TweakHub (Version/Playbook) и не PHX-профиль (tweaks)' }
}

# ---------- ИСПОЛНЕНИЕ ШАГА ----------
function Invoke-PhxExtStep {
    param($Step)
    switch ($Step.Kind) {
        'reg' {
            foreach ($a in @($Step.Payload)) { Set-PhxReg -Path $a.p -Name $a.n -Value $a.v -Type $a.t }
        }
        'builtin' {
            foreach ($a in @($Step.Payload)) { Set-PhxReg -Path $a.p -Name $a.n -Value $a.v -Type $a.t }
        }
        'our'  { Invoke-PhxTweak -Tweak $Step.Payload }
        'appx' { [void](Remove-PhxAppx -PkgName ([string]$Step.Payload)) }
        'svc'  { Set-PhxService -Name $Step.Payload.Name -StartType $Step.Payload.Start }
        'script' {
            Write-PhxLog ('EXT SCRIPT START: ' + $Step.Title)
            $oldEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { Invoke-Expression -Command $Step.Payload } catch { Write-PhxLog ('EXT SCRIPT ERR: ' + $_.Exception.Message) }
            $ErrorActionPreference = $oldEap
            Add-PhxJournal -Entry @{ kind='cmdps'; run='<external playbook script>'; undo=''; desc=('Плейбук: ' + $Step.Title) }
        }
    }
}

# ---------- ПРОГОН ПРОФИЛЯ ----------
# -Dry: полный прогон БЕЗ единой записи (ни реестр, ни журнал).
# Реальный прогон: одна группа отката (New-PhxOpGroup), запись 'extrun'
# в журнал с SHA256 профиля, каждый reg-шаг - с бэкапом (Set-PhxReg).
function Invoke-PhxExtProfile {
    param($Prof, [switch]$Dry)
    New-PhxOpGroup
    $grp = $script:OpGroup
    if (-not $Dry) {
        $script:LastExtGroup = $grp
        Add-PhxJournal -Entry @{ kind='extrun'; profile=$Prof.Name; sha=$Prof.Sha; steps=@($Prof.Steps).Count }
    }
    $ok = 0; $skip = 0; $block = 0; $fail = 0
    foreach ($st in @($Prof.Steps)) {
        if ($st.Status -eq 'SKIP')  { $skip++;  continue }
        if ($st.Status -eq 'BLOCK') { $block++; continue }
        try {
            if (-not $Dry) {
                Set-Status ('Шаг {0}: {1}...' -f $st.Idx, $st.Title)
                Invoke-PhxExtStep -Step $st
            }
            $ok++
        } catch {
            $fail++
            Write-PhxLog ('EXT STEP FAIL: ' + $st.Title + ' :: ' + $_.Exception.Message)
        }
    }
    return [pscustomobject]@{ Ok=$ok; Skip=$skip; Block=$block; Fail=$fail; Group=$grp }
}

# ============================================================
#  ТОЧКА ВОССТАНОВЛЕНИЯ (практика O&O: перед массовыми делами)
# ============================================================

function New-PhxRestorePoint {
    try {
        $sr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        Set-PhxReg -Path $sr -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type 'DWord'
        Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description ('PHX-HUB v' + $script:PhxVersion) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        return $true
    } catch {
        Write-PhxLog ('RPOINT FAIL: ' + $_.Exception.Message)
        return $false
    }
}

# ============================================================
#  ПРОВЕРКА БЕЗОПАСНОСТИ (скор + фиксы; практика TweakHub Security)
# ============================================================

function Get-PhxSecurityChecks {
    $checks = New-Object System.Collections.ArrayList

    # 1. UAC
    $uac = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue)
    $ok = ($null -ne $uac -and $uac.EnableLUA -eq 1)
    [void]$checks.Add(@{ Id='uac'; Name='UAC включён'; Ok=$ok; Info=('EnableLUA=' + $uac.EnableLUA);
        FixType='reg'; FixPath='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; FixName='EnableLUA'; FixVal=1; FixDesc='UAC будет включён (нужен выход из системы)' })

    # 2-3. Defender
    $def = $null
    try { $def = Get-MpComputerStatus -ErrorAction Stop } catch {}
    $okRTP = ($null -ne $def -and $def.RealTimeProtectionEnabled)
    [void]$checks.Add(@{ Id='defrt'; Name='Defender: реальная защита'; Ok=$okRTP; Info=$(if($def){'RTP: '+$def.RealTimeProtectionEnabled}else{'Defender недоступен'}); FixType=$null })
    $okSig = ($null -ne $def -and $def.AntivirusSignatureAge -le 7)
    [void]$checks.Add(@{ Id='defsig'; Name='Defender: свежие сигнатуры (до 7 дн.)'; Ok=$okSig; Info=$(if($def){'возраст: '+$def.AntivirusSignatureAge+' дн.'}else{'-'}); FixType='cmd2'; FixCmd='"%ProgramFiles%\Windows Defender\MpCmdRun.exe" -SignatureUpdate'; FixDesc='Обновить сигнатуры Defender' })

    # 4. SmartScreen
    $ss = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -ErrorAction SilentlyContinue)
    $ok = ($null -ne $ss -and $ss.EnableSmartScreen -ne 0)
    [void]$checks.Add(@{ Id='ss'; Name='SmartScreen включён'; Ok=$ok; Info=('EnableSmartScreen=' + $ss.EnableSmartScreen);
        FixType='reg'; FixPath='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; FixName='EnableSmartScreen'; FixVal=1; FixDesc='SmartScreen включён' })

    # 5. Firewall
    $ok = $false; $info = '-'
    try {
        $fw = @(Get-NetFirewallProfile -ErrorAction Stop)
        $ok = ($fw.Count -gt 0 -and (@($fw | Where-Object { -not $_.Enabled })).Count -eq 0)
        $info = (@($fw | ForEach-Object { '{0}={1}' -f $_.Name, $_.Enabled }) -join ' ')
    } catch { $info = 'недоступен' }
    [void]$checks.Add(@{ Id='fw'; Name='Брандмауэр: все профили активны'; Ok=$ok; Info=$info; FixType='cmdps'; FixCmd='Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled True'; FixDesc='Все профили брандмауэра включены' })

    # 6. RDP (выключен = ок; включён = только с NLA)
    $rdp = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue)
    $ok = $true; $info = 'RDP выключен'
    if ($null -ne $rdp -and $rdp.fDenyTSConnections -eq 0) {
        $nla = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue)
        if ($nla -and $nla.UserAuthentication -eq 1) { $info = 'RDP включён, NLA включён' }
        else { $ok = $false; $info = 'RDP включён БЕЗ NLA!' }
    }
    [void]$checks.Add(@{ Id='rdp'; Name='RDP: выключен или с NLA'; Ok=$ok; Info=$info; FixType=$null })

    # 7. SMBv1
    $ok = $false; $info = '-'
    try { $smb = Get-SmbServerConfiguration -ErrorAction Stop; $ok = (-not $smb.EnableSMB1Protocol); $info = ('SMB1=' + $smb.EnableSMB1Protocol) } catch { $info = 'недоступно' }
    [void]$checks.Add(@{ Id='smb1'; Name='SMBv1 отключён (дыра WannaCry)'; Ok=$ok; Info=$info;
        FixType='cmdps'; FixCmd='Set-SmbServerConfiguration -EnableSMB1Protocol $false -Confirm:$false -Force'; FixDesc='SMBv1 отключён' })

    # 8. LLMNR
    $llmnr = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -ErrorAction SilentlyContinue)
    $ok = ($null -ne $llmnr -and $llmnr.EnableMulticast -eq 0)
    [void]$checks.Add(@{ Id='llmnr'; Name='LLMNR отключён (защита от перехвата)'; Ok=$ok; Info=$(if($ok){'EnableMulticast=0'}else{'LLMNR активен'});
        FixType='reg'; FixPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; FixName='EnableMulticast'; FixVal=0; FixDesc='LLMNR отключён политикой' })

    # 9. PowerShell 2.0
    $ok = $false; $info = '-'
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName 'MicrosoftWindowsPowerShellV2' -ErrorAction Stop
        $ok = ($f.State -eq 'Disabled'); $info = $f.State
    } catch { $info = 'недоступно' }
    [void]$checks.Add(@{ Id='ps2'; Name='PowerShell 2.0 отключён (устаревший)'; Ok=$ok; Info=$info;
        FixType='cmdps'; FixCmd='Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2 -NoRestart'; FixDesc='PowerShell 2.0 отключён (без перезагрузки)' })

    # 10. Гостевая учётка
    $ok = $true; $info = 'Гость отключён'
    try {
        $gu = Get-LocalUser -Name 'Guest' -ErrorAction Stop
        $ok = (-not $gu.Enabled); $info = ('Guest Enabled=' + $gu.Enabled)
    } catch { $info = 'недоступно' }
    [void]$checks.Add(@{ Id='guest'; Name='Учётка Гость отключена'; Ok=$ok; Info=$info; FixType=$null })

    # 11. SecureBoot (информационно - на Legacy BIOS неприменимо)
    $sb = 'N/A'; $okSB = $null
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { $sb = 'BIOS Legacy - неприменимо' }
    if ($sb -is [bool]) { $okSB = $sb } 
    [void]$checks.Add(@{ Id='sb'; Name='Secure Boot'; Ok=$okSB; Info=[string]$sb; FixType=$null })

    return ,$checks.ToArray()
}

# ============================================================
#  ПЛЕЙБУКИ (профили одним кликом)
# ============================================================

$script:Playbooks = @(
    @{ Id='PRIVACY_MAX'; Name='МАКС-ПРИВАТНОСТЬ'; Desc='Телемерия 0, реклама, история, ввод, ошибки, Copilot, Windows AI, веб-поиск';
       Tweaks=@('tel0','adv','acthist','feedback','inp','errrep','bing','copilot','wai') },
    @{ Id='GAMING';      Name='ИГРОВОЙ';          Desc='CPU-планировщик, GameDVR off, FSO off, мышь 1:1, сеть без троттла, MMCSS, TCP-задержки';
       Tweaks=@('wps26','gamedvr','fso','mouse','netthr','sysresp','tcpack','startupdelay') },
    @{ Id='SPEED';       Name='МАКС-СКОРОСТЬ';    Desc='CPU-планировщик, автозапуск без задержки, DO off, драйверы WU off';
       Tweaks=@('wps26','startupdelay','do0','wudrv') },
    @{ Id='CLEANBLOAT';  Name='ЧИСТКА МУСОРА';    Desc='Удаление предустановленного мусора Store (Cortana, Teams, Clipchamp, Bing-набор и т.д.)';
       Apps=@('Microsoft.549981C3F5F10','MSTeams','MicrosoftTeams','Microsoft.MicrosoftOfficeHub','Clipchamp.Clipchamp','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch','Microsoft.GetHelp','Microsoft.GetStarted','Microsoft.WindowsFeedbackHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.Microsoft3DViewer','Microsoft.ZuneMusic','Microsoft.ZuneVideo') },
    @{ Id='QOL';         Name='КОМФОРТ ПРОВОДНИКА'; Desc='Классическое меню, расширения, скрытые файлы, Этот компьютер, панель слева, NumLock';
       Tweaks=@('ctxmenu','filext','hidden','launchto','tbal','numlock') }
)

# ============================================================
#  v1.2: ПРОФИЛЬНЫЙ ДВИЖОК (TweakHub-стиль, наш)
#  Профиль JSON: ver 1.0/1.1 { name, tweaks[], appx[], services:[{name,start}] }
# ============================================================
#  КАРТА СТАНЦИИ (v1.3): полная карта территории одним кликом
#  НОЛЬ записей в систему: карта - только чтение (как AIDA64).
#  Синтез практик: configuration drift detection (baseline vs live,
#  2026), CIS-подход (базлайн у нас = HDD-конституция), PS-инвентаризация
#  служб/задач/автозапуска. Файлы карты: JSON + TXT + SHA256 (Law 4).
# ============================================================
#>>>MAP
$script:MapDir = Join-Path $env:ProgramData 'PHX-HUB\maps'

function Get-PhxMap {
    # Сбор карты живой системы (только чтение)
    $r = [ordered]@{}
    $os = Get-CimInstance Win32_OperatingSystem
    $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -ErrorAction SilentlyContinue).UBR
    $r.os = [ordered]@{ caption=[string]$os.Caption; version=[string]$os.Version; build=[string]$os.BuildNumber; ubr=$ubr }
    $r.boot = ('{0}' -f $os.LastBootUpTime)
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $r.cpu = [ordered]@{ name=[string]$cpu.Name.Trim(); cores=[int]$cpu.NumberOfCores; threads=[int]$cpu.NumberOfLogicalProcessors; mhz=[int]$cpu.MaxClockSpeed }
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $r.ram = [ordered]@{ totalMB=[int](($ram | Measure-Object Capacity -Sum).Sum/1MB); modules=@($ram | ForEach-Object { [ordered]@{ loc=[string]$_.DeviceLocator; maker=[string]$_.Manufacturer; part=[string]$_.PartNumber; mb=[int]($_.Capacity/1MB); mhz=[int]$_.Speed } }) }
    $r.gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { [ordered]@{ name=[string]$_.Name; driver=[string]$_.DriverVersion; date=[string]$_.DriverDate } })
    $r.disks = @(Get-CimInstance Win32_DiskDrive | ForEach-Object { [ordered]@{ model=[string]$_.Model.Trim(); sn=([string]$_.SerialNumber -replace '\s',''); gb=[int]($_.Size/1GB); iface=[string]$_.InterfaceType } })
    $r.volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { [ordered]@{ letter=[string]$_.DeviceID; fs=[string]$_.FileSystem; gb=[math]::Round($_.Size/1GB,1); freeGb=[math]::Round($_.FreeSpace/1GB,1) } })
    $r.net = @(Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True AND NetEnabled=True' | ForEach-Object { [ordered]@{ name=[string]$_.Name.Trim(); mac=[string]$_.MACAddress; mbps=[int]($_.Speed/1000000) } })
    $r.services = @(Get-Service | ForEach-Object { [ordered]@{ n=[string]$_.Name; s=[string]$_.Status; t=[string]$_.StartType } })
    $r.tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ p=[string]$_.TaskPath; n=[string]$_.TaskName; st=[string]$_.State } })
    $rr = @()
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        if (Test-Path $k) {
            $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')) {
                    $rr += [ordered]@{ src=$k; name=[string]$prop.Name; val=[string]$prop.Value }
                }
            }
        }
    }
    $r.run = $rr
    $r.topProc = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 | ForEach-Object { [ordered]@{ name=[string]$_.ProcessName; mb=[int]($_.WorkingSet64/1MB) } })
    $soft = @()
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $soft += @(Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object { [ordered]@{ name=[string]$_.DisplayName; ver=[string]$_.DisplayVersion } })
    }
    $r.software = @($soft | Sort-Object { $_.name } -Unique)
    return $r
}

function Test-PhxMapConstitution {
    # Сверка карты с HDD-конституцией (базлайн проекта, подход CIS)
    param($Map)
    $out = @()
    $sm = $Map.services | Where-Object { $_.n -eq 'SysMain' } | Select-Object -First 1
    if ($sm) {
        if ([string]$sm.t -eq 'Disabled') {
            $out += 'ТРЕВОГА|SysMain: тип запуска Disabled - нарушение HDD-конституции (на этом HDD SysMain ПОМОГАЕТ). Вернуть: sc config SysMain start= auto'
        } elseif ([string]$sm.s -eq 'Stopped') {
            $out += 'ВНИМАНИЕ|SysMain: остановлена (тип {0}) - запуск программ с HDD может быть вялым. Проверить: sc query SysMain' -f $sm.t
        } else {
            $out += 'OK|SysMain: {0}, {1} - конституция соблюдена' -f $sm.s, $sm.t
        }
    }
    $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name EnablePrefetcher -ErrorAction SilentlyContinue).EnablePrefetcher
    if ($null -eq $pf) { $out += 'СВЕДЕНИЕ|EnablePrefetcher: значение не задано (умолчание Windows = 3)' }
    elseif ($pf -eq 0) { $out += 'ТРЕВОГА|EnablePrefetcher = 0: Prefetcher выключен - нарушение HDD-конституции. Вернуть значение 3' }
    else { $out += 'OK|EnablePrefetcher = {0} (3 - оптимально для HDD)' -f $pf }
    $df = $Map.tasks | Where-Object { $_.p -eq '\Microsoft\Windows\Defrag\' -and $_.n -eq 'ScheduledDefrag' } | Select-Object -First 1
    if ($df) {
        if ([string]$df.st -eq 'Disabled') { $out += 'ТРЕВОГА|ScheduledDefrag: отключена - нарушение HDD-конституции (HDD ждёт дефрагментацию по расписанию)' }
        else { $out += 'OK|ScheduledDefrag: {0}' -f $df.st }
    }
    $ws = $Map.services | Where-Object { $_.n -eq 'WSearch' } | Select-Object -First 1
    if ($ws -and [string]$ws.t -eq 'Disabled') { $out += 'ВНИМАНИЕ|WSearch: Disabled - без индекса поиск медленный, но HDD щадится (решение за Хозяином)' }
    return $out
}

function Get-PhxMapDiff {
    # Детект дрейфа: текущая карта против предыдущей (configuration drift)
    param($Map, $PrevMap)
    if (-not $PrevMap) { return @('СВЕДЕНИЕ|Предыдущей карты нет - дрейф считается с этого среза') }
    $out = @()
    $prevSvc = @{}; foreach ($s in $PrevMap.services) { $prevSvc[$s.n] = ('{0}|{1}' -f $s.s, $s.t) }
    $curSvc = @{}; foreach ($s in $Map.services) { $curSvc[$s.n] = ('{0}|{1}' -f $s.s, $s.t) }
    $new = @($curSvc.Keys | Where-Object { -not $prevSvc.ContainsKey($_) } | Sort-Object)
    $gone = @($prevSvc.Keys | Where-Object { -not $curSvc.ContainsKey($_) } | Sort-Object)
    $chg = @($curSvc.Keys | Where-Object { $prevSvc.ContainsKey($_) -and $prevSvc[$_] -ne $curSvc[$_] } | Sort-Object)
    if ($new.Count) { $out += 'ДРЕЙФ|Службы появились: {0}' -f (($new | Select-Object -First 8) -join ', ') }
    if ($gone.Count) { $out += 'ДРЕЙФ|Службы исчезли: {0}' -f (($gone | Select-Object -First 8) -join ', ') }
    foreach ($c in ($chg | Select-Object -First 12)) { $out += 'ДРЕЙФ|Служба {0}: {1} -> {2}' -f $c, ($prevSvc[$c] -replace '\|', '/'), ($curSvc[$c] -replace '\|', '/') }
    $prevRun = @($PrevMap.run | ForEach-Object { [string]$_.name + '=' + [string]$_.val })
    $curRun = @($Map.run | ForEach-Object { [string]$_.name + '=' + [string]$_.val })
    foreach ($a in @($curRun | Where-Object { $prevRun -notcontains $_ })) { $out += 'ДРЕЙФ|Автозагрузка +: ' + $a }
    foreach ($r2 in @($prevRun | Where-Object { $curRun -notcontains $_ })) { $out += 'ДРЕЙФ|Автозагрузка -: ' + $r2 }
    return $out
}

function Invoke-PhxMapCapture {
    # Оркестр: сбор -> конституция -> дрейф -> файлы (JSON+TXT+SHA256) -> журнал
    Set-Status 'Снятие карты станции (только чтение)...'
    try {
        $map = Get-PhxMap
        $now = Get-Date
        $stamp = $now.ToString('yyyyMMdd-HHmmss')
        if (-not (Test-Path $script:MapDir)) { New-Item -Path $script:MapDir -ItemType Directory -Force | Out-Null }
        $prev = $null
        $prevFile = Get-ChildItem $script:MapDir -Filter 'map-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($prevFile) { try { $prev = Get-Content $prevFile.FullName -Raw | ConvertFrom-Json } catch { $prev = $null } }
        $const = @(Test-PhxMapConstitution -Map $map)
        $diff = @(Get-PhxMapDiff -Map $map -PrevMap $prev)
        $mapObj = [ordered]@{ ver=$script:PhxVersion; host=$env:COMPUTERNAME; user=$env:USERNAME; stamp=$now.ToString('yyyy-MM-dd HH:mm:ss'); map=$map }
        $json = ($mapObj | ConvertTo-Json -Depth 6)
        $jsonPath = Join-Path $script:MapDir ('map-{0}.json' -f $stamp)
        [IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $sha = (Get-FileHash $jsonPath -Algorithm SHA256).Hash
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine(('PHX-HUB v{0} - КАРТА СТАНЦИИ (карта железа + карта системы = полная карта территории)' -f $script:PhxVersion))
        [void]$sb.AppendLine(('Снята: {0} | ПК: {1} | юзер: {2}' -f $mapObj.stamp, $mapObj.host, $mapObj.user))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== ЖЕЛЕЗО ==')
        [void]$sb.AppendLine(('CPU: {0} ({1}C/{2}T, {3} МГц)' -f $map.cpu.name, $map.cpu.cores, $map.cpu.threads, $map.cpu.mhz))
        [void]$sb.AppendLine(('RAM: {0} МБ ({1})' -f $map.ram.totalMB, (($map.ram.modules | ForEach-Object { '{0}: {1} {2} МБ {3} МГц' -f $_.loc, $_.maker, $_.mb, $_.mhz }) -join '; ')))
        foreach ($g in $map.gpu) { [void]$sb.AppendLine(('GPU: {0} | драйвер {1} ({2})' -f $g.name, $g.driver, $g.date)) }
        foreach ($d in $map.disks) { [void]$sb.AppendLine(('Диск: {0} | SN {1} | {2} ГБ | {3}' -f $d.model, $d.sn, $d.gb, $d.iface)) }
        foreach ($v in $map.volumes) { [void]$sb.AppendLine(('Том: {0} {1} | {2} ГБ, свободно {3} ГБ' -f $v.letter, $v.fs, $v.gb, $v.freeGb)) }
        foreach ($n in $map.net) { [void]$sb.AppendLine(('Сеть: {0} | MAC {1} | {2} Мбит/с' -f $n.name, $n.mac, $n.mbps)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== ОС ==')
        [void]$sb.AppendLine(('{0}, билд {1}.{2}' -f $map.os.caption, $map.os.build, $map.os.ubr))
        [void]$sb.AppendLine(('Загрузка ОС: {0}' -f $map.boot))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('== СЛУЖБЫ ({0}) ==' -f $map.services.Count))
        foreach ($s in $map.services) { [void]$sb.AppendLine(('{0,-34} {1,-13} {2}' -f $s.n, $s.s, $s.t)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('== АВТОЗАГРУЗКА ({0}) ==' -f $map.run.Count))
        foreach ($x in $map.run) { [void]$sb.AppendLine(('{0} = {1}' -f $x.name, $x.val)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('== ЗАДАЧИ: всего {0}; активных (не Disabled): {1} ==' -f $map.tasks.Count, @($map.tasks | Where-Object { $_.st -ne 'Disabled' }).Count))
        foreach ($t in ($map.tasks | Where-Object { $_.st -ne 'Disabled' })) { [void]$sb.AppendLine(('{0}{1} [{2}]' -f $t.p, $t.n, $t.st)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== ПРОЦЕССЫ ТОП-15 (память) ==')
        foreach ($p in $map.topProc) { [void]$sb.AppendLine(('{0,-30} {1} МБ' -f $p.name, $p.mb)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('== СОФТ ({0}) ==' -f $map.software.Count))
        foreach ($s in $map.software) { [void]$sb.AppendLine(('{0} {1}' -f $s.name, $s.ver)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== СВЕРКА HDD-КОНСТИТУЦИИ ==')
        foreach ($c in $const) { [void]$sb.AppendLine('  ' + ($c -replace '\|', ': ')) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== ДРЕЙФ С ПРЕДЫДУЩЕЙ КАРТОЙ ==')
        if ($diff.Count -eq 0) { [void]$sb.AppendLine('  изменений нет') } else { foreach ($c in $diff) { [void]$sb.AppendLine('  ' + ($c -replace '\|', ': ')) } }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('SHA256 карты (JSON): {0}' -f $sha))
        [void]$sb.AppendLine(('Файл карты: {0}' -f $jsonPath))
        $txtPath = Join-Path $script:MapDir ('map-{0}.txt' -f $stamp)
        [IO.File]::WriteAllText($txtPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
        $alerts = @($const | Where-Object { $_.StartsWith('ТРЕВОГА') }).Count
        Write-PhxLog ('КАРТА СТАНЦИИ: {0} (служб {1}, автозап {2}, задач {3}, софта {4}); ТРЕВОГ конституции: {5}; SHA256 {6}' -f $stamp, $map.services.Count, $map.run.Count, $map.tasks.Count, $map.software.Count, $alerts, $sha.Substring(0,16))
        Set-Status ('Карта снята: {0}. ТРЕВОГ конституции: {1}' -f $stamp, $alerts)
        $sum = New-Object System.Text.StringBuilder
        [void]$sum.AppendLine(('КАРТА СТАНЦИИ СНЯТА: {0}' -f $stamp))
        [void]$sum.AppendLine(('Служб: {0} | Автозапуск: {1} | Задач: {2} | Софт: {3}' -f $map.services.Count, $map.run.Count, $map.tasks.Count, $map.software.Count))
        [void]$sum.AppendLine('')
        [void]$sum.AppendLine('СВЕРКА HDD-КОНСТИТУЦИИ:')
        foreach ($c in $const) { [void]$sum.AppendLine('  ' + ($c -replace '\|', ': ')) }
        [void]$sum.AppendLine('')
        [void]$sum.AppendLine('ДРЕЙФ С ПРЕДЫДУЩЕЙ КАРТОЙ:')
        if ($diff.Count -eq 0) { [void]$sum.AppendLine('  изменений нет') } else { foreach ($c in $diff) { [void]$sum.AppendLine('  ' + ($c -replace '\|', ': ')) } }
        [void]$sum.AppendLine('')
        [void]$sum.AppendLine(('Файлы: map-{0}.json / map-{0}.txt' -f $stamp))
        [void]$sum.AppendLine(('Каталог: {0}' -f $script:MapDir))
        [void]$sum.AppendLine(('SHA256 (JSON): {0}' -f $sha))
        return $sum.ToString()
    } catch {
        Write-PhxLog ('Ошибка снятия карты: {0}' -f $_.Exception.Message)
        return ('ОШИБКА снятия карты: {0}' -f $_.Exception.Message)
    }
}
#<<<MAP

#  Каталог внешних профилей: %ProgramData%\PHX-HUB\profiles
# ============================================================

$script:ProfileDir = Join-Path $env:ProgramData 'PHX-HUB\profiles'
try { if (-not (Test-Path $script:ProfileDir)) { New-Item -Path $script:ProfileDir -ItemType Directory -Force | Out-Null } } catch {}

function Test-PhxProfile {
    param([string]$Path)
    $warn = New-Object System.Collections.ArrayList
    try {
        $raw = Get-Content -Path $Path -Encoding UTF8 -Raw
        $j = $raw | ConvertFrom-Json
    } catch {
        return @{ Ok=$false; Err=('JSON не читается: ' + $_.Exception.Message); Warn=@(); Profile=$null }
    }
    $ver = [string]$j.ver
    if ($ver -ne '' -and $ver -ne '1.0' -and $ver -ne '1.1') { [void]$warn.Add(('версия профиля ' + $ver + ' - читаю как 1.1')) }
    $name = [string]$j.name
    if ($name -eq '') { $name = [IO.Path]::GetFileNameWithoutExtension($Path) }

    $tws = @(); $aps = @(); $svs = @()
    foreach ($id in @($j.tweaks)) {
        $s = [string]$id
        if ($s -eq '') { continue }
        $known = ($script:Tweaks | Where-Object { $_.Id -eq $s } | Select-Object -First 1)
        if ($null -eq $known) { [void]$warn.Add(('твик в каталоге не найден: ' + $s)) } else { $tws += $s }
    }
    foreach ($nm in @($j.appx)) {
        $s = [string]$nm
        if ($s -ne '') { $aps += $s }
    }
    if ($null -ne $j.services) {
        foreach ($sv in @($j.services)) {
            $sn = [string]$sv.name; $ss = [string]$sv.start
            $known = ($script:SvcPreset | Where-Object { $_.n -eq $sn } | Select-Object -First 1)
            if ($null -eq $known) { [void]$warn.Add(('служба вне безопасного списка: ' + $sn)); continue }
            if ($ss -ne 'Automatic' -and $ss -ne 'Manual' -and $ss -ne 'Disabled') { [void]$warn.Add(('служба ' + $sn + ': тип ' + $ss + ' запрещён')); continue }
            $svs += @{ Name=$sn; Start=$ss }
        }
    }
    if ($tws.Count -eq 0 -and $aps.Count -eq 0 -and $svs.Count -eq 0) {
        return @{ Ok=$false; Err='в профиле нет ни одного известного действия'; Warn=@($warn); Profile=$null }
    }
    return @{ Ok=$true; Err=$null; Warn=@($warn); Profile=@{ Name=$name; Tweaks=@($tws); Apps=@($aps); Services=@($svs) } }
}

# verify одного значения реестра (DWord сравнивается по байтам - урок 0xFFFFFFFF)
function Test-PhxRegValue {
    param([string]$Path,[string]$Name,$Expected,[string]$Type)
    try {
        if (-not (Test-Path $Path)) { return $false }
        $cur = $null
        if ($Name -eq '(Default)') { $cur = (Get-Item -Path $Path -ErrorAction Stop).GetValue('') }
        else { $cur = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
        if ($Type -eq 'DWord' -or $Type -eq 'QWord') {
            $cb = [BitConverter]::GetBytes([long]$cur)
            $eb = [BitConverter]::GetBytes([long]$Expected)
            if ($Type -eq 'DWord') { return ([BitConverter]::ToUInt32($cb,0) -eq [BitConverter]::ToUInt32($eb,0)) }
            return ([BitConverter]::ToUInt64($cb,0) -eq [BitConverter]::ToUInt64($eb,0))
        }
        return ([string]$cur -eq [string]$Expected)
    } catch { return $false }
}

function Test-PhxActState {
    param($Act)
    switch ([string]$Act.k) {
        'reg' { return (Test-PhxRegValue -Path $Act.p -Name $Act.n -Expected $Act.v -Type ([string]$Act.t)) }
        'svc' { try { return ([string](Get-Service -Name $Act.n -ErrorAction Stop).StartType -eq [string]$Act.s) } catch { return $false } }
        default { return $null }
    }
}

# ПОЛНЫЙ КОНВЕЙЕР: подтверждение -> точка восстановления -> применение -> verify -> сводка
function Invoke-PhxProfileRun {
    param($Profile)
    $nT = @($Profile.Tweaks).Count; $nA = @($Profile.Apps).Count; $nS = @($Profile.Services).Count
    $r = Show-PhxMsg -Text ('Профиль "{0}": твиков {1}, приложений {2}, служб {3}.' + [Environment]::NewLine + [Environment]::NewLine + 'Применить? Каждая запись реестра - с автоматическим бэкапом, всё попадёт в журнал с возможностью отката.' -f $Profile.Name, $nT, $nA, $nS) -Title 'PHX-HUB: профиль' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return $null }
    $rp = Show-PhxMsg -Text 'Создать точку восстановления перед профилем?' -Title 'PHX-HUB' -Question $true
    New-PhxOpGroup
    if ($rp -eq [System.Windows.MessageBoxResult]::Yes) {
        Set-Status 'Создание точки восстановления...'
        [void](New-PhxRestorePoint)
    }
    $st = @{ Applied=0; Failed=0; Chk=0; ChkOk=0; Missed=(New-Object System.Collections.ArrayList) }
    foreach ($tid in @($Profile.Tweaks)) {
        $t = $script:Tweaks | Where-Object { $_.Id -eq $tid } | Select-Object -First 1
        if ($null -eq $t) { continue }
        Set-Status ('Профиль {0}: {1}...' -f $Profile.Name, $t.Name)
        try {
            Invoke-PhxTweak -Tweak $t; $st.Applied++
            foreach ($a in $t.Acts) {
                $v = Test-PhxActState -Act $a
                if ($null -ne $v) {
                    $st.Chk++
                    if ($v) { $st.ChkOk++ } else { [void]$st.Missed.Add($t.Name) }
                }
            }
        } catch {
            $st.Failed++
            Write-PhxLog ('PB FAIL ' + $tid + ': ' + $_.Exception.Message)
            [void]$st.Missed.Add(($t.Name + ' [ошибка]'))
        }
    }
    foreach ($an in @($Profile.Apps)) {
        Set-Status ('Профиль {0}: удаление {1}...' -f $Profile.Name, $an)
        try {
            [void](Remove-PhxAppx -PkgName $an); $st.Applied++
            $st.Chk++
            if ($null -eq (Get-AppxPackage -Name $an -ErrorAction SilentlyContinue)) { $st.ChkOk++ } else { [void]$st.Missed.Add(('Appx: ' + $an)) }
        } catch {
            $st.Failed++
            [void]$st.Missed.Add(('Appx: ' + $an + ' [ошибка]'))
        }
    }
    foreach ($sv in @($Profile.Services)) {
        Set-Status ('Профиль {0}: служба {1} -> {2}...' -f $Profile.Name, $sv.Name, $sv.Start)
        try {
            Set-PhxService -Name $sv.Name -StartType $sv.Start; $st.Applied++
            $st.Chk++
            $cur = [string](Get-Service -Name $sv.Name -ErrorAction Stop).StartType
            if ($cur -eq $sv.Start) { $st.ChkOk++ } else { [void]$st.Missed.Add(('Служба ' + $sv.Name + ': стало ' + $cur)) }
        } catch {
            $st.Failed++
            [void]$st.Missed.Add(('Служба ' + $sv.Name + ' [ошибка]'))
        }
    }
    $missTxt = ''
    if ($st.Missed.Count -gt 0) {
        $head = @($st.Missed | Select-Object -First 6)
        $missTxt = [Environment]::NewLine + [Environment]::NewLine + ('Не совпало ({0}):' -f $st.Missed.Count) + [Environment]::NewLine + '- ' + ($head -join ([Environment]::NewLine + '- '))
        if ($st.Missed.Count -gt 6) { $missTxt += ([Environment]::NewLine + '- ...') }
    }
    Show-PhxMsg ('Профиль "{0}" применён.' + [Environment]::NewLine + [Environment]::NewLine + ('Операций: {0} (ошибок: {1}).' -f $st.Applied, $st.Failed) + [Environment]::NewLine + ('Проверка (verify): {0} из {1} совпало.' -f $st.ChkOk, $st.Chk) + $missTxt) -Title 'PHX-HUB: профиль применён'
    Write-PhxLog ('PROFILE RUN: ' + $Profile.Name + ' applied=' + $st.Applied + ' failed=' + $st.Failed + ' verify=' + $st.ChkOk + '/' + $st.Chk)
    Add-PhxJournal -Entry @{ kind='profile'; name=$Profile.Name; applied=[string]$st.Applied; failed=[string]$st.Failed; verify=('{0}/{1}' -f $st.ChkOk, $st.Chk) }
    Set-Status 'Готово.'
    return $st
}

# карточки внешних профилей из каталога (после встроенных)
function Add-PhxExternalProfileCards {
    if (-not (Test-Path $script:ProfileDir)) { return }
    $files = @(Get-ChildItem -Path $script:ProfileDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count -eq 0) {
        $hint = New-PhxTxt -Text ('Внешних профилей нет. Положи JSON в каталог: {0} и нажми "Обновить каталог".' -f $script:ProfileDir) -Color '#5A6070' -Size 11
        $hint.Margin = '0,10,0,2'
        [void]$ui.spPlaybooks.Children.Add($hint)
        return
    }
    $hdr = New-PhxTxt -Text ('ВНЕШНИЕ ПРОФИЛИ (каталог: {0})' -f $script:ProfileDir) -Color '#5A6070' -Size 11
    $hdr.Margin = '0,10,0,2'
    [void]$ui.spPlaybooks.Children.Add($hdr)
    foreach ($f in $files) {
        $pr = Test-PhxProfile -Path $f.FullName
        if (-not $pr.Ok) { continue }
        $p = $pr.Profile
        $card = New-PhxCard
        $grid = New-Object System.Windows.Controls.Grid
        $g1 = New-Object System.Windows.Controls.ColumnDefinition; $g1.Width = (New-Object System.Windows.GridLength(1,'Star'))
        $g2 = New-Object System.Windows.Controls.ColumnDefinition; $g2.Width = [System.Windows.GridLength]::Auto
        $g3 = New-Object System.Windows.Controls.ColumnDefinition; $g3.Width = [System.Windows.GridLength]::Auto
        [void]$grid.ColumnDefinitions.Add($g1); [void]$grid.ColumnDefinitions.Add($g2); [void]$grid.ColumnDefinitions.Add($g3)
        $sp = New-Object System.Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-PhxTxt -Text $p.Name -Color '#FF7A2F' -Bold $true -Size 14.5 -Wrap $false))
        [void]$sp.Children.Add((New-PhxTxt -Text ('твиков {0}, приложений {1}, служб {2}  -  файл: {3}' -f @($p.Tweaks).Count, @($p.Apps).Count, @($p.Services).Count, $f.Name) -Color '#8B90A0' -Size 11.5))
        $sp.Margin = '0,0,8,0'
        [void]$grid.Children.Add($sp)
        [System.Windows.Controls.Grid]::SetColumn($sp,0)
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = 'ПРИМЕНИТЬ'
        $btn.Style = $win.FindResource('PhxBtnFire')
        $btn.VerticalAlignment = 'Center'
        $btn.Tag = $p
        $btn.Add_Click({
            $p = $this.Tag
            $pp = @{ Name = $p.Name; Tweaks = @($p.Tweaks); Apps = @($p.Apps); Services = @($p.Services) }
            $null = Invoke-PhxProfileRun -Profile $pp
        })
        [void]$grid.Children.Add($btn)
        [System.Windows.Controls.Grid]::SetColumn($btn,1)
        $bdel = New-Object System.Windows.Controls.Button
        $bdel.Content = 'УДАЛИТЬ'
        $bdel.Style = $win.FindResource('PhxBtn')
        $bdel.VerticalAlignment = 'Center'
        $bdel.Margin = '6,0,0,0'
        $bdel.Tag = $f.FullName
        $bdel.Add_Click({
            $fp = $this.Tag
            $r = Show-PhxMsg -Text ('Удалить файл профиля из каталога?' + [Environment]::NewLine + $fp) -Title 'PHX-HUB: каталог' -Icon Warning -Question $true
            if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
            try { Remove-Item -Path $fp -Force; Build-PlaybookList } catch { Show-PhxMsg ('Не удалось: ' + $_.Exception.Message) -Icon Error }
        })
        [void]$grid.Children.Add($bdel)
        [System.Windows.Controls.Grid]::SetColumn($bdel,2)
        $card.Child = $grid
        [void]$ui.spPlaybooks.Children.Add($card)
    }
}

# ============================================================
#  СБОРЩИКИ ДАННЫХ
# ============================================================

function Get-PhxSystemInfo {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1)
    $freeGB = [math]::Round($os.FreePhysicalMemory/1MB,1)
    $totGB  = [math]::Round($os.TotalVisibleMemorySize/1MB,0)
    $up = (Get-Date) - $os.LastBootUpTime
    return [pscustomobject]@{
        CPU   = ('{0}  ({1} ядер)' -f $cpu.Name.Trim(), $cpu.NumberOfCores)
        RAM   = ('{0} / {1} ГБ свободно' -f $freeGB, $totGB)
        OS    = $os.Caption
        Build = $os.Version
        User  = $env:USERNAME
        Uptime= ('{0} дн. {1:00}:{2:00}' -f $up.Days, $up.Hours, $up.Minutes)
    }
}

function Get-PhxDevices {
    return @(Get-PnpDevice -ErrorAction SilentlyContinue | Sort-Object Class, FriendlyName | ForEach-Object {
        [pscustomobject]@{
            Class  = $_.Class
            Name   = $_.FriendlyName
            Status = $_.Status
            Problem= $(if ($_.Status -ne 'OK') { $_.ProblemDescription } else { '' })
            Id     = $_.InstanceId
        }
    })
}

function Get-PhxMsiState {
    param([string]$InstanceId)
    $p = ('HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties' -f $InstanceId)
    if (-not (Test-Path $p)) { return $null }
    $v = (Get-ItemProperty -Path $p -Name 'MSISupported' -ErrorAction SilentlyContinue)
    if ($null -eq $v) { return @{ Path=$p; Val=$null } }
    return @{ Path=$p; Val=$v.MSISupported }
}

function Get-PhxPowerPlans {
    $out = @()
    $raw = @()
    try { $raw = @(& powercfg /list 2>&1) } catch { return $out }
    foreach ($l in $raw) {
        if ($l -match 'GUID.:\s+\S+\s+\((.+)\)') {
            $name = $Matches[1]
            $guid = ($l -replace '.*GUID: ','' -replace '\(.+\)','').Trim()
            $isCur = $l -match '\*'
            $out += [pscustomobject]@{ Name=$name; Guid=$guid; Active=$isCur }
        }
    }
    return $out
}

function Get-PhxNetAdapters {
    return @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Name    = $_.Name
            Desc    = $_.InterfaceDescription
            Status  = $_.Status
            Speed   = ('{0} Мбит/с' -f [math]::Round($_.Speed/1MB,0))
            DNS     = (@($dns.ServerAddresses) -join ', ')
            IfIndex = $_.ifIndex
        }
    })
}

function Get-PhxServicesView {
    return @(Get-Service | Where-Object { $_.StartType -ne 'Boot' } | Sort-Object DisplayName | ForEach-Object {
        [pscustomobject]@{
            Name  = $_.DisplayName
            Svc   = $_.Name
            Status= $_.Status
            Start = $_.StartType
        }
    })
}

function Get-PhxJournalView {
    if (-not (Test-Path $script:JournalF)) { return @() }
    $out = @()
    $lines = @(Get-Content -Path $script:JournalF -Encoding UTF8 | Where-Object { $_.Trim() -ne '' })
    foreach ($l in $lines) {
        try {
            $j = $l | ConvertFrom-Json
            $tgt = switch ($j.kind) {
                'reg'  { ('{0} :: {1} = {2}' -f $j.path, $j.name, $j.newv) }
                'regdel' { ('удалён ключ: ' + $j.path) }
                'svc'  { ('служба {0}: {1} -> {2}' -f $j.name, $j.old, $j.new) }
                'cmd'  { $j.desc }
                'cmdps'{ $j.desc }
                'dns'  { ('DNS {0}: {1}' -f $j.name, $j.new) }
                'appx' { ('удалено приложение: ' + $j.full) }
                default { $j.kind }
            }
            $kindRu = switch ($j.kind) {
                'reg' {'реестр'} 'regdel' {'реестр'} 'svc' {'служба'} 'cmd' {'команда'} 'cmdps' {'команда PS'} 'dns' {'DNS'} 'appx' {'приложение'} default {$j.kind}
            }
            $out += [pscustomobject]@{
                Time = $j.ts; Kind = $kindRu; Target = $tgt; Group = $j.group
            }
        } catch {}
    }
    return $out
}


# ============================================================
#  XAML: ОБОЛОЧКА (тёмная фениксовая тема)
# ============================================================

$script:Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PHX-HUB v1.2 :: PHOENIX Control Center"
        Height="780" Width="1260" MinHeight="640" MinWidth="1020"
        WindowStartupLocation="CenterScreen"
        Background="#0F1117" FontFamily="Segoe UI" FontSize="13"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">

  <Window.Resources>
    <Style x:Key="PhxBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#E8E6E3"/>
      <Setter Property="Background" Value="#232839"/>
      <Setter Property="BorderBrush" Value="#2E3450"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="7" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2E3550"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#3A4260"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PhxBtnFire" TargetType="Button" BasedOn="{StaticResource PhxBtn}">
      <Setter Property="Background" Value="#B44A15"/>
      <Setter Property="BorderBrush" Value="#FF7A2F"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="7" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E05A18"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#8A3A10"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PhxNav" TargetType="Button" BasedOn="{StaticResource PhxBtn}">
      <Setter Property="Height" Value="42"/>
      <Setter Property="Margin" Value="12,3"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="FontSize" Value="13.5"/>
    </Style>

    <Style x:Key="PhxList" TargetType="ListView">
      <Setter Property="Background" Value="#141722"/>
      <Setter Property="BorderBrush" Value="#262B3A"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="#E8E6E3"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Auto"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="58"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="32"/>
    </Grid.RowDefinitions>

    <!-- ВЕРХНЯЯ ПАНЕЛЬ -->
    <Border Grid.Row="0" Background="#151824" BorderBrush="#262B3A" BorderThickness="0,0,0,1">
      <Grid Margin="16,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="PHOENIX" FontSize="19" FontWeight="Bold" Foreground="#FF7A2F"/>
          <TextBlock Text="HUB" FontSize="19" FontWeight="Bold" Foreground="#E8E6E3" Margin="6,0,0,0"/>
          <Border Background="#1E2230" CornerRadius="4" Margin="12,0,0,0" Padding="7,3" VerticalAlignment="Center">
            <TextBlock x:Name="tbVer" Text="v1.0" Foreground="#8B90A0" FontSize="11"/>
          </Border>
        </StackPanel>
        <TextBlock x:Name="tbSysInfo" Grid.Column="1" VerticalAlignment="Center" Margin="20,0"
                   Foreground="#8B90A0" FontSize="11.5" TextTrimming="CharacterEllipsis" Text="сбор данных..."/>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
          <Border x:Name="bdAdmin" Background="#2A2418" CornerRadius="4" Padding="8,3" Margin="0,0,10,0">
            <TextBlock x:Name="tbAdmin" Text="..." FontSize="11" FontWeight="Bold" Foreground="#D9A648"/>
          </Border>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ОСНОВНАЯ ОБЛАСТЬ -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="230"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#12141D" BorderBrush="#262B3A" BorderThickness="0,0,1,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="0,10,0,10">
            <TextBlock Text="УПРАВЛЕНИЕ" Foreground="#5A6070" FontSize="10.5" Margin="16,4,0,6"/>
            <Button x:Name="navDash"   Style="{StaticResource PhxNav}" Tag="Dash"   Content="ГЛАВНАЯ"/>
            <Button x:Name="navTweaks" Style="{StaticResource PhxNav}" Tag="Tweaks" Content="ТВИКИ"/>
            <Button x:Name="navPlay"   Style="{StaticResource PhxNav}" Tag="Play"   Content="ПРОФИЛИ"/>
            <Button x:Name="navMap"    Style="{StaticResource PhxNav}" Tag="Map"    Content="КАРТА"/>
            <Button x:Name="navDev"    Style="{StaticResource PhxNav}" Tag="Dev"    Content="УСТРОЙСТВА"/>
            <Button x:Name="navPower"  Style="{StaticResource PhxNav}" Tag="Power"  Content="ЭНЕРГИЯ"/>
            <Button x:Name="navNet"    Style="{StaticResource PhxNav}" Tag="Net"    Content="СЕТЬ"/>
            <Button x:Name="navApps"   Style="{StaticResource PhxNav}" Tag="Apps"   Content="ПРИЛОЖЕНИЯ"/>
            <Button x:Name="navSvc"    Style="{StaticResource PhxNav}" Tag="Svc"    Content="СЛУЖБЫ"/>
            <Button x:Name="navJournal" Style="{StaticResource PhxNav}" Tag="Journal" Content="ЖУРНАЛ И ОТКАТ"/>
            <Button x:Name="navAbout"  Style="{StaticResource PhxNav}" Tag="About"  Content="О ПРОГРАММЕ"/>
          </StackPanel>
        </ScrollViewer>
      </Border>

      <Grid Grid.Column="1" Margin="14,12,14,10">

        <!-- 1. ГЛАВНАЯ -->
        <Grid x:Name="panDash">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Background="#1A1D29" CornerRadius="10" Padding="16,12" BorderBrush="#262B3A" BorderThickness="1">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="180"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock x:Name="tbSysBig" Text="..." FontSize="15" FontWeight="Bold" Foreground="#E8E6E3"/>
                <TextBlock x:Name="tbSysSub" Text="..." FontSize="12" Foreground="#8B90A0" Margin="0,4,0,0"/>
                <TextBlock x:Name="tbSysThird" Text="..." FontSize="12" Foreground="#8B90A0" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock x:Name="tbScorePct" Text="--" FontSize="34" FontWeight="Bold" HorizontalAlignment="Center" Foreground="#D9A648"/>
                <TextBlock Text="БЕЗОПАСНОСТЬ" FontSize="10.5" Foreground="#5A6070" HorizontalAlignment="Center"/>
              </StackPanel>
              <Button x:Name="btnRP" Grid.Column="2" Style="{StaticResource PhxBtnFire}" VerticalAlignment="Center"
                      Content="Точка восстановления"/>
            </Grid>
          </Border>
          <ScrollViewer Grid.Row="1" Margin="0,10,0,0" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="spChecks" Margin="0,0,4,0"/>
          </ScrollViewer>
          <TextBlock Grid.Row="2" x:Name="tbDashHint" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11"
                     Text="Каждая проверка независима: 'Исправить' пишет изменение в журнал - откат через раздел ЖУРНАЛ."/>
        </Grid>

        <!-- 2. ТВИКИ -->
        <Grid x:Name="panTweaks" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Каталог твиков. Каждый применяется с резервной копией реестра и записью в журнал."
                       Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
            <Button x:Name="btnSelAll"  Grid.Column="1" Style="{StaticResource PhxBtn}" Content="Отметить все" Margin="8,0,0,0"/>
            <Button x:Name="btnSelNone" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="Снять все" Margin="8,0,0,0"/>
            <Button x:Name="btnApply"   Grid.Column="3" Style="{StaticResource PhxBtnFire}" Content="ПРИМЕНИТЬ ВЫБРАННОЕ" Margin="8,0,0,0"/>
          </Grid>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="spTweaks" Margin="0,0,4,0"/>
          </ScrollViewer>
          <TextBlock Grid.Row="2" x:Name="tbTweakHint" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11"
                     Text="Часть твиков требует перезапуска Проводника или выхода из системы - будет предложено автоматически."/>
        </Grid>

        <!-- 3. ПРОФИЛИ -->
        <Grid x:Name="panPlay" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Margin="0,0,0,8">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="Профили одним кликом + перенос конфигурации на флешке (JSON)."
                         Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
              <Button x:Name="btnPlayExport" Grid.Column="1" Style="{StaticResource PhxBtn}" Content="Экспорт профиля" Margin="8,0,0,0"/>
              <Button x:Name="btnPlayImport" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="Импорт (галочки)" Margin="8,0,0,0"/>
            </Grid>
            <Grid Margin="0,6,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="v1.2: движок плейбуков TweakHub + Конституция-страж + DRY-RUN + verify."
                         Foreground="#5A6070" VerticalAlignment="Center" FontSize="11"/>
              <Button x:Name="btnPlayApplyFile" Grid.Column="1" Style="{StaticResource PhxBtnFire}" Content="ИМПОРТ И ПРИМЕНИТЬ" Margin="8,0,0,0"/>
              <Button x:Name="btnPlayCatalog" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="Обновить каталог" Margin="8,0,0,0"/>
              <Button x:Name="btnPlayFolder" Grid.Column="3" Style="{StaticResource PhxBtn}" Content="Папка профилей" Margin="8,0,0,0"/>
            </Grid>
          </StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="spPlaybooks" Margin="0,0,4,0"/>
          </ScrollViewer>
          <StackPanel Grid.Row="2" Margin="0,8,0,0">
            <Grid Margin="0,0,0,4">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Button x:Name="btnExtImport" Grid.Column="0" Style="{StaticResource PhxBtn}" Content="Импорт плейбука" Margin="0,0,6,0"/>
              <Button x:Name="btnExtShow" Grid.Column="1" Style="{StaticResource PhxBtn}" Content="Шаги" Margin="0,0,6,0"/>
              <Button x:Name="btnExtDry" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="DRY-RUN" Margin="0,0,6,0"/>
              <Button x:Name="btnExtApply" Grid.Column="3" Style="{StaticResource PhxBtnFire}" Content="ПРИМЕНИТЬ ПРОФИЛЬ" Margin="0,0,6,0"/>
              <Button x:Name="btnExtUndo" Grid.Column="4" Style="{StaticResource PhxBtn}" Content="Откат прогона"/>
            </Grid>
            <TextBox x:Name="txtExtLog" Height="170" IsReadOnly="True" Background="#12151D" Foreground="#C9CFDA"
                     BorderBrush="#2A3140" BorderThickness="1" FontFamily="Consolas" FontSize="11"
                     TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     Padding="6,4"/>
            <TextBlock Margin="0,6,0,0" Foreground="#5A6070" FontSize="11"
                       Text="Движок v1.3: плейбуки TweakHub (Version=1) и PHX-профили, Конституция-страж (HDD-вредное - БЛОК), DRY-RUN, SHA256 в журнале. Каталог наших профилей: %ProgramData%\PHX-HUB\profiles. Экспорт - по чекбоксам ТВИКОВ/ПРИЛОЖЕНИЙ."
                       TextWrapping="Wrap"/>
          </StackPanel>
        </Grid>

        <!-- 3b. КАРТА (v1.3) -->
        <Grid x:Name="panMap" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="КАРТА СТАНЦИИ: карта железа + карта системы = полная карта территории. Только чтение - ноль записей в систему."
                       Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5" TextWrapping="Wrap"/>
            <Button x:Name="btnMapSnap"   Grid.Column="1" Style="{StaticResource PhxBtnFire}" Content="СНЯТЬ КАРТУ" Margin="8,0,0,0"/>
            <Button x:Name="btnMapFolder" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="Папка карт" Margin="8,0,0,0"/>
          </Grid>
          <TextBox x:Name="txtMap" Grid.Row="1" IsReadOnly="True" Background="#12151D" Foreground="#C9CFDA"
                   BorderBrush="#2A3140" BorderThickness="1" FontFamily="Consolas" FontSize="11"
                   TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                   Padding="6,4"
                   Text="Карта не снималась. Кнопка САНЯТЬ КАРТУ делает полный срез: ОС, железо, службы (состояние+тип запуска), автозапуск, задачи, процессы, софт - затем сверку с HDD-конституцией (ТРЕВОГИ) и диф с предыдущей картой (дрейф). Файлы: %ProgramData%\PHX-HUB\maps (JSON+TXT+SHA256). Карту можно передать агенту проекта - это глаза вместо догадок."/>
          <TextBlock Grid.Row="2" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11" TextWrapping="Wrap"
                     Text="Методология Хозяина: прежде чем что-либо делать в системе - изучить её досконально, держать на руках карту территории. Снимай карту до и после каждого этапа изменений: диф покажет, что именно изменилось."/>
        </Grid>

        <!-- 4. УСТРОЙСТВА -->
        <Grid x:Name="panDev" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Инвентаризация устройств. Проблемные - подсвечены. MSI-режим для выбранного устройства."
                       Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
            <Button x:Name="btnDevRefresh" Grid.Column="1" Style="{StaticResource PhxBtn}" Content="Обновить" Margin="8,0,0,0"/>
            <Button x:Name="btnDevProblems" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="Только проблемные" Margin="8,0,0,0"/>
          </Grid>
          <ListView x:Name="lvDevices" Grid.Row="2" Style="{StaticResource PhxList}" SelectionMode="Single">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Класс" Width="110" DisplayMemberBinding="{Binding Class}"/>
                <GridViewColumn Header="Устройство" Width="430" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="Статус" Width="80" DisplayMemberBinding="{Binding Status}"/>
                <GridViewColumn Header="Проблема" Width="330" DisplayMemberBinding="{Binding Problem}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <Border Grid.Row="3" Background="#1A1D29" CornerRadius="10" Padding="12,8" Margin="0,8,0,0"
                  BorderBrush="#262B3A" BorderThickness="1">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="tbMsi" Text="Выберите устройство в списке." Foreground="#8B90A0" VerticalAlignment="Center" TextWrapping="Wrap" FontSize="11.5"/>
              <Button x:Name="btnMsiOn"  Grid.Column="1" Style="{StaticResource PhxBtn}" Content="MSI вкл" Margin="8,0,0,0"/>
              <Button x:Name="btnMsiOff" Grid.Column="2" Style="{StaticResource PhxBtn}" Content="MSI выкл" Margin="8,0,0,0"/>
            </Grid>
          </Border>
        </Grid>

        <!-- 5. ЭНЕРГИЯ -->
        <Grid x:Name="panPower" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Text="Схемы электропитания и быстрые действия (всё через powercfg, с журналом)."
                     Foreground="#8B90A0" Margin="0,0,0,8" FontSize="11.5"/>
          <ListView x:Name="lvPlans" Grid.Row="1" Style="{StaticResource PhxList}" SelectionMode="Single">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Схема" Width="520" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="GUID" Width="300" DisplayMemberBinding="{Binding Guid}"/>
                <GridViewColumn Header="Активна" Width="90" DisplayMemberBinding="{Binding ActiveS}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <WrapPanel Grid.Row="2" Margin="0,8,0,0">
            <Button x:Name="btnPlanSet" Style="{StaticResource PhxBtnFire}" Content="Сделать активной выбранную" Margin="0,0,8,6"/>
            <Button x:Name="btnHibOff" Style="{StaticResource PhxBtn}" Content="Гибернация: выкл" Margin="0,0,8,6"/>
            <Button x:Name="btnHibOn"  Style="{StaticResource PhxBtn}" Content="Гибернация: вкл" Margin="0,0,8,6"/>
            <Button x:Name="btnFastOff" Style="{StaticResource PhxBtn}" Content="Быстрый старт: выкл" Margin="0,0,8,6"/>
            <Button x:Name="btnFastOn"  Style="{StaticResource PhxBtn}" Content="Быстрый старт: вкл" Margin="0,0,8,6"/>
            <Button x:Name="btnCpu100" Style="{StaticResource PhxBtn}" Content="Мин. CPU 100% (без паркинга)" Margin="0,0,8,6"/>
            <Button x:Name="btnCpu5"   Style="{StaticResource PhxBtn}" Content="Мин. CPU 5% (экономия)" Margin="0,0,8,6"/>
          </WrapPanel>
        </Grid>

        <!-- 6. СЕТЬ -->
        <Grid x:Name="panNet" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Text="Адаптеры и DNS. Смена DNS - с сохранением старых значений в журнале."
                     Foreground="#8B90A0" Margin="0,0,0,8" FontSize="11.5"/>
          <ListView x:Name="lvNet" Grid.Row="1" Style="{StaticResource PhxList}" SelectionMode="Single">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Имя" Width="120" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="Адаптер" Width="330" DisplayMemberBinding="{Binding Desc}"/>
                <GridViewColumn Header="Статус" Width="90" DisplayMemberBinding="{Binding Status}"/>
                <GridViewColumn Header="Скорость" Width="100" DisplayMemberBinding="{Binding Speed}"/>
                <GridViewColumn Header="DNS" Width="220" DisplayMemberBinding="{Binding DNS}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <WrapPanel Grid.Row="2" Margin="0,8,0,0">
            <Button x:Name="btnDnsCF"   Style="{StaticResource PhxBtnFire}" Content="DNS: Cloudflare (1.1.1.1)" Margin="0,0,8,6"/>
            <Button x:Name="btnDnsG"    Style="{StaticResource PhxBtn}" Content="DNS: Google (8.8.8.8)" Margin="0,0,8,6"/>
            <Button x:Name="btnDnsQ9"   Style="{StaticResource PhxBtn}" Content="DNS: Quad9 (9.9.9.9)" Margin="0,0,8,6"/>
            <Button x:Name="btnDnsAuto" Style="{StaticResource PhxBtn}" Content="DNS: авто (DHCP)" Margin="0,0,8,6"/>
            <Button x:Name="btnFlush"   Style="{StaticResource PhxBtn}" Content="Очистить кеш DNS" Margin="0,0,8,6"/>
          </WrapPanel>
          <TextBlock x:Name="tbNetHint" Grid.Row="3" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11"
                     Text="Если провайдер перехватывает порт 53 (подмена DNS), смена внешне может не сработать - проверяется трассировкой."/>
        </Grid>

        <!-- 7. ПРИЛОЖЕНИЯ -->
        <Grid x:Name="panApps" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Магазинные приложения (Appx). Удаление для текущего пользователя; возврат - из Microsoft Store."
                       Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
            <Button x:Name="btnAppxRemove" Grid.Column="1" Style="{StaticResource PhxBtnFire}" Content="УДАЛИТЬ ВЫБРАННЫЕ" Margin="8,0,0,0"/>
          </Grid>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="spApps" Margin="0,0,4,0"/>
          </ScrollViewer>
          <TextBlock x:Name="tbWinget" Grid.Row="2" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11" Text="winget: проверка..."/>
        </Grid>

        <!-- 8. СЛУЖБЫ -->
        <Grid x:Name="panSvc" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Службы. Выберите строку и отключите, либо примените безопасный пресет целиком."
                       Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
            <Button x:Name="btnSvcDisable" Grid.Column="1" Style="{StaticResource PhxBtn}" Content="Отключить выбранную" Margin="8,0,0,0"/>
            <Button x:Name="btnSvcPreset"  Grid.Column="2" Style="{StaticResource PhxBtnFire}" Content="Безопасный пресет" Margin="8,0,0,0"/>
          </Grid>
          <ListView x:Name="lvSvc" Grid.Row="1" Style="{StaticResource PhxList}" SelectionMode="Single">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Отображаемое имя" Width="480" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="Служба" Width="220" DisplayMemberBinding="{Binding Svc}"/>
                <GridViewColumn Header="Состояние" Width="110" DisplayMemberBinding="{Binding Status}"/>
                <GridViewColumn Header="Запуск" Width="100" DisplayMemberBinding="{Binding Start}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <TextBlock Grid.Row="2" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11"
                     Text="Пресет: DiagTrack, dmwappushservice, MapsBroker, lfsvc, RetailDemo, WMPNetworkSvc, RemoteRegistry, PhoneSvc, Fax. Прежний тип запуска каждой службы сохраняется в журнале."/>
        </Grid>

        <!-- 9. ЖУРНАЛ -->
        <Grid x:Name="panJournal" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Каждая операция зафиксирована. Выберите группу операций и откатите её, либо откатите всё."
                       Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
            <Button x:Name="btnUndoGroup" Grid.Column="1" Style="{StaticResource PhxBtn}" Content="Откатить выбранную группу" Margin="8,0,0,0"/>
            <Button x:Name="btnUndoAll"   Grid.Column="2" Style="{StaticResource PhxBtnFire}" Content="ОТКАТИТЬ ВСЁ" Margin="8,0,0,0"/>
          </Grid>
          <ListView x:Name="lvJournal" Grid.Row="1" Style="{StaticResource PhxList}" SelectionMode="Single">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Время" Width="150" DisplayMemberBinding="{Binding Time}"/>
                <GridViewColumn Header="Тип" Width="90" DisplayMemberBinding="{Binding Kind}"/>
                <GridViewColumn Header="Что изменилось" Width="660" DisplayMemberBinding="{Binding Target}"/>
                <GridViewColumn Header="Группа" Width="120" DisplayMemberBinding="{Binding Group}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <TextBlock x:Name="tbBackupDir" Grid.Row="2" Margin="0,8,0,0" Foreground="#5A6070" FontSize="11" Text="Бэкапы реестра: ..."/>
        </Grid>

        <!-- 10. О ПРОГРАММЕ -->
        <Grid x:Name="panAbout" Visibility="Collapsed">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel MaxWidth="860" HorizontalAlignment="Left">
              <TextBlock Text="PHX-HUB" FontSize="26" FontWeight="Bold" Foreground="#FF7A2F"/>
              <TextBlock Text="Единый центр управления системой проекта H-PE11 // PHOENIX. Версия 1.0."
                         Foreground="#8B90A0" Margin="0,6,0,16" TextWrapping="Wrap"/>
              <TextBlock Foreground="#C9CBD4" TextWrapping="Wrap" FontSize="12.5" LineHeight="20"
                         Text="Механизм вдохновлён TweakHub (PrimeBuild-pc): каталог твиков с бэкапами, плейбуки, скор безопасности, MSI-режим устройств, редактор энергии. Дополнено лучшими мировыми практиками: WinUtil (CTT) - сетевые задержки и деbloat-чистка, Sophia Script - политики приватности, privacy.sexy - прозрачность каждой операции, O&amp;O ShutUp10++ - точки восстановления перед изменениями.&#x0a;&#x0a;Ключевые отличия от оригинала: нулевые зависимости (нативный PowerShell 5.1 + WPF, ничего не ставится), полный журнал с обратным порядком отката, автоматический reg-экспорт затрагиваемых ключей ДО каждой записи, перенос профилей JSON на флешке, русский интерфейс из коробки.&#x0a;&#x0a;Правила безопасности: точка восстановления перед массовыми операциями; удаление Appx - только для текущего пользователя и только заведомо возвратимого; службы - только смена типа запуска, прежний тип хранится в журнале; реестр - reg-экспорт перед каждой записью.&#x0a;&#x0a;Данные: %ProgramData%\PHX-HUB - журнал (journal.jsonl), лог (phx-hub.log), резервные копии (backup\ГРУППА\*.reg).&#x0a;&#x0a;v1.1: профильный движок - каталог внешних профилей (ProgramData\PHX-HUB\profiles), импорт профиля с немедленным применением, verify-проход (перечитывание фактических значений после применения), службы в профилях - только из безопасного списка.&#x0a;v1.2: движок ПЛЕЙБУКОВ TweakHub 1.5.0 (Version=1: builtin:/custom: шаги, PowerShell-скрипты) - исполняется БЕЗ установленного TweakHub; Конституция-страж: HDD-вредные шаги БЛОКИРУЮТСЯ с явной причиной; DRY-RUN: полный прогон без единой записи; SHA256 профиля пишется в журнал; откат прогона одним кликом; builtin-каталог TweakHub (22 твика) вшит из открытых исходников.&#x0a;v1.3: КАРТА СТАНЦИИ - методология Хозяина в инструменте: полный срез живой системы (ОС, железо, службы с типами запуска, автозапуск, задачи, процессы, софт) одним кликом БЕЗ единой записи в систему; сверка карты с HDD-конституцией (ТРЕВОГИ с причинами и командами возврата); диф с предыдущей картой - детект дрейфа (практика configuration drift 2026); карты в %ProgramData%\PHX-HUB\maps как JSON+TXT+SHA256 - файл карты можно передать агенту проекта, это глаза вместо догадок."/>
              <TextBlock Text="PHOENIX WILL RISE." Foreground="#FF7A2F" FontWeight="Bold" Margin="0,16,0,0"/>
            </StackPanel>
          </ScrollViewer>
        </Grid>

      </Grid>
    </Grid>

    <!-- СТАТУС -->
    <Border Grid.Row="2" Background="#151824" BorderBrush="#262B3A" BorderThickness="0,1,0,0">
      <Grid Margin="14,0">
        <TextBlock x:Name="tbStatus" Text="Готово." Foreground="#8B90A0" VerticalAlignment="Center" FontSize="11.5"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@


# ============================================================
#  UI: РАЗБОР XAML + ХЕЛПЕРЫ
# ============================================================

$win = [Windows.Markup.XamlReader]::Parse($script:Xaml)

function Get-UINode { param([string]$Name)
    $n = $win.FindName($Name)
    if ($null -eq $n) { throw ('UI-элемент не найден: ' + $Name) }
    return $n
}

$ui = @{}
foreach ($n in @('tbVer','tbSysInfo','tbAdmin','bdAdmin','tbScorePct','spChecks','btnRP','tbSysBig','tbSysSub','tbSysThird',
    'spTweaks','btnSelAll','btnSelNone','btnApply','tbTweakHint',
    'spPlaybooks','btnPlayExport','btnPlayImport','btnPlayApplyFile','btnPlayCatalog','btnPlayFolder',
    'lvDevices','btnDevRefresh','btnDevProblems','tbMsi','btnMsiOn','btnMsiOff',
    'lvPlans','btnPlanSet','btnHibOff','btnHibOn','btnFastOff','btnFastOn','btnCpu100','btnCpu5',
    'lvNet','btnDnsCF','btnDnsG','btnDnsQ9','btnDnsAuto','btnFlush','tbNetHint',
    'spApps','btnAppxRemove','tbWinget',
    'lvSvc','btnSvcDisable','btnSvcPreset',
    'lvJournal','btnUndoGroup','btnUndoAll','tbBackupDir',
    'tbStatus','panDash','panTweaks','panPlay','panDev','panPower','panNet','panApps','panSvc','panJournal','panAbout',
    'navDash','navTweaks','navPlay','navDev','navPower','navNet','navApps','navSvc','navJournal','navAbout')) {
    $ui[$n] = Get-UINode -Name $n
}

$script:BrushConv = New-Object System.Windows.Media.BrushConverter
function Col { param([string]$Hex) return $script:BrushConv.ConvertFromString($Hex) }

# мгновенная прокачка очереди отрисовки (WPF-DoEvents)
function Push-PhxFrame {
    $fr = New-Object System.Windows.Threading.DispatcherFrame
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([action]{ $fr.Continue = $false })
    [void][System.Windows.Threading.Dispatcher]::PushFrame($fr)
}

function Set-Status {
    param([string]$Text)
    $ui.tbStatus.Text = $Text
    [void]$win.Dispatcher.Invoke([action]{})
    Push-PhxFrame
    Start-Sleep -Milliseconds 15
}

function Show-PhxMsg {
    param([string]$Text,[string]$Title='PHX-HUB',[string]$Icon='Information',[bool]$Question=$false)
    $mt = [System.Windows.MessageBoxImage]::Information
    if ($Icon -eq 'Warning') { $mt = [System.Windows.MessageBoxImage]::Warning }
    if ($Icon -eq 'Error')   { $mt = [System.Windows.MessageBoxImage]::Error }
    $mb = [System.Windows.MessageBoxButton]::OK
    if ($Question) { $mb = [System.Windows.MessageBoxButton]::YesNo }
    return [System.Windows.MessageBox]::Show($win, $Text, $Title, $mb, $mt)
}

function New-PhxCard {
    # базовая карточка-подложка
    $b = New-Object System.Windows.Controls.Border
    $b.Background = Col '#1A1D29'
    $b.CornerRadius = 9
    $b.Padding = 14,10
    $b.Margin = 0,0,0,8
    $b.BorderThickness = 1,1,1,1
    $b.BorderBrush = Col '#262B3A'
    return $b
}

function New-PhxTxt {
    param([string]$Text,[string]$Color='#E8E6E3',[double]$Size=13,[bool]$Bold=$false,[bool]$Wrap=$true)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.Foreground = Col $Color
    $t.FontSize = $Size
    if ($Bold) { $t.FontWeight = 'Bold' }
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

# ============================================================
#  UI: НАВИГАЦИЯ
# ============================================================

$script:Panels = @{
    Dash='panDash'; Tweaks='panTweaks'; Play='panPlay'; Map='panMap'; Dev='panDev'; Power='panPower'
    Net='panNet'; Apps='panApps'; Svc='panSvc'; Journal='panJournal'; About='panAbout'
}
$script:NavBtns = @{
    Dash='navDash'; Tweaks='navTweaks'; Play='navPlay'; Map='navMap'; Dev='navDev'; Power='navPower'
    Net='navNet'; Apps='navApps'; Svc='navSvc'; Journal='navJournal'; About='navAbout'
}

function Show-Panel {
    param([string]$Key)
    foreach ($k in $script:Panels.Keys) {
        $p = $ui[$script:Panels[$k]]
        if ($k -eq $Key) { $p.Visibility = 'Visible' } else { $p.Visibility = 'Collapsed' }
    }
    foreach ($k in $script:NavBtns.Keys) {
        $b = $ui[$script:NavBtns[$k]]
        if ($k -eq $Key) { $b.Foreground = Col '#FF7A2F' } else { $b.Foreground = Col '#E8E6E3' }
    }
    switch ($Key) {
        'Dev'     { if (-not $script:DevLoaded)   { Update-DeviceList } }
        'Power'   { if (-not $script:PowerLoaded) { Update-PowerPlans } }
        'Net'     { if (-not $script:NetLoaded)   { Update-NetList } }
        'Apps'    { if (-not $script:AppsLoaded)  { Update-AppxList } }
        'Svc'     { if (-not $script:SvcLoaded)   { Update-SvcList } }
        'Journal' { Update-JournalList }
    }
}

foreach ($k in $script:NavBtns.Keys) {
    $btn = $ui[$script:NavBtns[$k]]
    $kk = $k
    $btn.Add_Click({ Show-Panel -Key $kk }.GetNewClosure())
}

# ============================================================
#  UI: ГЛАВНАЯ (скор безопасности + точки восстановления)
# ============================================================

function Update-Dashboard {
    Set-Status 'Сбор информации о системе...'
    $si = Get-PhxSystemInfo
    $ui.tbSysBig.Text   = ('{0}  -  сборка {1}' -f $si.OS, $si.Build)
    $ui.tbSysSub.Text   = ('CPU: {0}' -f $si.CPU)
    $ui.tbSysThird.Text = ('RAM: {0}  |  работа: {1}  |  пользователь: {2}' -f $si.RAM, $si.Uptime, $si.User)
    $ui.tbSysInfo.Text  = ('{0}  |  {1}  |  {2}  |  аптайм {3}' -f $si.OS, $si.CPU, $si.RAM, $si.Uptime)

    Set-Status 'Проверка безопасности...'
    $checks = Get-PhxSecurityChecks
    $pass = 0; $total = 0
    $ui.spChecks.Children.Clear()
    foreach ($c in $checks) {
        if ($null -ne $c.Ok) { $total++; if ($c.Ok) { $pass++ } }
        $card = New-PhxCard

        $col = '#E5534B'
        if ($null -eq $c.Ok) { $col = '#5A6070' } elseif ($c.Ok) { $col = '#3FBF7F' }

        $grid = New-Object System.Windows.Controls.Grid
        $g1 = New-Object System.Windows.Controls.ColumnDefinition; $g1.Width = [System.Windows.GridLength]::Auto
        $g2 = New-Object System.Windows.Controls.ColumnDefinition; $g2.Width = (New-Object System.Windows.GridLength(1,'Star'))
        $g3 = New-Object System.Windows.Controls.ColumnDefinition; $g3.Width = [System.Windows.GridLength]::Auto
        [void]$grid.ColumnDefinitions.Add($g1); [void]$grid.ColumnDefinitions.Add($g2); [void]$grid.ColumnDefinitions.Add($g3)

        $dot = New-Object System.Windows.Controls.TextBlock
        $dot.Text = [string][char]0x25CF
        $dot.Foreground = Col $col
        $dot.VerticalAlignment = 'Top'
        $dot.Margin = 0,2,10,0
        [void]$grid.Children.Add($dot)
        [System.Windows.Controls.Grid]::SetColumn($dot,0)

        $mid = New-Object System.Windows.Controls.StackPanel
        [void]$mid.Children.Add((New-PhxTxt -Text $c.Name -Bold $true -Wrap $false))
        [void]$mid.Children.Add((New-PhxTxt -Text $c.Info -Color '#8B90A0' -Size 11.5))
        $mid.Margin = 0,0,8,0
        [void]$grid.Children.Add($mid)
        [System.Windows.Controls.Grid]::SetColumn($mid,1)

        if ($c.FixType) {
            $fx = New-Object System.Windows.Controls.Button
            $fx.Content = 'Исправить'
            $fx.Style = $win.FindResource('PhxBtn')
            $fx.Margin = 10,0,0,0
            $fx.VerticalAlignment = 'Center'
            $fx.Tag = $c
            $fx.Add_Click({
                $cc = $this.Tag
                $r = Show-PhxMsg -Text $cc.FixDesc -Title 'PHX-HUB: исправление' -Icon Warning -Question $true
                if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
                New-PhxOpGroup
                try {
                    switch ($cc.FixType) {
                        'reg'   { Set-PhxReg -Path $cc.FixPath -Name $cc.FixName -Value $cc.FixVal }
                        'cmd2'  { Invoke-PhxCmd -Run $cc.FixCmd -Undo '' -Desc $cc.FixDesc }
                        'cmdps' { Invoke-PhxCmdPS -Command $cc.FixCmd -Desc $cc.FixDesc }
                    }
                    Set-Status ('Исправлено: ' + $cc.Name)
                    Show-PhxMsg ('Готово: {0}. Обновляю список.' -f $cc.FixDesc)
                } catch {
                    Show-PhxMsg ('Ошибка: ' + $_.Exception.Message) -Icon Error
                }
                Update-Dashboard
            })
            [void]$grid.Children.Add($fx)
            [System.Windows.Controls.Grid]::SetColumn($fx,2)
        }

        $card.Child = $grid
        [void]$ui.spChecks.Children.Add($card)
    }
    $pct = 0
    if ($total -gt 0) { $pct = [int][math]::Round($pass * 100.0 / $total) }
    $ui.tbScorePct.Text = ('{0}%' -f $pct)
    $scCol = '#E5534B'; if ($pct -ge 80) { $scCol = '#3FBF7F' } elseif ($pct -ge 50) { $scCol = '#D9A648' }
    $ui.tbScorePct.Foreground = Col $scCol
    Set-Status ('Скор безопасности: {0}% ({1} из {2}).' -f $pct, $pass, $total)
}

$ui.btnRP.Add_Click({
    $r = Show-PhxMsg -Text 'Создать точку восстановления системы сейчас?' -Title 'PHX-HUB' -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Set-Status 'Создание точки восстановления (может занять до минуты)...'
    New-PhxOpGroup
    $ok = New-PhxRestorePoint
    if ($ok) { Show-PhxMsg 'Точка восстановления создана.' }
    else { Show-PhxMsg 'Не удалось создать точку. Подробности в логе %ProgramData%\PHX-HUB\phx-hub.log' -Icon Warning }
    Set-Status 'Готово.'
})


# ============================================================
#  UI: ТВИКИ
# ============================================================

$script:chkTweaks = @{}

function Build-TweakList {
    $ui.spTweaks.Children.Clear()
    $script:chkTweaks.Clear()
    $groups = @($script:Tweaks | ForEach-Object { $_.Group } | Select-Object -Unique)
    foreach ($g in $groups) {
        $hdr = New-PhxTxt -Text $g.ToUpper() -Color '#FF7A2F' -Size 12.5 -Bold $true -Wrap $false
        $hdr.Margin = 4,8,0,6
        [void]$ui.spTweaks.Children.Add($hdr)

        foreach ($t in ($script:Tweaks | Where-Object { $_.Group -eq $g })) {
            $card = New-PhxCard
            $sp = New-Object System.Windows.Controls.StackPanel

            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Tag = $t.Id
            $cb.HorizontalAlignment = 'Left'
            $cb.VerticalAlignment = 'Top'
            $cb.Cursor = [System.Windows.Input.Cursors]::Hand
            $cbC = New-PhxTxt -Text $t.Name -Bold $true -Wrap $false
            $cb.Content = $cbC
            $cb.Margin = 0,0,0,4
            [void]$sp.Children.Add($cb)

            [void]$sp.Children.Add((New-PhxTxt -Text $t.Desc -Color '#8B90A0' -Size 11.5))
            $card.Child = $sp
            [void]$ui.spTweaks.Children.Add($card)
            $script:chkTweaks[$t.Id] = $cb
        }
    }
}

$ui.btnSelAll.Add_Click({
    foreach ($k in $script:chkTweaks.Keys) { $script:chkTweaks[$k].IsChecked = $true }
})
$ui.btnSelNone.Add_Click({
    foreach ($k in $script:chkTweaks.Keys) { $script:chkTweaks[$k].IsChecked = $false }
})

$ui.btnApply.Add_Click({
    $sel = @()
    foreach ($k in $script:chkTweaks.Keys) {
        if ($script:chkTweaks[$k].IsChecked) { $sel += $k }
    }
    if ($sel.Count -eq 0) { Show-PhxMsg 'Ничего не отмечено.'; return }

    $r = Show-PhxMsg -Text ('Применить твиков: {0}? Сначала будет предложена точка восстановления.' -f $sel.Count) -Title 'PHX-HUB: применение' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $rp = Show-PhxMsg -Text 'Создать точку восстановления перед применением?' -Title 'PHX-HUB' -Question $true
    if ($rp -eq [System.Windows.MessageBoxResult]::Yes) {
        Set-Status 'Создание точки восстановления...'
        New-PhxOpGroup
        [void](New-PhxRestorePoint)
    }

    New-PhxOpGroup
    $done = 0; $fail = 0
    foreach ($id in $sel) {
        $t = $script:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($null -eq $t) { continue }
        Set-Status ('Применение: {0}...' -f $t.Name)
        try { Invoke-PhxTweak -Tweak $t; $done++ }
        catch {
            $fail++
            Write-PhxLog ('TWEAK FAIL {0}: {1}' -f $id, $_.Exception.Message)
        }
    }

    # перезапуск Проводника для твиков интерфейса
    $needExp = @($sel | Where-Object { @('ctxmenu','tbal','tbwidgets','tbchat') -contains $_ })
    if ($needExp.Count -gt 0) {
        $re = Show-PhxMsg -Text 'Применены твики интерфейса. Перезапустить Проводник сейчас?' -Title 'PHX-HUB' -Question $true
        if ($re -eq [System.Windows.MessageBoxResult]::Yes) {
            $null = & cmd.exe /c 'taskkill /f /im explorer.exe & start explorer.exe' 2>&1
        }
    }
    Show-PhxMsg ('Применено: {0}, с ошибками: {1}.{2}' -f $done, $fail, $(if ($fail -gt 0) {' Подробности в логе.'} else {''}))
    Set-Status ('Твики применены: {0} (журнал обновлён).' -f $done)
})

# ============================================================
#  UI: ПРОФИЛИ (плейбуки + перенос JSON)
# ============================================================

function Build-PlaybookList {
    $ui.spPlaybooks.Children.Clear()
    foreach ($pb in $script:Playbooks) {
        $card = New-PhxCard
        $grid = New-Object System.Windows.Controls.Grid
        $g1 = New-Object System.Windows.Controls.ColumnDefinition; $g1.Width = (New-Object System.Windows.GridLength(1,'Star'))
        $g2 = New-Object System.Windows.Controls.ColumnDefinition; $g2.Width = [System.Windows.GridLength]::Auto
        [void]$grid.ColumnDefinitions.Add($g1); [void]$grid.ColumnDefinitions.Add($g2)

        $sp = New-Object System.Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-PhxTxt -Text $pb.Name -Color '#FF7A2F' -Bold $true -Size 14.5 -Wrap $false))
        [void]$sp.Children.Add((New-PhxTxt -Text $pb.Desc -Color '#8B90A0' -Size 11.5))
        $sp.Margin = 0,0,8,0
        [void]$grid.Children.Add($sp)
        [System.Windows.Controls.Grid]::SetColumn($sp,0)

        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = 'ПРИМЕНИТЬ'
        $btn.Style = $win.FindResource('PhxBtnFire')
        $btn.VerticalAlignment = 'Center'
        $btn.Tag = $pb
        $btn.Add_Click({
            $p = $this.Tag
            $pb = @{ Name = $p.Name; Tweaks = @($p.Tweaks); Apps = @($p.Apps); Services = @() }
            $null = Invoke-PhxProfileRun -Profile $pb
        })
        [void]$grid.Children.Add($btn)
        [System.Windows.Controls.Grid]::SetColumn($btn,1)

        $card.Child = $grid
        [void]$ui.spPlaybooks.Children.Add($card)
    }
    Add-PhxExternalProfileCards
}

# ============================================================
#  v1.2: КНОПКИ ПРОФИЛЬНОГО ДВИЖКА
# ============================================================

$ui.btnPlayApplyFile.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'JSON профиль (*.json)|*.json'
    $dlg.Title = 'PHX-HUB v1.2: выбрать профиль для применения'
    if (-not $dlg.ShowDialog($win)) { return }
    $pr = Test-PhxProfile -Path $dlg.FileName
    if (-not $pr.Ok) { Show-PhxMsg ('Профиль НЕ принят: ' + $pr.Err) -Title 'PHX-HUB: ошибка' -Icon Error; return }
    if ($pr.Warn.Count -gt 0) {
        Show-PhxMsg ('Замечания по профилю (будут пропущены):' + [Environment]::NewLine + '- ' + ($pr.Warn -join ([Environment]::NewLine + '- '))) -Title 'PHX-HUB: предупреждение' -Icon Warning
    }
    $res = Invoke-PhxProfileRun -Profile $pr.Profile
    if ($null -ne $res) {
        $r2 = Show-PhxMsg 'Добавить копию профиля в каталог (%ProgramData%\PHX-HUB\profiles), чтобы применять одним кликом?' -Title 'PHX-HUB' -Question $true
        if ($r2 -eq [System.Windows.MessageBoxResult]::Yes) {
            try {
                Copy-Item -Path $dlg.FileName -Destination (Join-Path $script:ProfileDir (Split-Path $dlg.FileName -Leaf)) -Force
                Build-PlaybookList
                Show-PhxMsg 'Профиль добавлен в каталог.'
            } catch { Show-PhxMsg ('Не удалось добавить: ' + $_.Exception.Message) -Icon Error }
        }
    }
})

$ui.btnPlayCatalog.Add_Click({
    Build-PlaybookList
    $n = @(Get-ChildItem -Path $script:ProfileDir -Filter '*.json' -ErrorAction SilentlyContinue).Count
    Set-Status ('Каталог профилей: внешних {0}.' -f $n)
})

$ui.btnPlayFolder.Add_Click({
    try { if (-not (Test-Path $script:ProfileDir)) { New-Item -Path $script:ProfileDir -ItemType Directory -Force | Out-Null } } catch {}
    Start-Process explorer.exe -ArgumentList ('"' + $script:ProfileDir + '"')
})

$ui.btnPlayExport.Add_Click({
    $selT = @(); $selA = @()
    foreach ($k in $script:chkTweaks.Keys) { if ($script:chkTweaks[$k].IsChecked) { $selT += $k } }
    foreach ($k in $script:chkApps.Keys)  { if ($script:chkApps[$k].IsChecked)  { $selA += $k } }
    $prof = [ordered]@{
        ver = $script:PhxVersion
        host = $env:COMPUTERNAME
        os = (Get-CimInstance Win32_OperatingSystem).Version
        date = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        tweaks = $selT
        appx = $selA
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.FileName = ('PHX-HUB-PROFILE-{0}-{1}.json' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    $dlg.Filter = 'JSON профиль (*.json)|*.json'
    if ($dlg.ShowDialog($win)) {
        try {
            $prof | ConvertTo-Json | Set-Content -Path $dlg.FileName -Encoding UTF8
            Show-PhxMsg ('Профиль сохранён: {0}' -f $dlg.FileName)
        } catch { Show-PhxMsg ('Ошибка сохранения: ' + $_.Exception.Message) -Icon Error }
    }
})

$ui.btnPlayImport.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'JSON профиль (*.json)|*.json'
    if ($dlg.ShowDialog($win)) {
        try {
            $prof = Get-Content -Path $dlg.FileName -Encoding UTF8 -Raw | ConvertFrom-Json
            foreach ($k in $script:chkTweaks.Keys) { $script:chkTweaks[$k].IsChecked = $false }
            foreach ($k in $script:chkApps.Keys)  { $script:chkApps[$k].IsChecked = $false }
            $nT = 0; $nA = 0
            foreach ($id in $prof.tweaks) { if ($script:chkTweaks.ContainsKey($id)) { $script:chkTweaks[$id].IsChecked = $true; $nT++ } }
            foreach ($nm in $prof.appx)   { if ($script:chkApps.ContainsKey($nm))   { $script:chkApps[$nm].IsChecked = $true; $nA++ } }
            Show-PhxMsg ('Профиль загружен: твиков {0}, приложений {1}. Проверьте отметки в ТВИКАХ и ПРИЛОЖЕНИЯХ.' -f $nT, $nA)
        } catch { Show-PhxMsg ('Ошибка чтения профиля: ' + $_.Exception.Message) -Icon Error }
    }
})


# ============================================================
#  UI: ДВИЖОК ПРОФИЛЕЙ v1.2 (внешние плейбуки)
# ============================================================

function Write-ExtLog {
    param([string]$Text)
    $tb = $ui.txtExtLog
    $line = ('[{0}]  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text)
    $tb.AppendText($line + [Environment]::NewLine)
    $tb.ScrollToEnd()
}

$ui.btnExtImport.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Профиль/плейбук JSON (*.json)|*.json|Все файлы (*.*)|*.*'
    $dlg.Title = 'PHX-HUB v1.2: импорт плейбука TweakHub или PHX-профиля'
    if (-not $dlg.ShowDialog($win)) { return }
    try {
        $p = Import-PhxExternalProfile -JsonPath $dlg.FileName
        $script:ExtProfile = $p
        $okC = @($p.Steps | Where-Object { $_.Status -eq 'OK' }).Count
        $skC = @($p.Steps | Where-Object { $_.Status -eq 'SKIP' }).Count
        $blC = @($p.Steps | Where-Object { $_.Status -eq 'BLOCK' }).Count
        Write-ExtLog ('ИМПОРТ: {0}' -f $p.Name)
        Write-ExtLog ('SHA256: {0}' -f $p.Sha)
        Write-ExtLog ('Шагов: {0} (к исполнению {1}, пропущено {2}, БЛОК конституции {3})' -f @($p.Steps).Count, $okC, $skC, $blC)
        foreach ($st in @($p.Steps)) {
            if ($st.Status -eq 'BLOCK') { Write-ExtLog ('  [БЛОК] {0} - {1}' -f $st.Title, $st.Reason) }
        }
        Write-ExtLog ('Далее: DRY-RUN (просмотр), затем ПРИМЕНИТЬ ПРОФИЛЬ.')
        Set-Status ('Профиль загружен: {0}' -f $p.Name)
    } catch { Write-ExtLog ('ОШИБКА ИМПОРТА: ' + $_.Exception.Message) }
})

$ui.btnExtShow.Add_Click({
    if ($null -eq $script:ExtProfile) { Write-ExtLog 'Профиль не загружен. Сначала - Импорт плейбука.'; return }
    $p = $script:ExtProfile
    Write-ExtLog ('ШАГИ ПРОФИЛЯ: {0}  ({1})' -f $p.Name, $p.Source)
    foreach ($st in @($p.Steps)) {
        $mark = switch ($st.Status) { 'OK' {'[ok]  '} 'SKIP' {'[skip]'} 'BLOCK' {'[БЛОК]'} default {'[?]   '} }
        $line = '  {0} #{1,2} {2}' -f $mark, $st.Idx, $st.Title
        if ($st.Status -ne 'OK') { $line += '  :: ' + $st.Reason }
        Write-ExtLog $line
    }
})

$ui.btnExtDry.Add_Click({
    if ($null -eq $script:ExtProfile) { Write-ExtLog 'Профиль не загружен. Сначала - Импорт плейбука.'; return }
    $p = $script:ExtProfile
    Set-Status 'DRY-RUN: прогон без изменений...'
    $r = Invoke-PhxExtProfile -Prof $p -Dry
    Write-ExtLog ('DRY-RUN завершён (ни одной записи не сделано): к исполнению {0}, пропущено {1}, блок {2}, сбоев {3}' -f $r.Ok, $r.Skip, $r.Block, $r.Fail)
    Set-Status 'DRY-RUN готов.'
})

$ui.btnExtApply.Add_Click({
    if ($null -eq $script:ExtProfile) { Write-ExtLog 'Профиль не загружен. Сначала - Импорт плейбука.'; return }
    $p = $script:ExtProfile
    $r = Show-PhxMsg -Text ('Профиль: {0}{1}SHA256: {2}{1}{1}Применить? Каждый шаг - с бэкапом реестра и записью в журнал.' -f $p.Name, [Environment]::NewLine, $p.Sha) -Title 'PHX-HUB v1.2: применение профиля' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $rp = Show-PhxMsg -Text 'Создать точку восстановления перед профилем?' -Title 'PHX-HUB' -Question $true
    if ($rp -eq [System.Windows.MessageBoxResult]::Yes) {
        Set-Status 'Создание точки восстановления...'
        [void](New-PhxRestorePoint)
    }
    $r2 = Invoke-PhxExtProfile -Prof $p
    Write-ExtLog ('ПРИМЕНЕНО: исполнено {0}, пропущено {1}, блок {2}, сбоев {3}. Группа отката: {4}' -f $r2.Ok, $r2.Skip, $r2.Block, $r2.Fail, $r2.Group)
    Show-PhxMsg ('Профиль применён: исполнено {0}, сбоев {1}.{2}Откат - кнопкой "Откат прогона" или через ЖУРНАЛ.' -f $r2.Ok, $r2.Fail, [Environment]::NewLine)
    Set-Status 'Готово.'
})

$ui.btnExtUndo.Add_Click({
    if ([string]::IsNullOrEmpty($script:LastExtGroup)) { Write-ExtLog 'Откатывать нечего: профили ещё не применялись в этой сессии.'; return }
    $r = Show-PhxMsg -Text ('Откатить последний прогон профиля (группа {0})? Реестр вернётся из бэкапов.' -f $script:LastExtGroup) -Title 'PHX-HUB v1.2: откат' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Set-Status 'Откат прогона...'
    $n = Invoke-PhxUndoAll -OnlyGroup $script:LastExtGroup
    Write-ExtLog ('ОТКАТ: обработано записей журнала: {0}' -f $n)
    $script:LastExtGroup = $null
    Set-Status 'Откат завершён.'
})
# ============================================================
#  UI: УСТРОЙСТВА (+ MSI-режим)
# ============================================================

$script:DevLoaded = $false
$script:DevAll = @()

function Update-DeviceList {
    Set-Status 'Инвентаризация устройств...'
    $script:DevAll = Get-PhxDevices
    $ui.lvDevices.ItemsSource = $script:DevAll
    $script:DevLoaded = $true
    $bad = @($script:DevAll | Where-Object { $_.Status -ne 'OK' }).Count
    Set-Status ('Устройств: {0}, с проблемами: {1}.' -f $script:DevAll.Count, $bad)
}

$ui.btnMapSnap.Add_Click({
    $out = Invoke-PhxMapCapture
    $ui.txtMap.Text = $out
})
$ui.btnMapFolder.Add_Click({
    if (-not (Test-Path $script:MapDir)) { New-Item -Path $script:MapDir -ItemType Directory -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList ('"' + $script:MapDir + '"')
})

$ui.btnDevRefresh.Add_Click({ Update-DeviceList })
$ui.btnDevProblems.Add_Click({
    $bad = @($script:DevAll | Where-Object { $_.Status -ne 'OK' })
    $ui.lvDevices.ItemsSource = $bad
    Set-Status ('Проблемных устройств: {0}.' -f $bad.Count)
})

function Show-PhxMsiInfo {
    $sel = $ui.lvDevices.SelectedItem
    if ($null -eq $sel) { $ui.tbMsi.Text = 'Выберите устройство в списке.'; return }
    $msi = Get-PhxMsiState -InstanceId $sel.Id
    if ($null -eq $msi) {
        $ui.tbMsi.Text = ('MSI: драйвер устройства "{0}" не заявляет MessageSignaledInterruptProperties - переключение недоступно.' -f $sel.Name)
    } else {
        if ($null -eq $msi.Val) {
            $ui.tbMsi.Text = ('MSI: ключ есть, значения нет. {0}' -f $msi.Path)
        } else {
            $st = 'ВЫКЛ'; if ($msi.Val -eq 1) { $st = 'ВКЛ' }
            $ui.tbMsi.Text = ('MSI для "{0}": {1}. Изменение требует перезагрузки и пишется в журнал.' -f $sel.Name, $st)
        }
    }
}
$ui.lvDevices.Add_SelectionChanged({ Show-PhxMsiInfo })

function Set-PhxMsi {
    param([int]$Val)
    $sel = $ui.lvDevices.SelectedItem
    if ($null -eq $sel) { Show-PhxMsg 'Выберите устройство.'; return }
    $msi = Get-PhxMsiState -InstanceId $sel.Id
    if ($null -eq $msi -or $null -eq $msi.Val) {
        Show-PhxMsg 'Устройство не заявляет MSI - переключение невозможно.' -Icon Warning
        return
    }
    New-PhxOpGroup
    Set-PhxReg -Path $msi.Path -Name 'MSISupported' -Value $Val -Type 'DWord'
    Show-PhxMsg ('MSI={0} записано для "{1}". Вступит в силу после перезагрузки.' -f $Val, $sel.Name)
    Show-PhxMsiInfo
}
$ui.btnMsiOn.Add_Click({ Set-PhxMsi -Val 1 })
$ui.btnMsiOff.Add_Click({ Set-PhxMsi -Val 0 })

# ============================================================
#  UI: ЭНЕРГИЯ
# ============================================================

$script:PowerLoaded = $false

function Update-PowerPlans {
    $plans = Get-PhxPowerPlans
    $view = @()
    foreach ($p in $plans) {
        $s = 'нет'; if ($p.Active) { $s = 'ДА' }
        $view += [pscustomobject]@{ Name=$p.Name; Guid=$p.Guid; ActiveS=$s }
    }
    $ui.lvPlans.ItemsSource = $view
    $script:PowerLoaded = $true
    Set-Status ('Схем питания: {0}.' -f $view.Count)
}

$ui.btnPlanSet.Add_Click({
    $sel = $ui.lvPlans.SelectedItem
    if ($null -eq $sel) { Show-PhxMsg 'Выберите схему в списке.'; return }
    $prev = @(Get-PhxPowerPlans | Where-Object { $_.Active }) | Select-Object -First 1
    New-PhxOpGroup
    Invoke-PhxCmd -Run ('powercfg /setactive ' + $sel.Guid) -Undo ('powercfg /setactive ' + $prev.Guid) -Desc ('Активная схема: ' + $sel.Name)
    Update-PowerPlans
    Set-Status ('Схема активирована: ' + $sel.Name)
})

$ui.btnHibOff.Add_Click({
    New-PhxOpGroup
    Invoke-PhxCmd -Run 'powercfg /hibernate off' -Undo 'powercfg /hibernate on' -Desc 'Гибернация выключена'
    Set-Status 'Гибернация выключена.'
})
$ui.btnHibOn.Add_Click({
    New-PhxOpGroup
    Invoke-PhxCmd -Run 'powercfg /hibernate on' -Undo 'powercfg /hibernate off' -Desc 'Гибернация включена'
    Set-Status 'Гибернация включена.'
})
$ui.btnFastOff.Add_Click({
    New-PhxOpGroup
    Set-PhxReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -Type 'DWord'
    Set-Status 'Быстрый старт выключен.'
})
$ui.btnFastOn.Add_Click({
    New-PhxOpGroup
    Set-PhxReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 1 -Type 'DWord'
    Set-Status 'Быстрый старт включён.'
})
$ui.btnCpu100.Add_Click({
    New-PhxOpGroup
    Invoke-PhxCmd -Run 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 & powercfg /setactive SCHEME_CURRENT' `
                  -Undo 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 & powercfg /setactive SCHEME_CURRENT' `
                  -Desc 'Минимальное состояние CPU = 100%'
    Set-Status 'Мин. состояние CPU = 100% (отключает простой ядер).'
})
$ui.btnCpu5.Add_Click({
    New-PhxOpGroup
    Invoke-PhxCmd -Run 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 & powercfg /setactive SCHEME_CURRENT' `
                  -Undo 'powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 & powercfg /setactive SCHEME_CURRENT' `
                  -Desc 'Минимальное состояние CPU = 5%'
    Set-Status 'Мин. состояние CPU = 5% (экономия).'
})

# ============================================================
#  UI: СЕТЬ
# ============================================================

$script:NetLoaded = $false

function Update-NetList {
    $ui.lvNet.ItemsSource = Get-PhxNetAdapters
    $script:NetLoaded = $true
    Set-Status 'Сетевые адаптеры обновлены.'
}

function Set-PhxDnsUI {
    param([string[]]$Servers,[string]$Label)
    $sel = $ui.lvNet.SelectedItem
    if ($null -eq $sel) { Show-PhxMsg 'Выберите адаптер в списке.'; return }
    New-PhxOpGroup
    if ($Servers.Count -eq 0) {
        Set-PhxDns -IfIndex $sel.IfIndex -Servers @() -IfName $sel.Name
        Set-Status ('DNS -> авто: ' + $sel.Name)
    } else {
        Set-PhxDns -IfIndex $sel.IfIndex -Servers $Servers -IfName $sel.Name
        Set-Status ('DNS {0} -> {1}' -f $sel.Name, $Label)
    }
    Update-NetList
}

$ui.btnDnsCF.Add_Click({ Set-PhxDnsUI -Servers @('1.1.1.1','1.0.0.1') -Label 'Cloudflare' })
$ui.btnDnsG.Add_Click({ Set-PhxDnsUI -Servers @('8.8.8.8','8.8.4.4') -Label 'Google' })
$ui.btnDnsQ9.Add_Click({ Set-PhxDnsUI -Servers @('9.9.9.9','149.112.112.112') -Label 'Quad9' })
$ui.btnDnsAuto.Add_Click({ Set-PhxDnsUI -Servers @() -Label 'авто' })
$ui.btnFlush.Add_Click({
    $null = & ipconfig /flushdns 2>&1
    Set-Status 'Кеш DNS очищен.'
})

# ============================================================
#  UI: ПРИЛОЖЕНИЯ (Appx)
# ============================================================

$script:chkApps = @{}
$script:AppsLoaded = $false

function Update-AppxList {
    Set-Status 'Чтение установленных приложений...'
    $ui.spApps.Children.Clear()
    $script:chkApps.Clear()
    $installed = 0
    foreach ($a in $script:AppxBloat) {
        $has = $null -ne (Get-AppxPackage -Name $a.n -ErrorAction SilentlyContinue)
        $card = New-PhxCard
        $sp = New-Object System.Windows.Controls.StackPanel
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Tag = $a.n
        $cb.HorizontalAlignment = 'Left'
        $cb.Cursor = [System.Windows.Input.Cursors]::Hand
        if ($has) { $cb.Content = New-PhxTxt -Text $a.d -Bold $true -Wrap $false }
        else { $cb.Content = New-PhxTxt -Text ('{0}  (не установлено)' -f $a.d) -Color '#5A6070' -Wrap $false }
        if ($has -and $a.def -eq 1) { $cb.IsChecked = $true }
        if (-not $has) { $cb.IsEnabled = $false }
        $cb.Margin = 0,0,0,3
        [void]$sp.Children.Add($cb)
        [void]$sp.Children.Add((New-PhxTxt -Text $a.n -Color '#5A6070' -Size 11 -Wrap $false))
        $card.Child = $sp
        [void]$ui.spApps.Children.Add($card)
        $script:chkApps[$a.n] = $cb
        if ($has) { $installed++ }
    }
    $script:AppsLoaded = $true
    # winget
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -ne $wg) { $ui.tbWinget.Text = 'winget найден в системе - удалённое из Store можно вернуть через winget install.' }
    else { $ui.tbWinget.Text = 'winget не найден (для возврата приложений используйте Microsoft Store).' }
    Set-Status ('Приложений из списка в системе: {0} из {1}.' -f $installed, $script:AppxBloat.Count)
}

$ui.btnAppxRemove.Add_Click({
    $sel = @()
    foreach ($k in $script:chkApps.Keys) {
        if ($script:chkApps[$k].IsEnabled -and $script:chkApps[$k].IsChecked) { $sel += $k }
    }
    if ($sel.Count -eq 0) { Show-PhxMsg 'Ничего не отмечено (или отмеченное не установлено).'; return }
    $r = Show-PhxMsg -Text ('Удалить приложений: {0}? Удаление для текущего пользователя; возврат - из Microsoft Store.' -f $sel.Count) -Title 'PHX-HUB: приложения' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    New-PhxOpGroup
    $n = 0
    foreach ($nm in $sel) {
        Set-Status ('Удаление: {0}...' -f $nm)
        try { if (Remove-PhxAppx -PkgName $nm) { $n++ } } catch {}
    }
    Show-PhxMsg ('Удалено: {0} из {1}.' -f $n, $sel.Count)
    Update-AppxList
})

# ============================================================
#  UI: СЛУЖБЫ
# ============================================================

$script:SvcLoaded = $false

function Update-SvcList {
    Set-Status 'Чтение служб...'
    $ui.lvSvc.ItemsSource = Get-PhxServicesView
    $script:SvcLoaded = $true
    Set-Status 'Службы загружены.'
}

$ui.btnSvcDisable.Add_Click({
    $sel = $ui.lvSvc.SelectedItem
    if ($null -eq $sel) { Show-PhxMsg 'Выберите службу в списке.'; return }
    $r = Show-PhxMsg -Text ('Отключить службу "{0}" ({1})? Прежний тип запуска сохранится в журнале.' -f $sel.Name, $sel.Svc) -Title 'PHX-HUB: службы' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    New-PhxOpGroup
    try {
        Set-PhxService -Name $sel.Svc -StartType 'Disabled'
        Set-Status ('Служба отключена: ' + $sel.Svc)
        Update-SvcList
    } catch { Show-PhxMsg ('Ошибка: ' + $_.Exception.Message) -Icon Error }
})

$ui.btnSvcPreset.Add_Click({
    $list = @()
    foreach ($s in $script:SvcPreset) { $list += $s.n.Trim() }
    $r = Show-PhxMsg -Text ('Применить безопасный пресет отключения?{0}Службы: {1}. Прежние типы запуска сохраняются в журнале.' -f [Environment]::NewLine, ($list -join ', ')) -Title 'PHX-HUB: пресет служб' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    New-PhxOpGroup
    $n = 0
    foreach ($s in $script:SvcPreset) {
        Set-Status ('Служба: {0}...' -f $s.n.Trim())
        try { Set-PhxService -Name $s.n.Trim() -StartType 'Disabled'; $n++ } catch { Write-PhxLog ('SVC PRESET FAIL: ' + $s.n.Trim()) }
    }
    Show-PhxMsg ('Пресет применён: отключено {0}.' -f $n)
    Update-SvcList
})

# ============================================================
#  UI: ЖУРНАЛ И ОТКАТ
# ============================================================

function Update-JournalList {
    Set-Status 'Чтение журнала...'
    $ui.lvJournal.ItemsSource = Get-PhxJournalView
    $ui.tbBackupDir.Text = ('Бэкапы реестра: {0}  |  журнал: {1}' -f $script:BackupDir, $script:JournalF)
    Set-Status ('Записей в журнале: {0}.' -f $ui.lvJournal.Items.Count)
}

$ui.btnUndoGroup.Add_Click({
    $sel = $ui.lvJournal.SelectedItem
    if ($null -eq $sel) { Show-PhxMsg 'Выберите любую строку нужной группы операций.'; return }
    $r = Show-PhxMsg -Text ('Откатить ВСЮ группу операций {0}? Реестр вернётся из резервных копий, службы и DNS - к прежним значениям.' -f $sel.Group) -Title 'PHX-HUB: откат' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Set-Status 'Откат группы...'
    $n = Invoke-PhxUndoAll -OnlyGroup $sel.Group
    Show-PhxMsg ('Откатано записей: {0}.' -f $n)
    Update-JournalList
})

$ui.btnUndoAll.Add_Click({
    $r = Show-PhxMsg -Text 'ОТКАТИТЬ ВСЕ операции из журнала (в обратном порядке)? Это вернёт систему к состоянию до всех изменений, сделанных через PHX-HUB.' -Title 'PHX-HUB: ПОЛНЫЙ ОТКАТ' -Icon Warning -Question $true
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Set-Status 'Полный откат (обратный порядок)...'
    $n = Invoke-PhxUndoAll
    Show-PhxMsg ('Откатано записей: {0}. Журнал очищен.' -f $n)
    Update-JournalList
})

# ============================================================
#  СТАРТ
# ============================================================

$ui.tbVer.Text = ('v{0}' -f $script:PhxVersion)
if ($script:IsAdmin) {
    $ui.tbAdmin.Text = 'ADMIN'
    $ui.bdAdmin.Background = Col '#1C2A1F'
    $ui.tbAdmin.Foreground = Col '#3FBF7F'
} else {
    $ui.tbAdmin.Text = 'БЕЗ ПРАВ (только просмотр)'
    $ui.bdAdmin.Background = Col '#2A2418'
    $ui.tbAdmin.Foreground = Col '#D9A648'
}

Build-TweakList
Build-PlaybookList
Update-Dashboard
Show-Panel -Key 'Dash'
Set-Status 'PHX-HUB готов. Каждый шаг пишется в журнал - откат в разделе ЖУРНАЛ.'

[void]$win.ShowDialog()
Write-PhxLog 'PHX-HUB закрыт'
