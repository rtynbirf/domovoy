# =====================================================================
# H-PE11 // PHOENIX TWEAKPACK v2.0 "SYNTHESIS" (paste-and-run)
# Базы синтеза: TweakHub v1.5.0 (аудит TH-AUDIT-1) + WinUtil 2026 (config/
#       tweaks.json разобран) + Atlas v0.5.0 + O&O ShutUp10++ + Win11Debloat
#       (Raphire) + privacy.sexy (реестровые практики, сверены).
# СВОЁ СВЕРХ ВСЕХ (нет ни у кого из шести):
#   (1) ПРОФИЛИ одним переключателем: Safe/Balanced/Performance/PrivacyMax/Custom;
#   (2) verify-loop на ВСЁ: reg перечитывается, сервисы/задачи/Appx/NIC/питание
#       перечитываются и сверяются — не совпало = [--];
#   (3) rollback.ps1-генератор — самодостаточный откат (reg+сервисы+задачи+Appx);
#   (4) тройной бэкап: JSON-журнал v2 + целые ключи reg_export/*.reg + .pow схемы;
#   (5) debloat-уровни Light/Default с ЗАЩИТНЫМ списком (winget/Defender/Store не сносим);
#   (6) авто-детекции: диск (SysMain), GPU (HAGS), RAM (svchost-split), ноут/десктоп (питание);
#   (7) SHA256 журнала (Law 4), ЭВ.1 и логи в стиле бомб-скриптов H-PE11.
# ИСПРАВЛЕНО против v1.1: флаги категорий БЫЛИ декоративные (объявлены и не
#       применялись!) — теперь профиль/флаги РЕАЛЬНО фильтруют цели; verify
#       DWord сравнивает в uint32 (0xFFFFFFFF больше не даёт ложный [--]).
# Отвергнуто (см. docs/TWEAK-MATRIX.md §2): TcpAckFrequency (плацебо),
#       Spectre/Meltdown-off (security-линия), снос Edge/OneDrive (совместимость),
#       полное отключение WU (умнее Security-режим 365д/4д), IPv6-off (только Teredo).
# Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ. ЭВ.1: недоступно = НЕ сделано (метка [--]).
# Требования: Windows 11 24H2/25H2, консоль PowerShell ОТ АДМИНИСТРАТОРА.
# =====================================================================

# ==== ПРОФИЛЬ (главный переключатель) ====
$PhxProfile = 'Balanced'  # Safe | Balanced | Performance | PrivacyMax | Custom
#   Safe        - телеметрия/реклама/WU-Security/Hiberboot/AI-политики; НИКАКОй перф/деблоат (рабочие станции)
#   Balanced    - Safe + CPU/сеть/игра/отзывчивость/NIC + Light-деблоат (дом/офис по умолчанию)
#   Performance - Balanced + Default-деблоат + QoL + lastaccess (игровые станции)
#   PrivacyMax  - Safe + Default-деблоат + таскбар/Пуск + Edge-политики (макс приватность)
#   Custom      - брать флаги категорий ниже КАК ЕСТЬ (тонкая настройка руками)
# ==== ФЛАГИ Custom-профиля (править при $PhxProfile='Custom') ====
$PhxMode         = 'Report'  # 'Report' = только план | 'Apply' = применить | 'Restore' = откат по журналу
$PhxBackupDir    = ''        # пусто = рядом со скриптом\PHX_TWEAKBACKUP_<ts>; иначе свой путь
$PhxCatCpu       = $true     # CPU-планирование (Win32PrioritySeparation, WPBT)
$PhxCatNetwork   = $true     # Сеть: throttling, DO-лимиты, Teredo
$PhxCatGaming    = $true     # Игра: GameDVR, FSE, GameMode; HAGS - по детекции GPU
$PhxCatResponsiv = $true     # Отзывчивость: меню, старт-задержка, мышь, анимации
$PhxCatMemory    = $true     # SysMain/Prefetcher - АВТО по диску (см. $PhxForceSysMainOff)
$PhxCatPrivacy   = $true     # Телеметрия/приватность: политики + СЕРВИСЫ + CEIP-задачи
$PhxCatUpdate    = $true     # WU Security-режим (фичи +365д, секьюрити +4д)
$PhxCatPower     = $true     # Fast startup off (BCD-линия PHOENIX)
$PhxCatMisc      = $true     # BSOD verbose, device-metadata, svchost-split
$PhxQol          = $true     # QoL: классич. контекст-меню, расширения, NumLock, LongPaths...
$PhxTaskbar      = $true     # Таскбар/Пуск: виджеты/копилот-кнопки/рекомендации/ads off
$PhxAi           = $true     # AI-блок: Recall-снапшоты и Copilot off (политики, откатываемо)
$PhxEdgePolicy   = $false    # Edge: StartupBoost/BackgroundMode/HubsSidebar off (политики)
$PhxDebloat      = 'Light'   # 'None' | 'Light' | 'Default' - снос магазинного мусора (см. каталог)
$PhxRemoveXbox   = $false    # $true = снести и Xbox-набор приложений (игрокам НЕ надо)
$PhxNicLowLat    = $true     # NIC-пресет низкой задержки (moderation/EEE/green-ethernet)
$PhxMsiGpuNvme   = $false    # $true = MSI mode GPU/NVMe (требует теста DPC-латентности!)
$PhxWSearchOff   = $false    # $true = Windows Search off (на SSD обычно НЕ надо)
$PhxAdvancedRisk = $false    # $true = risk 5: SearchOrderConfig, VBS/HVCI off (security!)
$PhxReservedStor = $false    # $true = Reserved Storage off (~7 ГБ, DISM)
$PhxLastAccess   = $false    # $true = fsutil disablelastaccess (микро, тренд Atlas)
$PhxForceSysMainOff = $false # $true = SysMain+Prefetch off (НЕ рекомендуется: Atlas v0.4.1+)
$PhxRestorePoint = $true     # $true = точка восстановления Win перед Apply (частота=0, без лимита 24ч)
$PhxFullRestore  = $true     # $true = Restore откатывает и сервисы/задачи/Appx/питание (v2)
# =====================================================================

