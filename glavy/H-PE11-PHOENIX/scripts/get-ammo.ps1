# =====================================================================
# H-PE11 // GET-AMMO v1.1 (paste-and-run) — добывает снаряды в payload
# Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ. ЭВ.1: недоступно = НЕ сделано ([--]).
# Запуск: admin PowerShell -> вставить всё -> Enter.
# Кладёт всё в: Рабочий стол\H-PE11_Bomb_Payload\ (для build-bomb.ps1)
# =====================================================================

& {
  $ErrorActionPreference = 'Continue'
  $ts  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
  $pay = "$env:USERPROFILE\Desktop\H-PE11_Bomb_Payload"
  $log = "$env:USERPROFILE\Desktop\H-PE11_GET-AMMO_$ts.log"
  function Write-Log([string]$m) { Write-Host $m; Add-Content -LiteralPath $log -Value $m -Encoding UTF8 }
  foreach ($d in @('','DirectX','VC','Tools','Python','wget','Cursors','Cursors\XpucT','HMS','LoginUnlocker','DriverPacks','Volume2')) {
    New-Item -ItemType Directory -Path (Join-Path $pay $d) -Force | Out-Null
  }
  Write-Log "H-PE11 // GET-AMMO v1.1 | $ts | payload: $pay"

  # --- 1. Volume2: сначала станция, потом GitHub ---
  $v2 = $null
  foreach ($c in @("$env:ProgramFiles\Volume2","${env:ProgramFiles(x86)}\Volume2","$env:LOCALAPPDATA\Volume2","$env:APPDATA\Volume2")) {
    if (Test-Path (Join-Path $c 'Volume2.exe')) { $v2 = $c; break }
  }
  if ($v2) { Copy-Item -LiteralPath (Join-Path $v2 '*') -Destination "$pay\Volume2" -Recurse -Force; Write-Log "[x] Volume2 скопирован со станции: $v2" }
  else {
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/irzyxa/Volume2/releases' -TimeoutSec 30
      $asset = $rel[0].assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
      if ($asset) {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile "$pay\Volume2\volume2-portable.zip" -TimeoutSec 300
        Write-Log ("[x] Volume2 скачан: " + $asset.name)
      } else { Write-Log "[--] Volume2: у релиза нет zip-ассета" }
    } catch { Write-Log ("[--] Volume2: " + $_.Exception.Message) }
  }

  # --- 2. GNU wget (eternallybored) ---
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://eternallybored.org/misc/wget/current/wget64.exe' -OutFile "$pay\wget\wget.exe" -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -TimeoutSec 120
    $len = (Get-Item "$pay\wget\wget.exe").Length
    if ($len -gt 200000) { Write-Log "[x] GNU wget64.exe скачан ($len байт)" }
    else { Write-Log "[--] wget: сервер отдал не бинарник; в PE будет wget.cmd-обёртка над curl.exe" }
  } catch { Write-Log ("[--] wget: " + $_.Exception.Message) }

  # --- 3+4. Strelec: Login Unlocker + SSTR\DriverPacks из ISO/папки ---
  $isoHit = $null
  foreach ($drv in @('C:\','D:\','E:\','F:\','G:\')) {
    if (-not (Test-Path $drv)) { continue }
    $isoHit = Get-ChildItem $drv -Filter '*Strelec*.iso' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($isoHit) { break }
  }
  if ($isoHit) {
    Write-Log ("[ ] Найден ISO Strelec: " + $isoHit.FullName + " — монтирую...")
    try {
      $img = Mount-DiskImage -ImagePath $isoHit.FullName -PassThru
      $dl  = ($img | Get-Volume).DriveLetter + ':\'
      $wlu = Get-ChildItem $dl -Directory -Recurse -Depth 3 -Filter '*Login*Unlocker*' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($wlu) { Copy-Item -LiteralPath (Join-Path $wlu.FullName '*') -Destination "$pay\LoginUnlocker" -Recurse -Force; Write-Log ("[x] Windows Login Unlocker: " + $wlu.FullName) }
      else { Write-Log "[--] Login Unlocker в ISO не найден" }
      $sstr = Get-ChildItem $dl -Directory -Recurse -Depth 3 -Filter 'DriverPacks' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'SSTR' -or (Get-ChildItem $_.FullName -Filter 'MassStorage*' -ErrorAction SilentlyContinue) } | Select-Object -First 1
      if ($sstr) { Copy-Item -LiteralPath (Join-Path $sstr.FullName '*') -Destination "$pay\DriverPacks" -Recurse -Force; Write-Log ("[x] SSTR DriverPacks: " + $sstr.FullName) }
      else { Write-Log "[--] DriverPacks в ISO не найден" }
      Dismount-DiskImage -ImagePath $isoHit.FullName | Out-Null
    } catch { Write-Log ("[--] ISO: " + $_.Exception.Message) }
  } else {
    Write-Log "[--] ISO Strelec не найден на дисках. Если есть скачанный Strelec/папка SSTR — положи LoginUnlocker и DriverPacks в payload вручную"
  }

  # --- 5. VC++ runtime DLL (полный набор со станции) ---
  $vcDlls = @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','concrt140.dll','msvcp120.dll','msvcr120.dll','msvcp110.dll','msvcr110.dll','msvcp100.dll','msvcr100.dll','msvcp90.dll','msvcr90.dll','msvcp80.dll','msvcr80.dll')
  $vcGot = 0
  foreach ($d in $vcDlls) {
    foreach ($sysdir in @("$env:SystemRoot\System32","$env:SystemRoot\SysWOW64")) {
      $src = Join-Path $sysdir $d
      if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $pay ('VC\' + $d)) -Force; $vcGot++ }
    }
  }
  Write-Log ("[x] VC++ DLL собрано: " + $vcGot + " (System32+SysWOW64)")

  # --- 6. DirectX d3dx (со станции, если есть) ---
  $dxDlls = @('d3dx9_43.dll','d3dx9_40.dll','d3dx10_43.dll','d3dx11_43.dll','d3dx9_34.dll','d3dxof.dll','dinput8.dll','xinput1_3.dll')
  $dxGot = 0
  foreach ($d in $dxDlls) {
    foreach ($sysdir in @("$env:SystemRoot\System32","$env:SystemRoot\SysWOW64")) {
      $src = Join-Path $sysdir $d
      if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $pay ('DirectX\' + $d)) -Force; $dxGot++ }
    }
  }
  if ($dxGot -gt 0) { Write-Log ("[x] DirectX DLL собрано: " + $dxGot) }
  else { Write-Log "[--] d3dx на станции нет; при необходимости ставь DirectX End-User Runtime (Jun 2010) и перезапусти" }

  # --- 7. 7-Zip / Notepad++ ---
  foreach ($pair in @(@("$env:ProgramFiles\7-Zip",'7-Zip'),@("${env:ProgramFiles(x86)}\7-Zip",'7-Zip'),@("$env:ProgramFiles\Notepad++",'Notepad++'),@("${env:ProgramFiles(x86)}\Notepad++",'Notepad++'))) {
    if (Test-Path $pair[0]) { Copy-Item -LiteralPath (Join-Path $pair[0] '*') -Destination (Join-Path $pay ('Tools\' + $pair[1])) -Recurse -Force; Write-Log ("[x] Tools: " + $pair[0]) }
  }

  # --- 8. Отчёт + SHA256 ---
  $sums = @()
  Get-ChildItem $pay -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $h = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    $sums += ($h.Hash + "  " + $_.FullName.Substring($pay.Length + 1))
  }
  Set-Content -LiteralPath (Join-Path $pay 'SHA256SUMS.txt') -Value $sums -Encoding ASCII
  Write-Log ("SHA256SUMS.txt: " + $sums.Count + " записей")
  Write-Log "ГОТОВО. Теперь запусти build-bomb.ps1 (он подхватит payload автоматически)"
}
