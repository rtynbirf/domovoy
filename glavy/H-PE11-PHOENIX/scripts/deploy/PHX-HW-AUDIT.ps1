# =====================================================================
# H-PE11 // PHX-HW-AUDIT.ps1 - аудит железа станции (ALPHA-контур)
# Зачем: ALPHA испытывается НА КОНКРЕТНОМ железе. Отчёт уходит Хозяину
#        -> профиль v2.x затачивается под реальные CPU/GPU/диск/NIC/RAM.
# Выход: C:\PHX\reports\PHX-HW-REPORT.txt  (человекочитаемый - для Хозяина)
#        C:\PHX\reports\PHX-HW-REPORT.json (машинный - для синтеза v2.x)
# Закон ЭВ.1: секция не опросилась = [--] в отчёте, но отчёт продолжается.
# =====================================================================

param([string]$OutDir = 'C:\PHX\reports')

$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$stamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$lines  = New-Object System.Collections.Generic.List[string]
$json   = @{}
$ev     = New-Object System.Collections.Generic.List[string]

function Sect([string]$name) {
  $lines.Add('')
  $lines.Add('==================== ' + $name + ' ====================')
}
function EvMark([string]$item, [bool]$ok, [string]$note) {
  if ($ok) { $lines.Add('  [x] ' + $item + ' :: ' + $note) }
  else { $lines.Add('  [--] ' + $item + ' :: ' + $note); $script:ev.Add($item + ' :: ' + $note) }
}
function Add([string]$s) { $lines.Add($s) }

Add ('H-PE11 // PHOENIX-ALPHA 0.1 - HW AUDIT')
Add ('Время: ' + $stamp)
Add ('Компьютер: ' + $env:COMPUTERNAME + ' | Пользователь: ' + $env:USERNAME)
Add ('ОТПРАВЬ ЭТОТ ФАЙЛ ХОЗЯИНУ ЦЕЛИКОМ (целиком = без сокращений).')

# ---------- OS ----------
Sect 'OS'
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  $json.os = @{ Caption=$os.Caption; Build=$os.BuildNumber; UBR=$cv.UBR; DisplayVersion=$cv.DisplayVersion; Arch=$os.OSArchitecture; InstallDate=([string]$os.InstallDate) }
  Add ('Издание: ' + $os.Caption + ' | Сборка: ' + $os.BuildNumber + '.' + $cv.UBR + ' | ' + $cv.DisplayVersion)
  EvMark 'OS' $true ($os.BuildNumber + '.' + $cv.UBR)
} catch { EvMark 'OS' $false $_.Exception.Message }

# ---------- CPU ----------
Sect 'CPU'
try {
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $json.cpu = @{ Name=$cpu.Name; Cores=$cpu.NumberOfCores; Threads=$cpu.NumberOfLogicalProcessors; MaxClock=[string]$cpu.MaxClockSpeed }
  Add ('Процессор: ' + $cpu.Name)
  Add ('Ядра/потоки: ' + $cpu.NumberOfCores + '/' + $cpu.NumberOfLogicalProcessors + ' | Такт: ' + [math]::Round($cpu.MaxClockSpeed/1000,2) + ' ГГц')
  EvMark 'CPU' $true $cpu.Name
} catch { EvMark 'CPU' $false $_.Exception.Message }

# ---------- RAM ----------
Sect 'RAM'
try {
  $sticks = Get-CimInstance Win32_PhysicalMemory
  $total = [long]($sticks | Measure-Object Capacity -Sum).Sum
  $json.ram = @{ TotalGB=[math]::Round($total/1GB,2); Sticks=@() }
  Add ('Всего: ' + [math]::Round($total/1GB,2) + ' ГБ, планок: ' + $sticks.Count)
  foreach ($s in $sticks) {
    $json.ram.Sticks += @{ GB=[math]::Round($s.Capacity/1GB,1); Speed=$s.Speed; Type=$s.SMBIOSMemoryType }
    Add ('  планка ' + [math]::Round($s.Capacity/1GB,1) + ' ГБ @ ' + $s.Speed + ' MT/s (SMBIOS type ' + $s.SMBIOSMemoryType + ')')
  }
  EvMark 'RAM' $true ([math]::Round($total/1GB,2) + ' ГБ')
} catch { EvMark 'RAM' $false $_.Exception.Message }

# ---------- GPU ----------
Sect 'GPU'
try {
  $gpus = Get-CimInstance Win32_VideoController
  $json.gpu = @()
  foreach ($g in $gpus) {
    $json.gpu += @{ Name=$g.Name; Driver=[string]$g.DriverVersion; VRAM=[string]$g.AdapterRAM }
    Add ('Видео: ' + $g.Name + ' | драйвер ' + $g.DriverVersion + ' | AdapterRAM ' + [math]::Round($g.AdapterRAM/1MB) + ' МБ (поле 32-бит, для >4ГБ смотри dxdiag)')
  }
  if ($gpus) { EvMark 'GPU' $true ($gpus[0].Name) } else { EvMark 'GPU' $false 'контроллеры не найдены' }
} catch { EvMark 'GPU' $false $_.Exception.Message }