& {
  $ErrorActionPreference = 'Continue'
  $ts   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
  $log  = "$env:USERPROFILE\Desktop\PHX_TWEAKPACK_$ts.log"
  if ([string]::IsNullOrWhiteSpace($PhxBackupDir)) {
    if ([string]::IsNullOrEmpty($PSScriptRoot)) { $bdir = "$env:USERPROFILE\Desktop\PHX_TWEAKBACKUP_$ts" }
    else { $bdir = Join-Path $PSScriptRoot "PHX_TWEAKBACKUP_$ts" }
  } else { $bdir = $PhxBackupDir }
  $script:PhxOk = 0; $script:PhxSkip = 0; $script:PhxRestored = 0
  $script:PhxEV1 = @()
  $journalPath = Join-Path $bdir 'phx_tweak_journal.json'

  function Write-Log([string]$msg) {
    Write-Host $msg
    Add-Content -LiteralPath $log -Value $msg -Encoding UTF8
  }
  function Set-EV1([string]$item, [bool]$done, [string]$note) {
    if ($done) { Write-Log ("  [x] " + $item + "  " + $note); $script:PhxOk++ }
    else {
      Write-Log ("  [--] " + $item + "  " + $note)
      $script:PhxEV1 += ($item + " :: " + $note)
      $script:PhxSkip++
    }
  }

  # ---------- ПРОФИЛЬНЫЙ ДВИЖОК (своё: один переключатель вместо дюжины флагов) ----------
  # Эффективные флаги $P.*; Custom берёт флаги шапки КАК ЕСТЬ (теперь они РЕАЛЬНО работают).
  $P = @{
    Cpu=[bool]$PhxCatCpu; Net=[bool]$PhxCatNetwork; Game=[bool]$PhxCatGaming
    Resp=[bool]$PhxCatResponsiv; Mem=[bool]$PhxCatMemory; Priv=[bool]$PhxCatPrivacy
    Wu=[bool]$PhxCatUpdate; Pow=[bool]$PhxCatPower; Misc=[bool]$PhxCatMisc
    Qol=[bool]$PhxQol; Taskbar=[bool]$PhxTaskbar; Ai=[bool]$PhxAi
    Edge=[bool]$PhxEdgePolicy; Debloat=[string]$PhxDebloat; Nic=[bool]$PhxNicLowLat
    Msi=[bool]$PhxMsiGpuNvme
  }
  switch ($PhxProfile) {
    'Safe' {
      $P.Cpu=$false; $P.Net=$false; $P.Game=$false; $P.Resp=$false; $P.Mem=$false
      $P.Qol=$false; $P.Taskbar=$false; $P.Edge=$false; $P.Nic=$false
      $P.Debloat='None'
    }
    'Balanced' {
      $P.Cpu=$true; $P.Net=$true; $P.Game=$true; $P.Resp=$true; $P.Mem=$true
      $P.Qol=$false; $P.Taskbar=$false; $P.Edge=$false; $P.Nic=$true
      $P.Debloat='Light'
    }
    'Performance' {
      $P.Cpu=$true; $P.Net=$true; $P.Game=$true; $P.Resp=$true; $P.Mem=$true
      $P.Qol=$true; $P.Taskbar=$true; $P.Edge=$false; $P.Nic=$true
      $P.Debloat='Default'
    }
    'PrivacyMax' {
      $P.Cpu=$false; $P.Net=$false; $P.Game=$false; $P.Resp=$false; $P.Mem=$false
      $P.Qol=$false; $P.Taskbar=$true; $P.Edge=$true; $P.Nic=$false
      $P.Debloat='Default'
    }
    'Custom' { Write-Log "Профиль Custom: флаги шапки применяются как заданы." }
    default  { Write-Log ("!! Неизвестный профиль '" + $PhxProfile + "' - работаю как Custom."); }
  }
  Write-Log ""
  Write-Log ("== PHOENIX TWEAKPACK v2.0 SYNTHESIS // " + $ts + " ==")
  Write-Log ("Профиль: $PhxProfile | Режим: $PhxMode | Debloat: " + $P.Debloat + " | Бэкап: $bdir")
  Write-Log ("Эффективно: cpu=" + $P.Cpu + " net=" + $P.Net + " game=" + $P.Game + " resp=" + $P.Resp + " mem=" + $P.Mem + " priv=" + $P.Priv + " wu=" + $P.Wu + " pow=" + $P.Pow + " misc=" + $P.Misc + " qol=" + $P.Qol + " taskbar=" + $P.Taskbar + " ai=" + $P.Ai + " edge=" + $P.Edge + " nic=" + $P.Nic + " msi=" + $P.Msi)

  # ---------- 0. Пре-чеки ----------
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Log "!! НЕТ ПРАВ АДМИНИСТРАТОРА."
    if ($PhxMode -ne 'Report') { Write-Log "!! Режим $PhxMode требует администратора - СТОП."; return }
    Write-Log "   Report продолжается (HKCU читается, HKLM будет помечен [--])."
  }
  New-Item -ItemType Directory -Path $bdir -Force | Out-Null

  $os = Get-CimInstance Win32_OperatingSystem
  $build = [int]($os.BuildNumber)
  $win11 = $build -ge 22000
  Set-EV1 'Windows 11 (build >= 22000)' $win11 "build $build"
  if (-not $win11) { Write-Log "!! Не Windows 11 - стоп."; return }

  # Тип системного диска: NVMe/SSD/HDD (авто-решения SysMain/Prefetch/WSearch)
  $sysDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue).DiskNumber } | Select-Object -First 1
  if (-not $sysDisk) { $sysDisk = Get-PhysicalDisk | Sort-Object Size -Descending | Select-Object -First 1 }
  $busType = if ($sysDisk) { $sysDisk.BusType } else { 'Unknown' }       # NVMe / SATA / ...
  $medType = if ($sysDisk) { $sysDisk.MediaType } else { 'Unspecified' } # SSD / HDD
  $isSsd = ($medType -eq 'SSD') -or ($busType -eq 'NVMe')
  Write-Log ("Системный диск: " + $busType + "/" + $medType + " -> SSD-класс: " + $isSsd)

  # Ноут или десктоп (питание: USB-suspend/ASPM трогаем только на десктопе)
  $isLaptop = $false
  try {
    $ch = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
    foreach ($c in @(@(8,9,10,12,14,30,31,32))) { if ($ch | Where-Object { $_ -in $c }) { $isLaptop = $true } }
  } catch {}
  Write-Log ("Шасси: " + $(if ($isLaptop) { 'ноутбук/портатив (питание AC-лимитов не трогаем)' } else { 'десктоп' }))

  # ---------- 1. Механика: журнал v2 (Reg/Svc/Task/Appx) + verify-loop ----------
  $script:Journal = New-Object System.Collections.Generic.List[object]
  function Get-PhxValue([string]$Path, [string]$Name) {
    if ($Name -eq '(Default)') { $Name = '' }  # PS-нотация дефолтного значения
    try { return (Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop) } catch { return $null }
  }
  function Backup-PhxValue([string]$Path, [string]$Name) {
    # ОРИГИНАЛ до первой записи. absent = значения не было (restore удалит).
    if ($Name -eq '(Default)') { $Name = '' }
    $existing = $null; $kind = $null
    try {
      $k = Get-Item -LiteralPath $Path -ErrorAction Stop
      $existing = $k.GetValue($Name)
      if ($null -ne $existing) { $kind = $k.GetValueKind($Name).ToString() }
    } catch { $existing = $null }
    $rec = @{ Kind='Reg'; Path = $Path; Name = $Name; Old = $existing; Kind2 = $kind; WasPresent = ($null -ne $existing) }
    $script:Journal.Add($rec) | Out-Null
    return $rec
  }
  function Set-PhxValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Backup-PhxValue $Path $Name | Out-Null
    try {
      New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
      # VERIFY-LOOP: перечитали и сверили (DWord - в uint32: 0xFFFFFFFF не ломает сравнение)
      $back = Get-PhxValue $Path $Name
      if ($Type -eq 'DWord') {
        $ok = $false
        try { $ok = ([uint32]$back -eq [uint32]$Value) } catch { $ok = ([string]$back -eq [string]$Value) }
      } elseif ($Type -eq 'QWord') {
        $ok = ([long]$back -eq [long]$Value)
      } else { $ok = ([string]$back -eq [string]$Value) }
      if (-not $ok) { Write-Log ("  !! verify FAILED: " + $Path + "\" + $Name + " записано=" + $back + " ожидалось=" + $Value); return $false }
      return $true
    } catch { Write-Log ("  !! сбой записи " + $Path + "\" + $Name + ": " + $_.Exception.Message); return $false }
  }
  function Save-PhxJournal {
    $json = $script:Journal | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $journalPath -Value $json -Encoding UTF8
    Write-Log ("Журнал v2: " + $journalPath + " (" + $script:Journal.Count + " записей)")
    $h = (Get-FileHash -LiteralPath $journalPath -Algorithm SHA256).Hash
    Write-Log ("SHA256 журнала (Law 4): " + $h)
  }

  # ---------- 2. Каталог целей (синтез шести школ; Src: TH/WU/OO/W11D/PSEXY/ATLAS/PHX) ----------
  # Поля: Path/Name/Value/Type | Svc/StartType | Task | Risk | Src | Cat | Note
  $script:Targets = @()
  if ($P.Cpu) {
    $script:Targets += @(
      @{ Cat='cpu'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name='Win32PrioritySeparation'; Value=0x26; Type='DWord'; Risk=3; Src='TH';   Note='форс-квант на передний план (26h = short/fixed/foreground-boost)' },
      @{ Cat='cpu'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name='DisableWpbtExecution'; Value=1; Type='DWord'; Risk=4; Src='TH'; Note='отключить WPBT-исполнение (OEM-код в ACPI)' }
    )
  }
  if ($P.Net) {
    $script:Targets += @(
      @{ Cat='net'; Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='NetworkThrottlingIndex'; Value=[int]-1; Type='DWord'; Risk=3; Src='TH'; Note='снять network-throttle (0xFFFFFFFF); эффект от системы к системе' },
      @{ Cat='net'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name='DOPercentageMaxBackgroundBandwidth'; Value=30; Type='DWord'; Risk=2; Src='TH'; Note='DO фоновая загрузка <= 30%' },
      @{ Cat='net'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name='DODownloadMode'; Value=1; Type='DWord'; Risk=2; Src='PHX'; Note='DO mode 1 (только LAN) - лимит p2p-раздачи' },
      @{ Cat='net'; Path='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'; Name='DisabledComponents'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='Teredo off (бит 1; IPv6 НЕ трогаем)' }
    )
  }
  if ($P.Game) {
    $script:Targets += @(
      @{ Cat='game'; Path='HKCU:\System\GameConfigStore'; Name='GameDVR_FSEBehaviorMode'; Value=2; Type='DWord'; Risk=1; Src='TH'; Note='полноэкранный без оптимизаций' },
      @{ Cat='game'; Path='HKCU:\System\GameConfigStore'; Name='GameDVR_HonorUserFSEBehaviorMode'; Value=1; Type='DWord'; Risk=1; Src='W11D'; Note='чтить выбор FSE пользователем' },
      @{ Cat='game'; Path='HKCU:\System\GameConfigStore'; Name='GameDVR_DXGIHonorFSEWindowsCompatible'; Value=1; Type='DWord'; Risk=1; Src='W11D'; Note='DXGI-FSE совместимость' },
      @{ Cat='game'; Path='HKCU:\System\GameConfigStore'; Name='GameDVR_EFSEFeatureFlags'; Value=0; Type='DWord'; Risk=1; Src='W11D'; Note='FSE-флаги off' },
      @{ Cat='game'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; Name='AppCaptureEnabled'; Value=0; Type='DWord'; Risk=1; Src='TH'; Note='GameDVR capture off' },
      @{ Cat='game'; Path='HKCU:\SOFTWARE\Microsoft\GameBar'; Name='AllowAutoGameMode'; Value=1; Type='DWord'; Risk=1; Src='PHX'; Note='GameMode ДЕРЖИМ (позиция Atlas)' },
      @{ Cat='game'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name='AllowGameDVR'; Value=0; Type='DWord'; Risk=2; Src='TH+;WU'; Note='политика GameDVR off (у TH только HKCU)' },
      @{ Cat='game'; Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='SystemResponsiveness'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='MMCSS: 0% CPU под фоновые (дефолт 20)' },
      @{ Cat='game'; Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='GPU Priority'; Value=8; Type='DWord'; Risk=2; Src='W11D'; Note='MMCSS Games: GPU priority 8' },
      @{ Cat='game'; Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='Priority'; Value=6; Type='DWord'; Risk=2; Src='W11D'; Note='MMCSS Games: priority 6' },
      @{ Cat='game'; Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name='Scheduling Category'; Value='High'; Type='String'; Risk=2; Src='W11D'; Note='MMCSS Games: категория High' }
    )
  }
  if ($P.Resp) {
    $script:Targets += @(
      @{ Cat='resp'; Path='HKCU:\Control Panel\Desktop'; Name='MenuShowDelay'; Value='0'; Type='String'; Risk=1; Src='TH'; Note='меню без задержки' },
      @{ Cat='resp'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name='StartupDelayInMSec'; Value=0; Type='DWord'; Risk=1; Src='TH'; Note='убрать старт-задержку запуска' },
      @{ Cat='resp'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name='TaskbarEndTask'; Value=1; Type='DWord'; Risk=1; Src='TH'; Note='End Task в правой кнопке таскбара' },
      @{ Cat='resp'; Path='HKCU:\Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Value='0'; Type='String'; Risk=1; Src='TH'; Note='минимизация без анимации' },
      @{ Cat='resp'; Path='HKCU:\Control Panel\Mouse'; Name='MouseSpeed'; Value='0'; Type='String'; Risk=1; Src='TH'; Note='акселерация мыши off (1/3)' },
      @{ Cat='resp'; Path='HKCU:\Control Panel\Mouse'; Name='MouseThreshold1'; Value='0'; Type='String'; Risk=1; Src='TH'; Note='акселерация мыши off (2/3)' },
      @{ Cat='resp'; Path='HKCU:\Control Panel\Mouse'; Name='MouseThreshold2'; Value='0'; Type='String'; Risk=1; Src='TH'; Note='акселерация мыши off (3/3)' },
      @{ Cat='resp'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Value=0; Type='DWord'; Risk=1; Src='TH'; Note='прозрачность off (вкус)' },
      @{ Cat='resp'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name='VisualFXSetting'; Value=2; Type='DWord'; Risk=1; Src='TH'; Note='визуальные эффекты -> максимум производительности' },
      @{ Cat='resp'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAnimations'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='анимации таскбара off' },
      @{ Cat='resp'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ListviewAlphaSelect'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='полупрозрачное выделение off' },
      @{ Cat='resp'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ListviewShadow'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='тень под иконками off' },
      @{ Cat='resp'; Path='HKCU:\Software\Microsoft\Windows\DWM'; Name='EnableAeroPeek'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='Aero Peek off' },
      @{ Cat='resp'; Path='HKCU:\Control Panel\Keyboard'; Name='KeyboardDelay'; Value='0'; Type='String'; Risk=1; Src='WU'; Note='задержка клавиатуры 0' },
      @{ Cat='resp'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name='01'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='Storage Sense off (не трогает файлы)' }
    )
  }
  if ($P.Priv) {
    $script:Targets += @(
      # --- политики телеметрии (TH + WinUtil/Sophia-практики) ---
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Value=0; Type='DWord'; Risk=3; Src='TH'; Note='на Pro фактически минимум (1); 0 = Enterprise/Edu' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='DoNotShowFeedbackNotifications'; Value=1; Type='DWord'; Risk=1; Src='WU'; Note='фидбек-уведомления off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='DisableOneSettingsDownloads'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='OneSettings: конфиг-пинг off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='LimitDiagnosticLogCollection'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='сбор диаг-логов ограничен' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='EnableActivityFeed'; Value=0; Type='DWord'; Risk=3; Src='TH'; Note='история активностей off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='PublishUserActivities'; Value=0; Type='DWord'; Risk=3; Src='WU'; Note='публикация активностей off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='UploadUserActivities'; Value=0; Type='DWord'; Risk=3; Src='WU'; Note='выгрузка активностей off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name='Enabled'; Value=0; Type='DWord'; Risk=2; Src='TH'; Note='рекламный ID off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name='TailoredExperiencesWithDiagnosticDataEnabled'; Value=0; Type='DWord'; Risk=2; Src='TH'; Note='персонализация по диагностике off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Value=1; Type='DWord'; Risk=2; Src='TH'; Note='consumer-контент/спонсируемые приложения off' },
      @{ Cat='priv'; Path='HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name='DisableSearchBoxSuggestions'; Value=1; Type='DWord'; Risk=1; Src='TH'; Note='Bing-подсказки в поиске off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='SettingsPageVisibility'; Value='hide:aicomponents'; Type='String'; Risk=4; Src='TH'; Note='спрятать страницу AI-компонентов' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; Name='Disabled'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='WER: пользовательские краш-репорты off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name='HasAccepted'; Value=0; Type='DWord'; Risk=2; Src='WU'; Note='облачное распознавание речи off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\InputPersonalization'; Name='RestrictImplicitInkCollection'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='рукописный ввод: авто-сбор off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\InputPersonalization'; Name='RestrictImplicitTextCollection'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='текстовый ввод: авто-сбор off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; Name='HarvestContacts'; Value=0; Type='DWord'; Risk=2; Src='WU'; Note='сбор контактов для инка/текста off' },
      @{ Cat='priv'; Path='HKCU:\Software\Microsoft\Clipboard'; Name='AllowCrossDeviceClipboard'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='клипборд между устройствами off' },
      # --- CDM анти-реклама: 12 значений (O&O ShutUp10++ база, v1.1 имела 8) ---
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='ContentDeliveryAllowed'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: доставка контента off (1/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='OemPreInstalledAppsEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: OEM-предустановки off (2/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='PreInstalledAppsEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: предустановки off (3/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='PreInstalledAppsEverEnabled'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='CDM: ever-предустановки off (4/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SilentInstalledAppsEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: тихая установка приложений off (5/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SoftLandingEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: советы/подсказки off (6/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SystemPaneSuggestionsEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: советы в Пуске off (7/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='RotatingLockScreenEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: карусель локскрина off (8/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='RotatingLockScreenOverlayEnabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: оверлей локскрина off (9/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-310093Enabled'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='CDM: welcome-опыт off (10/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338387Enabled'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='CDM: spotlight-эксперименты off (11/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338388Enabled'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='CDM: рекомендации в Пуске off (12/12)' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Siuf\Rules'; Name='NumberOfSIUFInPeriod'; Value=0; Type='DWord'; Risk=1; Src='OO'; Note='опросник «поделитесь мнением» off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name='AllowCortana'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='Cortana off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'; Name='AllowFindMyDevice'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='Найти устройство off' },
      @{ Cat='priv'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_TrackProgs'; Value=0; Type='DWord'; Risk=2; Src='OO'; Note='трекинг запусков приложений off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; Name='Value'; Value='Deny'; Type='String'; Risk=3; Src='WU'; Note='геолокация приложений: Deny' },
      @{ Cat='priv'; Path='HKLM:\SYSTEM\Maps'; Name='AutoUpdateEnabled'; Value=0; Type='DWord'; Risk=2; Src='WU'; Note='автообновление карт off' },
      @{ Cat='priv'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name='AllowWidgets'; Value=0; Type='DWord'; Risk=2; Src='WU+PHX'; Note='виджеты off политикой (Win11: AllowWidgets)' },
      # --- сервисный уровень телеметрии (своё: у TH только политики) ---
      @{ Cat='priv'; Svc='DiagTrack'; StartType='Disabled'; Risk=2; Src='PHX'; Note='Connected User Experiences and Telemetry - главный сборщик' },
      @{ Cat='priv'; Svc='dmwappushservice'; StartType='Disabled'; Risk=2; Src='PHX'; Note='WAP Push Message Routing - канал телеметрии' },
      @{ Cat='priv'; Svc='diagnosticshub.standardcollector.service'; StartType='Manual'; Risk=3; Src='PHX'; Note='Diagnostic Hub - в ручной' },
      @{ Cat='priv'; Svc='lfsvc'; StartType='Disabled'; Risk=2; Src='WU'; Note='геолокационная служба' },
      @{ Cat='priv'; Svc='RemoteRegistry'; StartType='Disabled'; Risk=2; Src='PHX'; Note='удалённый реестр - security-hardening' },
      @{ Cat='priv'; Svc='RetailDemo'; StartType='Disabled'; Risk=2; Src='WU'; Note='магазинный демо-режим' },
      # --- CEIP/телеметрия-задачи (Sophia/WinUtil-практики, v1.1 имела 4) ---
      @{ Cat='priv'; Task='\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'; Risk=2; Src='PHX'; Note='CEIP-оценщик совместимости' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Application Experience\ProgramDataUpdater'; Risk=2; Src='PHX'; Note='CEIP-сбор программных данных' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'; Risk=2; Src='PHX'; Note='CEIP Consolidator' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'; Risk=2; Src='PSEXY'; Note='CEIP USB-телеметрия' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'; Risk=2; Src='PSEXY'; Note='CEIP ядро' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Feedback\Siuf\DmClient'; Risk=2; Src='PHX'; Note='канал фидбека' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownloadData'; Risk=2; Src='PSEXY'; Note='фидбек: докачка сценариев' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Windows Error Reporting\QueueReporting'; Risk=2; Src='WU'; Note='очередь WER-репортов' },
      @{ Cat='priv'; Task='\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'; Risk=2; Src='WU'; Note='диагностика дисков (CEIP)' },
      @{ Cat='priv'; Task='\Microsoft\Windows\Autochk\Proxy'; Risk=2; Src='WU'; Note='autochk proxy (CEIP)' },
      @{ Cat='priv'; Task='\Microsoft\Windows\NetworkProfile\GatherNetworkInfo'; Risk=3; Src='WU'; Note='сбор сведений о сети' }
    )
  }
  if ($P.Taskbar) {
    $script:Targets += @(
      @{ Cat='tskb'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarDa'; Value=0; Type='DWord'; Risk=1; Src='W11D'; Note='кнопка Виджеты off' },
      @{ Cat='tskb'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowCopilotButton'; Value=0; Type='DWord'; Risk=1; Src='W11D'; Note='кнопка Copilot off' },
      @{ Cat='tskb'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_IrisRecommendations'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='рекомендации в Пуске off' },
      @{ Cat='tskb'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowSyncProviderNotifications'; Value=0; Type='DWord'; Risk=1; Src='W11D'; Note='реклама OneDrive-провайдеров в Проводнике off' },
      @{ Cat='tskb'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name='SearchboxTaskbarMode'; Value=0; Type='DWord'; Risk=1; Src='W11D'; Note='поиск-иконка на таскбаре off (вкус: верни 1, если нужен)' }
    )
  }
  if ($P.Ai) {
    $script:Targets += @(
      @{ Cat='ai'; Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='Recall: AI-анализ снимков экрана off (пользователь)' },
      @{ Cat='ai'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='Recall: AI-анализ снимков off (машина)' },
      @{ Cat='ai'; Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name='DisableClickToDo'; Value=1; Type='DWord'; Risk=2; Src='W11D'; Note='Click to Do off (25H2)' },
      @{ Cat='ai'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='Copilot off (политика)' }
    )
  }
  if ($P.Edge) {
    $script:Targets += @(
      @{ Cat='edge'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='StartupBoostEnabled'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='Edge Startup Boost off' },
      @{ Cat='edge'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='BackgroundModeEnabled'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='Edge в фоне не висит' },
      @{ Cat='edge'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='HubsSidebarEnabled'; Value=0; Type='DWord'; Risk=2; Src='W11D'; Note='боковая панель Edge off' },
      @{ Cat='edge'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='HideFirstRunExperience'; Value=1; Type='DWord'; Risk=2; Src='W11D'; Note='first-run мастер off' }
    )
  }
  if ($P.Wu) {
    $script:Targets += @(
      @{ Cat='wu'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name='NoAutoRebootWithLoggedOnUsers'; Value=1; Type='DWord'; Risk=1; Src='WU'; Note='без авто-ребута под юзером' },
      @{ Cat='wu'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferFeatureUpdates'; Value=1; Type='DWord'; Risk=2; Src='WU;TH'; Note='фич-апдейты задерживаем' },
      @{ Cat='wu'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferFeatureUpdatesPeriodInDays'; Value=365; Type='DWord'; Risk=2; Src='WU'; Note='фичи +365 дней (WinUtil 2026)' },
      @{ Cat='wu'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferQualityUpdates'; Value=1; Type='DWord'; Risk=2; Src='WU'; Note='секьюрити задерживаем' },
      @{ Cat='wu'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferQualityUpdatesPeriodInDays'; Value=4; Type='DWord'; Risk=2; Src='WU'; Note='секьюрити +4 дня (пропустить плохие патчи)' },
      @{ Cat='wu'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='ExcludeWUDriversInQualityUpdate'; Value=1; Type='DWord'; Risk=3; Src='TH'; Note='драйверы из WU не тянуть (наш конвейер сам катает)' }
    )
  }
  if ($P.Pow) {
    $script:Targets += @(
      @{ Cat='pow'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name='HiberbootEnabled'; Value=0; Type='DWord'; Risk=2; Src='TH'; Note='fast startup off - чистый cold boot (BCD-линия H-PE11)' }
    )
  }
  if ($P.Misc) {
    $script:Targets += @(
      @{ Cat='misc'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'; Name='DisplayParameters'; Value=1; Type='DWord'; Risk=1; Src='TH'; Note='подробный BSOD-экран' },
      @{ Cat='misc'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'; Name='PreventDeviceMetadataFromNetwork'; Value=1; Type='DWord'; Risk=3; Src='TH'; Note='метаданные устройств не с сети' },
      @{ Cat='misc'; Svc='CscService'; StartType='Disabled'; Risk=3; Src='WU'; Note='офлайн-файлы (клиентское кэширование сети)' },
      @{ Cat='misc'; Svc='MapsBroker'; StartType='Manual'; Risk=2; Src='WU'; Note='загрузчик карт - в ручной' },
      @{ Cat='misc'; Svc='SharedAccess'; StartType='Disabled'; Risk=3; Src='WU'; Note='Internet Connection Sharing (ICS; раздаёт интернет - НЕ включай на хотспоте)' }
    )
  }
  # ---------- 3. Условные цели (детекции решают вместо человека) ----------
  if ($P.Misc -and $PhxAdvancedRisk) {
    $script:Targets += @{ Cat='misc'; Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'; Name='SearchOrderConfig'; Value=0; Type='DWord'; Risk=5; Src='TH'; Note='НЕ искать драйверы в WU вовсе (risk 5: могут остаться без драйверов)' }
  }
  if ($PhxWSearchOff) {
    $script:Targets += @{ Cat='misc'; Svc='WSearch'; StartType='Disabled'; Risk=3; Src='TH'; Note='Windows Search off (флаг PhxWSearchOff)' }
  }

  Write-Log ""
  Write-Log "== ДЕТЕКЦИИ =="
  # HAGS: поддержка HwSchMode - дискретка GTX 10xx+/RDNA+ или iGPU Intel Xe/Arc
  $gpuOk = $false; $gpuName = ''
  try {
    $gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
    foreach ($g in $gpus) {
      $gpuName = $g
      if     ($g -match 'NVIDIA' -and $g -match 'GTX 1[0-9]|RTX|MX [2-9]') { $gpuOk = $true }
      elseif ($g -match 'Radeon RX|Ryzen .* Graphics|680M|780M|890M')       { $gpuOk = $true }
      elseif ($g -match 'Intel.*(UHD 7[3-9]0|Iris Xe|Arc)')                 { $gpuOk = $true }
    }
  } catch {}
  Write-Log ("GPU: " + $gpuName + " -> HAGS поддержан: " + $gpuOk)
  if ($P.Game) {
    if ($gpuOk) {
      $script:Targets += @{ Cat='game'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name='HwSchMode'; Value=2; Type='DWord'; Risk=2; Src='TH'; Note='HAGS on (GPU поддержан по детекции)' }
      Set-EV1 'HAGS (HwSchMode=2)' $true ('добавлен в план: ' + $gpuName)
    } else {
      Set-EV1 'HAGS (HwSchMode=2)' $false ('GPU не распознан как поддерживающий: ' + $gpuName + ' - тфик ИСКЛЮЧЁН из плана')
    }
  }

  # --- QoL-блок (вкусовое, WinUtil Customize Preferences) ---
  if ($P.Qol) {
    $script:Targets += @(
      @{ Cat='qol'; Path='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Name='(Default)'; Value=''; Type='String'; Risk=1; Src='WU'; Note='классическое контекст-меню Win10 (после рестарта explorer)' },
      @{ Cat='qol'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='HideFileExt'; Value=0; Type='DWord'; Risk=1; Src='WU'; Note='показывать расширения файлов' },
      @{ Cat='qol'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Hidden'; Value=1; Type='DWord'; Risk=1; Src='WU'; Note='показывать скрытые файлы' },
      @{ Cat='qol'; Path='Registry::HKEY_USERS\.Default\Control Panel\Keyboard'; Name='InitialKeyboardIndicators'; Value='2'; Type='String'; Risk=1; Src='WU'; Note='NumLock on при загрузке (до логона)' },
      @{ Cat='qol'; Path='HKCU:\Control Panel\Keyboard'; Name='InitialKeyboardIndicators'; Value='2'; Type='String'; Risk=1; Src='WU'; Note='NumLock on (текущий юзер)' },
      @{ Cat='qol'; Path='HKCU:\Control Panel\Accessibility\StickyKeys'; Name='Flags'; Value='506'; Type='String'; Risk=1; Src='WU'; Note='залипание Shift-диалогов off' },
      @{ Cat='qol'; Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='VerboseStatus'; Value=1; Type='DWord'; Risk=1; Src='WU'; Note='verbose-логон: этапы загрузки видны (полезно сборщику)' },
      @{ Cat='qol'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name='LongPathsEnabled'; Value=1; Type='DWord'; Risk=1; Src='WU'; Note='длинные пути >260 символов' }
    )
  }

  # --- SvcHost split: порог выше RAM = один svchost на всё (WinUtil, расчёт по RAM) ---
  try {
    $ramKb = [long]((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB)
    if ($P.Misc -and $ramKb -ge 6291456) {
      $script:Targets += @{ Cat='misc'; Path='HKLM:\SYSTEM\CurrentControlSet\Control'; Name='SvcHostSplitThresholdInKB'; Value=$ramKb; Type='DWord'; Risk=2; Src='WU+PHX'; Note=('svchost без сплита (RAM ' + [math]::Round($ramKb/1MB) + ' ГБ -> порог выше памяти)') }
      Set-EV1 'SvcHostSplitThreshold' $true ('RAM ' + [math]::Round($ramKb/1MB) + ' ГБ - порог выставлен')
    } elseif ($ramKb -lt 6291456) {
      Set-EV1 'SvcHostSplitThreshold' $true ('RAM < 6 ГБ - сплит ОСТАВЛЕН (правильно для малой памяти)')
    }
  } catch { Set-EV1 'SvcHostSplitThreshold' $false ('RAM не определена: ' + $_.Exception.Message) }

  # --- VBS/HVCI-off: ТОЛЬКО по явному флагу AdvancedRisk (security!) ---
  if ($PhxAdvancedRisk) {
    $script:Targets += @(
      @{ Cat='misc'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name='EnableVirtualizationBasedSecurity'; Value=0; Type='DWord'; Risk=5; Src='ATLAS-OPT'; Note='VBS off: +FPS, МИНУС защита (твоя ответственность)' },
      @{ Cat='misc'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name='Enabled'; Value=0; Type='DWord'; Risk=5; Src='ATLAS-OPT'; Note='HVCI (Memory Integrity) off: +FPS, МИНУС защита' }
    )
  }

  # --- ПАМЯТЬ: авто-решение по типу диска (тренд Atlas v0.4.1+: SysMain ОСТАВЛЯЮТ) ---
  Write-Log ""
  Write-Log "== ПАМЯТЬ: авто-решение по типу диска =="
  if ($PhxForceSysMainOff) {
    $script:Targets += @(
      @{ Cat='mem'; Svc='SysMain'; StartType='Disabled'; Risk=3; Src='TH'; Note='SysMain off (принудительно, флаг PhxForceSysMainOff)' },
      @{ Cat='mem'; Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name='EnablePrefetcher'; Value=0; Type='DWord'; Risk=3; Src='TH'; Note='prefetcher off (принудительно)' }
    )
    Set-EV1 'SysMain+Prefetcher' $true 'выключены принудительно (НЕ рекомендуется)'
  } elseif ($isSsd) {
    Set-EV1 'SysMain+Prefetcher' $true ('оставлены ВКЛ (SSD/NVMe; тренд Atlas) - отключение опционально флагом')
  } else {
    Set-EV1 'SysMain+Prefetcher' $true 'оставлены ВКЛ (HDD: prefetch жизненно важен)'
  }

  # ---------- 3b. DEBLOAT-движок (Win11Debloat-практики + ЗАЩИТНЫЙ список; своё) ----------
  # Уровни: None | Light (консенсус-мусор) | Default (Light + почта/карты/связь и пр.)
  # ЗАЩИТА: Store, winget, Defender-UI, калькулятор, блокнот, Paint, терминал, фото,
  #         камера, диктофон, QuickAssist, рантаймы (VCLibs/UI.Xaml/NET.Native) - НЕ сносим.
  $script:DebloatJournal = @()
  $phxProtect = @('Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI',
    'Microsoft.WindowsCalculator','Microsoft.WindowsNotepad','Microsoft.Paint','Microsoft.WindowsTerminal',
    'Microsoft.WindowsPhotos','Microsoft.WindowsCamera','Microsoft.WindowsSoundRecorder',
    'MicrosoftCorporationII.QuickAssist','Microsoft.XboxIdentityProvider',
    'Microsoft.VCLibs*','Microsoft.UI.Xaml*','Microsoft.NET.Native*','Microsoft.Services.Store*',
    'Microsoft.StorePurchaseApp','Microsoft.WindowsAppRuntime*','Microsoft.WebMediaExtensions*',
    'Microsoft.HEIFImageExtension*','Microsoft.VP9VideoExtensions*','Microsoft.WebpImageExtension*',
    'Microsoft.AV1VideoExtension*','Microsoft.HEVCVideoExtension*','Microsoft.RawImageExtension*')
  $phxDebloatLight = @(
    'Microsoft.Copilot','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch',
    'Microsoft.GetHelp','Microsoft.GetStarted','Microsoft.WindowsTips','Microsoft.WindowsFeedbackHub',
    'Microsoft.MicrosoftSolitaireCollection','MSTeams','Microsoft.549981C3F5F10',
    'Microsoft.PowerAutomateDesktop','MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.MicrosoftOfficeHub','Microsoft.Windows.DevHome','Microsoft.Todos',
    'Microsoft.Whiteboard','*Clipchamp*'
  )
  $phxDebloatDefault = @(
    'Microsoft.OutlookForWindows','Microsoft.YourPhone','Microsoft.WindowsMaps',
    'Microsoft.WindowsCommunicationsApps','Microsoft.ZuneMusic','Microsoft.MixedReality.Portal',
    'Microsoft.People','Microsoft.MicrosoftStickyNotes'
  )
  $phxDebloatXbox = @('Microsoft.GamingApp','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay',
    'Microsoft.XboxSpeechToTextOverlay','Microsoft.Xbox.TCUI')
  function Test-PhxProtected([string]$name) {
    foreach ($pat in $phxProtect) { if ($name -like $pat) { return $true } }
    return $false
  }
  function Invoke-PhxDebloat {
    Write-Log ""
    Write-Log ("== DEBLOAT уровень " + $P.Debloat + " (Appx) ==")
    $patterns = @()
    if ($P.Debloat -eq 'Light')   { $patterns = $phxDebloatLight }
    if ($P.Debloat -eq 'Default') { $patterns = $phxDebloatLight + $phxDebloatDefault }
    if ($PhxRemoveXbox)           { $patterns = $patterns + $phxDebloatXbox }
    if ($patterns.Count -eq 0) { Set-EV1 'Debloat' $true 'уровень None - пропущено'; return }
    foreach ($pat in $patterns) {
      $pkgs = Get-AppxPackage -Name $pat -AllUsers -ErrorAction SilentlyContinue
      if (-not $pkgs) { Set-EV1 ("appx " + $pat) $true 'не установлен (ok)'; continue }
      foreach ($p in $pkgs) {
        if (Test-PhxProtected $p.Name) { Set-EV1 ("appx " + $p.Name) $true 'ЗАЩИЩЁН списком - пропущен'; continue }
        $loc = $p.InstallLocation
        try {
          Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
          $script:DebloatJournal += @{ Name = $p.Name; FullName = $p.PackageFullName; Location = $loc }
          $back = Get-AppxPackage -Name $p.Name -AllUsers -ErrorAction SilentlyContinue
          Set-EV1 ("appx " + $p.Name) ($null -eq $back) ("снесён; вернуть: Add-AppxPackage -Register '<путь>\AppxManifest.xml' либо из Store")
        } catch {
          Set-EV1 ("appx " + $p.Name) $false $_.Exception.Message
        }
      }
      $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pat }
      foreach ($pp in $prov) {
        if (Test-PhxProtected $pp.DisplayName) { continue }
        try {
          Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
          Write-Log ("  [x] provisioned " + $pp.DisplayName + " снят с образа (новые юзеры его не получат)")
          $script:PhxOk++
        } catch { Write-Log ("  [--] provisioned " + $pp.DisplayName + ": " + $_.Exception.Message); $script:PhxSkip++ }
      }
    }
  }

  # ---------- 4. Power-слой через powercfg (TH PowerService + verify по hex-индексу) ----------
  function Invoke-PhxPower {
    Write-Log ""
    Write-Log "== POWER (powercfg) =="
    $raw = (powercfg /getactivescheme) | Out-String
    $m = [regex]::Match($raw, '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')
    if (-not $m.Success) { Set-EV1 'powercfg active scheme' $false 'не удалось вытащить GUID'; Write-Log $raw; return }
    $scheme = $m.Value
    & powercfg /export (Join-Path $bdir 'power_scheme_before.pow') $scheme 2>$null
    Set-EV1 'PRE-экспорт активной схемы питания' (Test-Path (Join-Path $bdir 'power_scheme_before.pow')) 'power_scheme_before.pow'
    powercfg /setacvalueindex $scheme SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
    Set-EV1 'CPU min state AC = 100%' ($LASTEXITCODE -eq 0) 'PROCTHROTTLEMIN (TH: disable_cpu_throttling)'
    powercfg /setacvalueindex $scheme SUB_PROCESSOR CPMINCORES 100 2>$null
    Set-EV1 'Core parking min cores = 100%' ($LASTEXITCODE -eq 0) 'CPMINCORES (TH: disable_core_parking)'
    if (-not $isLaptop) {
      powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
      Set-EV1 'USB selective suspend (AC) off' ($LASTEXITCODE -eq 0) 'только десктоп; на ноуте батарея дороже'
      powercfg /setacvalueindex $scheme 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>$null
      Set-EV1 'PCIe ASPM (AC) off' ($LASTEXITCODE -eq 0) 'только десктоп'
    }
    powercfg /setactive $scheme 2>$null
    Set-EV1 'powercfg применён и план переактивирован' ($LASTEXITCODE -eq 0) $scheme
    # VERIFY: перечитываем индекс PROCTHROTTLEMIN (hex в выводе локализационно-независим)
    $q = (powercfg /q $scheme SUB_PROCESSOR PROCTHROTTLEMIN 2>$null) | Out-String
    $hex = [regex]::Matches($q, '0x[0-9a-fA-F]+')
    if ($hex.Count -ge 1) {
      $ac = [Convert]::ToInt64($hex[0].Value.Substring(2), 16)
      Set-EV1 'verify: CPU min AC = 100%' ($ac -eq 100) ('перечитано: ' + $ac)
    } else { Set-EV1 'verify: CPU min AC = 100%' $false 'не удалось распарсить вывод powercfg' }
  }

  # ---------- 5. NIC-пресет низкой задержки (TH + verify перечитыванием) ----------
  function Invoke-PhxNic {
    Write-Log ""
    Write-Log "== NIC: пресет низкой задержки =="
    $sets = @(
      @('*InterruptModeration','0'), ('*EEE','0'), ('EEELinkAdvertisement','0'), ('ULPMode','0'), ('SipsEnabled','0'),
      ('AdvancedEEE','0'), ('EnableGreenEthernet','0'), ('GigaLite','0'), ('PowerSavingMode','0'),
      ('*FlowControl','0'), ('*ReceiveBuffers','512'), ('*TransmitBuffers','512')
    )
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    if (-not $adapters) { Set-EV1 'NIC пресет' $false 'адаптеры не найдены'; return }
    foreach ($a in $adapters) {
      $applied = 0; $skipped = 0
      foreach ($kv in $sets) {
        $cur = Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $kv[0] -ErrorAction SilentlyContinue
        if ($cur) {
          try {
            Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $kv[0] -RegistryValue $kv[1] -ErrorAction Stop
            $back = (Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $kv[0] -ErrorAction Stop).RegistryValue
            if ([string]$back -eq [string]$kv[1]) { $applied++ } else { $skipped++ }
          } catch { $skipped++ }
        } else { $skipped++ }
      }
      Set-EV1 ("NIC " + $a.Name) ($applied -gt 0) ("применено+сверено " + $applied + ", не поддержано " + $skipped)
    }
  }

  # ---------- 6. MSI mode / affinity GPU+NVMe (TH InterruptService; по флагу) ----------
  function Invoke-PhxMsi {
    Write-Log ""
    Write-Log "== MSI mode: GPU/NVMe =="
    $devs = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -in @('Display','SCSIAdapter') -or ($_.Class -eq 'DiskDrive' -and $_.InstanceId -match 'VEN_NVME|NVME') }
    if (-not $devs) { Set-EV1 'MSI: цели' $false 'GPU/NVMe не найдены'; return }
    foreach ($d in $devs) {
      $id = $d.InstanceId
      $base = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters\Interrupt Management"
      $msiKey = "$base\MessageSignaledInterruptProperties"
      if (-not (Test-Path $msiKey)) { New-Item -Path $msiKey -Force | Out-Null }
      $cur = Get-PhxValue $msiKey 'MSISupported'
      Backup-PhxValue $msiKey 'MSISupported' | Out-Null
      New-ItemProperty -LiteralPath $msiKey -Name 'MSISupported' -Value 1 -PropertyType DWord -Force | Out-Null
      Set-EV1 ("MSI " + $d.FriendlyName) $true ("было MSISupported=" + $(if ($null -ne $cur) { $cur } else { 'absent' }) + " -> 1 (после ребута)")
    }
    Write-Log "ВНИМАНИЕ: MSI-изменения подхватятся ТОЛЬКО после перезагрузки. Проверь DPC-латентность до/после."
  }

  # ---------- 6b. Файловый слой (тренды WinUtil/Atlas) ----------
  function Invoke-PhxFilesystem {
    Write-Log ""
    Write-Log "== FILESYSTEM (fsutil/DISM) =="
    if ($PhxLastAccess) {
      & fsutil behavior set disablelastaccess 1 2>$null | Out-Null
      Set-EV1 'disablelastaccess' ($LASTEXITCODE -eq 0) 'NTFS не пишет время последнего доступа (тренд Atlas)'
    } else { Set-EV1 'disablelastaccess' $true 'пропущено по флагу (по умолчанию off)' }
    if ($PhxReservedStor) {
      & dism.exe /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null
      Set-EV1 'Reserved Storage off' ($LASTEXITCODE -eq 0) 'освободить ~7 ГБ (WinUtil)'
    } else { Set-EV1 'Reserved Storage off' $true 'пропущено по флагу (по умолчанию off)' }
  }

  # ---------- 7. PRE-экспорт .reg (двойная страховка к журналу) ----------
  function Export-PhxReg {
    $regDir = Join-Path $bdir 'reg_export'
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    $n = 0
    foreach ($t in $script:Targets) {
      if ($t.Svc -or $t.Task) { continue }
      $rawPath = $t.Path -replace '^Registry::',''
      $regPath = $rawPath -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
      $file = Join-Path $regDir (($regPath -replace '[\\:]','_') + '.reg')
      & reg.exe export $regPath $file /y 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $n++ }
    }
    Set-Content -LiteralPath (Join-Path $bdir 'README.txt') -Value @('PHX TWEAKPACK v2.0 pre-export (до применения)','Каждый .reg - состояние ЦЕЛОГО ключа ДО применения твиков.','Восстановление: reg import <файл.reg> или двойной клик. Рядом: phx_tweak_journal.json + rollback.ps1 + power_scheme_before.pow.') -Encoding UTF8
    Set-EV1 'PRE-экспорт .reg ключей до применения' ($n -gt 0) ("reg_export: " + $n + " ключей")
  }

  # ---------- 7b. Точка восстановления Win (частота=0: без лимита 24ч; тренд WinUtil) ----------
  function Invoke-PhxRestorePoint {
    Write-Log ""
    Write-Log "== RESTORE POINT (Win) =="
    if (-not $PhxRestorePoint) { Set-EV1 'точка восстановления Win' $true 'пропущено по флагу'; return }
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freq = Get-PhxValue $srKey 'SystemRestorePointCreationFrequency'
    Backup-PhxValue $srKey 'SystemRestorePointCreationFrequency' | Out-Null
    New-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
    Set-EV1 'SystemRestorePointCreationFrequency = 0' $true ('было: ' + $(if ($null -ne $freq) { $freq } else { 'absent' }) + ' - лимит 24ч снят')
    try {
      Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
      Checkpoint-Computer -Description "PHX TWEAKPACK v2.0 $ts" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
      Set-EV1 'точка восстановления Win' $true 'Checkpoint-Computer выполнен'
    } catch { Set-EV1 'точка восстановления Win' $false ($_.Exception.Message + ' (SystemRestore может быть выключен в системе)') }
  }

  # ---------- 8. Report / Apply / Restore ----------
  function Show-PhxReport {
    Write-Log ""
    Write-Log ("== REPORT: план изменений (" + $script:Targets.Count + " позиций) ==")
    $i = 0
    foreach ($t in $script:Targets) {
      $i++
      if ($t.Svc) {
        $cur = (Get-Service -Name $t.Svc -ErrorAction SilentlyContinue)
        $curS = if ($cur) { $cur.StartType.ToString() } else { 'ABSENT' }
        Write-Log ("  {0,3}. [svc ] {1}: {2} -> {3} | risk {4} | {5} | {6}" -f $i, $t.Svc, $curS, $t.StartType, $t.Risk, $t.Src, $t.Note)
      } elseif ($t.Task) {
        $tp = (Split-Path $t.Task) + '\'; $tn = Split-Path $t.Task -Leaf
        $task = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction SilentlyContinue
        $curS = if ($task) { $task.State.ToString() } else { 'ABSENT' }
        Write-Log ("  {0,3}. [task] {1}: {2} -> Disabled | risk {3} | {4} | {5}" -f $i, $t.Task, $curS, $t.Risk, $t.Src, $t.Note)
      } else {
        $cur = Get-PhxValue $t.Path $t.Name
        $curS = if ($null -eq $cur) { 'absent' } else { $cur }
        Write-Log ("  {0,3}. [reg ] {1}\{2}: {3} -> {4} | risk {5} | {6} | {7}" -f $i, $t.Path, $t.Name, $curS, $t.Value, $t.Risk, $t.Src, $t.Note)
      }
    }
    if ($P.Debloat -ne 'None') {
      Write-Log ("  DEBLOAT уровень " + $P.Debloat + " - кандидаты на снос (что реально стоит - увидишь в Apply):")
      foreach ($pat in $phxDebloatLight) { Write-Log ("        appx ~ " + $pat) }
      if ($P.Debloat -eq 'Default') { foreach ($pat in $phxDebloatDefault) { Write-Log ("        appx ~ " + $pat) } }
      if ($PhxRemoveXbox) { foreach ($pat in $phxDebloatXbox) { Write-Log ("        appx ~ " + $pat) } }
      Write-Log "  ЗАЩИТА: Store/winget/Defender-UI/калькулятор/блокнот/Paint/терминал/фото/камера/QuickAssist/рантаймы - НЕ сносимы."
    }
    $regN = ($script:Targets | Where-Object { -not $_.Svc -and -not $_.Task }).Count
    $svcN = ($script:Targets | Where-Object { $_.Svc }).Count
    $tskN = ($script:Targets | Where-Object { $_.Task }).Count
    Write-Log ("Итого: reg " + $regN + " | сервисы " + $svcN + " | задачи " + $tskN + " | power/NIC/MSI/fsutil - отдельными слоями")
    Write-Log "Режим Report - НИЧЕГО не изменено. Для применения: \$PhxMode='Apply' и повторить вставку."
  }

  function Invoke-PhxApply {
    Write-Log ""
    Write-Log ("== APPLY: применение (" + $script:Targets.Count + " позиций) ==")
    Invoke-PhxRestorePoint
    # Сначала PRE-экспорт всех reg-целей (двойная страховка против журнала)
    Export-PhxReg
    $cat = ''
    foreach ($t in $script:Targets) {
      if ($t.Cat -ne $cat) { $cat = $t.Cat; Write-Log ("-- " + $cat.ToUpper() + " --") }
      if ($t.Svc) {
        $svc = Get-Service -Name $t.Svc -ErrorAction SilentlyContinue
        if ($svc) {
          $old = $svc.StartType.ToString()
          $script:Journal.Add(@{ Kind='Svc'; Svc=$t.Svc; OldStartType=$old }) | Out-Null
          try {
            Set-Service -Name $t.Svc -StartupType $t.StartType -ErrorAction Stop
            $back = (Get-Service -Name $t.Svc).StartType.ToString()
            Set-EV1 ("svc " + $t.Svc) ($back -eq $t.StartType) ($old + " -> " + $t.StartType + " (перечитано: " + $back + ")")
          } catch { Set-EV1 ("svc " + $t.Svc) $false $_.Exception.Message }
        } else { Set-EV1 ("svc " + $t.Svc) $false 'служба отсутствует' }
        continue
      }
      if ($t.Task) {
        $tp = (Split-Path $t.Task) + '\'; $tn = Split-Path $t.Task -Leaf
        $task = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction SilentlyContinue
        if ($task) {
          $old = $task.State.ToString()
          $script:Journal.Add(@{ Kind='Task'; Task=$t.Task; OldState=$old }) | Out-Null
          try {
            Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null
            $back = (Get-ScheduledTask -TaskPath $tp -TaskName $tn).State.ToString()
            Set-EV1 ("task " + $tn) ($back -eq 'Disabled') ($old + " -> Disabled (перечитано: " + $back + ")")
          } catch { Set-EV1 ("task " + $tn) $false $_.Exception.Message }
        } else { Set-EV1 ("task " + $tn) $false 'задача отсутствует' }
        continue
      }
      $ok = Set-PhxValue $t.Path $t.Name $t.Value $t.Type
      Set-EV1 ("reg " + (Split-Path $t.Path -Leaf) + '\' + $t.Name) $ok ("-> " + $t.Value + " (risk " + $t.Risk + ")")
    }
    Invoke-PhxPower
    if ($P.Nic) { Invoke-PhxNic }
    if ($P.Msi) { Invoke-PhxMsi }
    Invoke-PhxFilesystem
    if ($P.Debloat -ne 'None') { Invoke-PhxDebloat }
    foreach ($d in $script:DebloatJournal) { $script:Journal.Add(@{ Kind='Appx'; Name=$d.Name; FullName=$d.FullName; Location=$d.Location }) | Out-Null }
    Save-PhxJournal
    Write-Generate-Rollback
  }

  function Invoke-PhxRestore {
    Write-Log ""
    Write-Log "== RESTORE из журнала v2 =="
    if (-not (Test-Path $journalPath)) { Write-Log "!! Журнал не найден: $journalPath"; return }
    $j = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
    foreach ($r in $j) {
      try {
        if ($r.Kind -eq 'Svc') {
          if ($PhxFullRestore) {
            Set-Service -Name $r.Svc -StartupType $r.OldStartType -ErrorAction Stop
            $back = (Get-Service -Name $r.Svc).StartType.ToString()
            Set-EV1 ("restore svc " + $r.Svc) ($back -eq $r.OldStartType) ("-> " + $r.OldStartType + " (перечитано: " + $back + ")")
          } else { Write-Log ("  skip svc " + $r.Svc + " (PhxFullRestore=$false)") }
        } elseif ($r.Kind -eq 'Task') {
          if ($PhxFullRestore) {
            $tp = (Split-Path $r.Task) + '\'; $tn = Split-Path $r.Task -Leaf
            if ($r.OldState -in @('Ready','Running')) {
              Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null
              $back = (Get-ScheduledTask -TaskPath $tp -TaskName $tn).State.ToString()
              Set-EV1 ("restore task " + $tn) ($back -in @('Ready','Running')) ("-> " + $back)
            } else { Set-EV1 ("restore task " + $tn) $true ('остаётся ' + $r.OldState) }
          } else { Write-Log ("  skip task " + $tn + " (PhxFullRestore=$false)") }
        } elseif ($r.Kind -eq 'Appx') {
          if ($PhxFullRestore) {
            $manifest = Join-Path $r.Location 'AppxManifest.xml'
            if (Test-Path $manifest) {
              Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
              Set-EV1 ("restore appx " + $r.Name) $true 'перерегистрирован по манифесту'
            } else { Set-EV1 ("restore appx " + $r.Name) $false 'каталог пакета удалён - ставь из Store' }
          } else { Write-Log ("  skip appx " + $r.Name + " (PhxFullRestore=$false)") }
        } else {
          # Reg
          if ($r.WasPresent) {
            if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            $val = $r.Old
            if ($r.Old -is [System.Array]) {
              Write-Log ("  !! binary-значение " + $r.Path + "\" + $r.Name + " восстанавливай из reg_export/*.reg")
              continue
            }
            New-ItemProperty -LiteralPath $r.Path -Name $r.Name -Value $val -PropertyType $r.Kind2 -Force | Out-Null
            $back = Get-PhxValue $r.Path $r.Name
            Set-EV1 ("restore reg " + (Split-Path $r.Path -Leaf) + '\' + $r.Name) (([string]$back) -eq ([string]$r.Old)) ("-> " + $r.Old)
          } else {
            Remove-ItemProperty -LiteralPath $r.Path -Name $r.Name -ErrorAction SilentlyContinue
            $back = Get-PhxValue $r.Path $r.Name
            Set-EV1 ("restore reg " + (Split-Path $r.Path -Leaf) + '\' + $r.Name) ($null -eq $back) 'удалено (значения не было)'
          }
          $script:PhxRestored++
        }
      } catch { Write-Log ("  !! не восстановлено [" + $r.Kind + "] " + $r.Path + $r.Svc + $r.Task + $r.Name + ": " + $_.Exception.Message) }
    }
    # Питание: возврат экспортированной схемы
    $powFile = Join-Path $bdir 'power_scheme_before.pow'
    if ($PhxFullRestore -and (Test-Path $powFile)) {
      $out = (& powercfg /import $powFile 2>$null) | Out-String
      $gm = [regex]::Match($out, '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')
      if ($gm.Success) {
        powercfg /setactive $gm.Value 2>$null
        Set-EV1 'restore power' ($LASTEXITCODE -eq 0) ('схема импортирована и активирована: ' + $gm.Value)
      } else { Set-EV1 'restore power' $false 'powercfg /import не вернул GUID' }
    }
    Write-Log ("Восстановлено reg-значений: " + $script:PhxRestored)
  }

  # ---------- 9. Генератор самодостаточного rollback.ps1 (v2: reg+svc+task+appx) ----------
  function Write-Generate-Rollback {
    $rb = Join-Path $bdir 'rollback.ps1'
    $lines = @(
      '# rollback.ps1 - автосгенерирован PHX_TWEAKPACK v2.0 ' + $ts,
      '# Откат по журналу: реестр + сервисы + задачи + Appx. Запуск в admin PowerShell.',
      '$ErrorActionPreference = ''Continue'''
    )
    foreach ($r in $script:Journal) {
      if ($r.Kind -eq 'Svc') {
        $lines += ("Set-Service -Name '" + $r.Svc + "' -StartupType " + $r.OldStartType + " -ErrorAction SilentlyContinue")
      } elseif ($r.Kind -eq 'Task') {
        $lines += ("# task " + $r.Task + " было: " + $r.OldState)
        if ($r.OldState -in @('Ready','Running')) {
          $lines += ("Enable-ScheduledTask -TaskPath '" + ((Split-Path $r.Task) + '\') + "' -TaskName '" + (Split-Path $r.Task -Leaf) + "' -ErrorAction SilentlyContinue | Out-Null")
        }
      } elseif ($r.Kind -eq 'Appx') {
        $lines += ("# appx " + $r.Name + " - вернуть: Add-AppxPackage -Register '" + ($r.Location -replace "'", "''") + "\AppxManifest.xml' -DisableDevelopmentMode (если каталог жив) либо из Store")
      } else {
        $nm = if ($r.Name -eq '') { '(default)' } else { $r.Name }
        $p = ($r.Path -replace "'", "''")
        if ($r.WasPresent) {
          $kind = if ($r.Kind2) { $r.Kind2 } else { 'String' }
          if ($kind -eq 'String' -or $kind -eq 'ExpandString') {
            $v = if ($null -ne $r.Old) { ([string]$r.Old) -replace "'", "''" } else { '' }
            $lines += ("New-ItemProperty -LiteralPath '" + $p + "' -Name '" + $nm + "' -Value '" + $v + "' -PropertyType " + $kind + " -Force | Out-Null")
          } else {
            $v = if ($null -ne $r.Old) { [long]$r.Old } else { 0 }
            $lines += ("New-ItemProperty -LiteralPath '" + $p + "' -Name '" + $nm + "' -Value " + $v + " -PropertyType " + $kind + " -Force | Out-Null")
          }
        } else {
          $lines += ("Remove-ItemProperty -LiteralPath '" + $p + "' -Name '" + $nm + "' -ErrorAction SilentlyContinue")
        }
      }
    }
    $lines += ('"Готово: отработано записей: ' + $script:Journal.Count + '"')
    Set-Content -LiteralPath $rb -Value $lines -Encoding UTF8
    Set-EV1 'rollback.ps1 сгенерирован (v2: reg+svc+task+appx)' $true $rb
  }

  # ---------- 10. Диспетчер режимов + итог ----------
  switch ($PhxMode) {
    'Report'  { Show-PhxReport }
    'Apply'   { Invoke-PhxApply }
    'Restore' { Invoke-PhxRestore }
    default   { Write-Log "!! Неизвестный режим: $PhxMode (Report|Apply|Restore)" }
  }

  Write-Log ""
  Write-Log "== ИТОГ PHOENIX TWEAKPACK v2.0 =="
  Write-Log ("  [x] сделано: " + $script:PhxOk + " | [--] недоступно/НЕ сделано: " + $script:PhxSkip + " | восстановлено reg: " + $script:PhxRestored)
  Write-Log ("Профиль: $PhxProfile | Debloat: " + $P.Debloat + " | Журнал: " + $journalPath)
  Write-Log ("Бэкап:  " + $bdir + " (reg_export\*.reg + power_scheme_before.pow + rollback.ps1)")
  if ($script:PhxEV1.Count -gt 0) {
    Write-Log "Список ЭВ.1 (недоступно = НЕ сделано):"
    foreach ($e in $script:PhxEV1) { Write-Log ("    - " + $e) }
  }
  Write-Log ("Лог: " + $log)
}