# ---------- Диски ----------
Sect 'DISKS'
try {
  $pds = Get-PhysicalDisk
  $json.disks = @()
  foreach ($d in $pds) {
    $json.disks += @{ Friendly=$d.FriendlyName; Bus=$d.BusType; Media=[string]$d.MediaType; SizeGB=[math]::Round($d.Size/1GB,0); Health=[string]$d.HealthStatus }
    Add ('Диск: ' + $d.FriendlyName + ' | ' + $d.BusType + '/' + $d.MediaType + ' | ' + [math]::Round($d.Size/1GB,0) + ' ГБ | ' + $d.HealthStatus)
  }
  $sysVol = Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue
  if ($sysVol) { Add ('Системный диск №' + $sysVol.DiskNumber + ' (раздел ' + $env:SystemDrive + ')') }
  EvMark 'DISKS' ($pds.Count -gt 0) ($pds.Count + ' шт.')
} catch { EvMark 'DISKS' $false $_.Exception.Message }

# ---------- NIC ----------
Sect 'NIC'
try {
  $nics = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
  $json.nic = @()
  foreach ($n in $nics) {
    $json.nic += @{ Name=$n.Name; Desc=$n.InterfaceDescription; Speed=[string]$n.LinkSpeed; Mac=$n.MacAddress }
    Add ('Сеть: ' + $n.Name + ' | ' + $n.InterfaceDescription + ' | ' + $n.LinkSpeed)
  }
  if (-not $nics) { Add ('(активных адаптеров нет - оффлайн-аудит)') }
  EvMark 'NIC' $true ($(if ($nics) { $nics.Count + ' активных' } else { 'нет активных' }))
} catch { EvMark 'NIC' $false $_.Exception.Message }

# ---------- Firmware: UEFI/SecureBoot/TPM (байпасы ALPHA зависят от этого) ----------
Sect 'FIRMWARE'
try {
  $bootMode = 'Unknown'
  try {
    $env2 = Get-CimInstance -ClassName Win32_Environment -Filter "Name=' firmware_mode'" -ErrorAction SilentlyContinue
  } catch {}
  try {
    $binfo = bcdedit 2>$null | Out-String
    if ($binfo -match 'path\s+\\EFI\\') { $bootMode = 'UEFI' } elseif ($binfo) { $bootMode = 'Legacy/CSM' }
  } catch {}
  Add ('Режим загрузки (по bcdedit): ' + $bootMode)
  $json.firmware = @{ BootMode=$bootMode }
  $sb = $null
  try { $sb = Confirm-SecureBootUEFI } catch { $sb = $null }
  if ($null -ne $sb) { Add ('SecureBoot: ' + $sb); $json.firmware.SecureBoot = $sb }
  else { Add ('SecureBoot: [--] (не опрошено - legacy/CSM или нет прав)') }
  try {
    $tpm = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop
    Add ('TPM: SpecVersion ' + $tpm.SpecVersion + ' | Enabled ' + $tpm.IsEnabled_InitialValue)
    $json.firmware.TPM = [string]$tpm.SpecVersion
  } catch { Add ('TPM: [--] (не обнаружен/не опрошен - для ALPHA это не блокер, байпас активен)') }
  EvMark 'FIRMWARE' $true $bootMode
} catch { EvMark 'FIRMWARE' $false $_.Exception.Message }

# ---------- Шасси/питание ----------
Sect 'CHASSIS/POWER'
try {
  $enc = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
  $isLaptop = $false
  foreach ($c in @(8,9,10,12,14,30,31,32)) { if ($enc -contains $c) { $isLaptop = $true } }
  $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
  $sch = powercfg /getactivescheme | Out-String
  Add ('Шасси: ' + $(if ($isLaptop) { 'ноутбук/портатив' } else { 'десктоп' }) + ' | Батарея: ' + $(if ($bat) { 'есть' } else { 'нет' }))
  Add ('Схема питания: ' + $sch.Trim())
  $json.chassis = @{ Laptop=$isLaptop; Battery=($null -ne $bat); PowerScheme=$sch.Trim() }
  EvMark 'CHASSIS/POWER' $true $(if ($isLaptop) { 'laptop' } else { 'desktop' })
} catch { EvMark 'CHASSIS/POWER' $false $_.Exception.Message }

# ---------- Итог ----------
$lines.Insert(0, '')
$lines.Insert(0, 'Закон ЭВ.1: недоступно = НЕ сделано (метка [--]). Отчёт всё равно полон.')
if ($ev.Count -gt 0) {
  $lines.Add('')
  $lines.Add('== НЕ ОПРОШЕНО (ЭВ.1) ==')
  foreach ($e in $ev) { $lines.Add('  - ' + $e) }
}
$lines.Add('')
$lines.Add('== Конец отчёта (без искусственных завершающих блоков - это данные, не письмо). ==')

$txtPath = Join-Path $OutDir 'PHX-HW-REPORT.txt'
Set-Content -LiteralPath $txtPath -Value $lines -Encoding UTF8
try {
  $json._ev1 = $ev; $json._stamp = $stamp
  $json | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'PHX-HW-REPORT.json') -Encoding UTF8
} catch {}
Write-Host ('HW AUDIT готов: ' + $txtPath)
