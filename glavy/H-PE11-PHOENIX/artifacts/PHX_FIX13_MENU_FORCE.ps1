# ============================================================
# PHX_FIX13_MENU_FORCE.ps1  |  H-PE11 / FENIKS-11  |  2026-10-24  |  v2
# v2: ispravlen FATAL progona v1: funkcia R konfliktovala s
#   vstroennym aliasom PowerShell 'r' (Invoke-History) - aliasy
#   starshe funkcij, vyzovy uhodili v Invoke-History. Pereimenovana
#   v Run-Cmd + dobavlen selftest truboprovoda v FAZE 0.
#   Sistema v progone v1 NE izmenena: skript ostanovilsya na backup
#   do lyuboj zapisi (BAK NE SOZDAN - ostanovka).
# SITUACIYA: FIX12 SVODKA 4/4 PASS (Form A + sdi + menu), no pri
#   starte bootmgr NE pokazyvaet menyu i gruzeit Windows srazu.
# PRICHINA (veb-issledovanie: MS Learn BCDEdit /set + praktika):
#   1) bootmenupolicy: defolt Win10/11 = Standard. Po MS Learn:
#      "When Standard is selected, the boot menu appears but only
#      under certain conditions". Na zhivoi mashine menyu mozhet
#      ne pokazyvatsya vobshe. Legacy = klassicheskoe menyu na
#      kazhdom starte (kak v Win7) + rabotaet knopka F8.
#   2) Bystryi zapusk (Hiberboot): posle VYKLYUCHENIYa Windows
#      prosypaetsya iz hiberfil.sys i PROPUUSKAET menyu.
#   3) Monitor ne uspevaet prosnutsya za 7 sek (chernyi ekran ->
#      uzhe Windows). Lechitsya: PHX_FIX13_RUN.cmd 15
# FIX (4 shaga): bootmenupolicy Legacy ({bootmgr}, fallback:
#   loader Windows) + displaybootmenu Yes + timeout +
#   HiberbootEnabled = 0 (bystryi zapusk OFF).
# BEZOPASNOST: zapis FENIKS-11 PE v BCD NE trogaetsya; otkat ne
#   nuzhen (vse shaga obratimy, na put zagruzki ne vliyaiut).
#   Backup BCD vse ravno delaem (FAZA 2).
# ZAPUSK: PHX_FIX13_RUN.cmd [timeout_sek]  (default 7)
# LOG: C:\Boot\PHX_FIX13_LOG.txt
# ============================================================
param([int]$Tmo = 7)

$ErrorActionPreference = 'Continue'
$Log   = 'C:\Boot\PHX_FIX13_LOG.txt'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Bak   = 'C:\Boot\PHX_BCD_FIX13_BAK_' + $Stamp
$Res   = 'D:\PHX_BOOT_RESERVE'
$RegP  = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
$PE    = '{0fb9b787-cf0f-11f1-8e89-14dae993e88d}'
$script:LASTEC     = -1
$script:BMP_TARGET = ''
$script:PASS       = 0

function W([string]$s) {
  Write-Host $s
  try { Add-Content -Path $Log -Value $s -Encoding UTF8 } catch {}
}

function Run-Cmd([string]$exe, [string[]]$cargs) {
  $show = ($cargs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  W ('CMD> ' + $exe + ' ' + $show)
  $out = & $exe @cargs 2>&1
  $script:LASTEC = $LASTEXITCODE
  foreach ($l in @($out)) { W ('     ' + $l) }
  W ('     [ec=' + $script:LASTEC + ']')
  return (@($out) -join "`n")
}

# ---------- FAZA 0: SREDA ----------
try { New-Item -ItemType Directory -Path 'C:\Boot' -Force | Out-Null } catch {}
try { Set-Content -Path $Log -Value 'PHX FIX13 LOG' -Encoding UTF8 } catch {}

W '=========================================================='
W (' PHX FIX13 MENU FORCE v2  |  ' + $Stamp + '  |  TMO=' + $Tmo)
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
try { $os = Get-CimInstance Win32_OperatingSystem; W (' OS: ' + $os.Caption + ', build ' + $os.BuildNumber) } catch {}
W (' Admin = ' + $adm)
W '=========================================================='
if (-not $adm) { W 'NET PRAV ADMINA - zapusti cherez PHX_FIX13_RUN.cmd (UAC).'; exit 1 }
if (-not (Test-Path 'C:\Boot\BCD')) { W 'NET C:\Boot\BCD - eto ne ta mashina?'; exit 1 }

W ''
W '[selftest] proba truboprovoda (cmd /c ver):'
$st = Run-Cmd cmd.exe @('/c','ver')
if ($script:LASTEC -ne 0) {
  W 'SELFTEST FAIL - vyzov funkcii sloman, ostanovka (nichego ne izmeneno).'
  exit 1
}

# ---------- FAZA 1: DIAG DO ----------
W ''
W '---------- FAZA 1: DIAG DO ----------'
$BeforeBmgr = Run-Cmd bcdedit @('/enum','{bootmgr}')
Run-Cmd powercfg @('/a')
Run-Cmd reg.exe @('query',$RegP,'/v','HiberbootEnabled')

# ---------- FAZA 2: BACKUP BCD ----------
W ''
W '---------- FAZA 2: BACKUP BCD ----------'
Run-Cmd bcdedit @('/export',$Bak)
if (Test-Path $Bak) {
  $sz = (Get-Item $Bak).Length
  W ('BAK OK: ' + $Bak + ' (' + $sz + ' B)')
  try {
    if (-not (Test-Path $Res)) { New-Item -ItemType Directory -Path $Res -Force | Out-Null }
    Copy-Item $Bak (Join-Path $Res (Split-Path $Bak -Leaf)) -Force
    W 'Kopiya v D:\PHX_BOOT_RESERVE: OK'
  } catch { W ('Kopiya na D: NE udalas (ne fatal): ' + $_.Exception.Message) }
} else {
  W 'BAK NE SOZDAN - ostanovka (bez rezervnoj kopii nichego ne menyaem).'
  exit 1
}

# ---------- FAZA 3: FIX (4 shaga) ----------
W ''
W '---------- FAZA 3: FIX ----------'

W ''
W '[1/4] bootmenupolicy Legacy'
Run-Cmd bcdedit @('/set','{bootmgr}','bootmenupolicy','Legacy')
$script:BMP_TARGET = '{bootmgr}'
if ($script:LASTEC -ne 0) {
  W ('[1] {bootmgr} otkazal (ec=' + $script:LASTEC + ') - fallback na loader Windows')
  $wguid = $null
  if ($BeforeBmgr -match 'default\s+\{([0-9a-fA-F\-]{36})\}') { $wguid = '{' + $Matches[1] + '}' }
  if ($wguid) {
    W ('[1] Windows loader GUID: ' + $wguid)
    Run-Cmd bcdedit @('/set',$wguid,'bootmenupolicy','Legacy')
    if ($script:LASTEC -eq 0) { $script:BMP_TARGET = $wguid }
  } else {
    W '[1] default element ne najden - bootmenupolicy NE ustanovlen (ne fatal)'
  }
}

W ''
W '[2/4] displaybootmenu Yes'
Run-Cmd bcdedit @('/set','{bootmgr}','displaybootmenu','Yes')

W ''
W ('[3/4] timeout = ' + $Tmo)
Run-Cmd bcdedit @('/set','{bootmgr}','timeout',"$Tmo")

W ''
W '[4/4] HiberbootEnabled = 0 (bystryi zapusk OFF)'
Run-Cmd reg.exe @('add',$RegP,'/v','HiberbootEnabled','/t','REG_DWORD','/d','0','/f')

W ''
W 'Zapis FENIKS-11 PE v BCD NE trognuta.'

# ---------- FAZA 4: READBACK ----------
W ''
W '---------- FAZA 4: READBACK ----------'
$AfterBmgr = Run-Cmd bcdedit @('/enum','{bootmgr}')
$bmpok = ($AfterBmgr -match 'bootmenupolicy\s+Legacy')
if (-not $bmpok -and $script:BMP_TARGET -ne '{bootmgr}' -and $script:BMP_TARGET -ne '') {
  $wenum = Run-Cmd bcdedit @('/enum',$script:BMP_TARGET)
  $bmpok = ($wenum -match 'bootmenupolicy\s+Legacy')
}
$dbmok = ($AfterBmgr -match 'displaybootmenu\s+Yes')
$tmook = ($AfterBmgr -match ('timeout\s+' + $Tmo + '\b'))
$regq  = Run-Cmd reg.exe @('query',$RegP,'/v','HiberbootEnabled')
$hbok  = ($regq -match 'HiberbootEnabled\s+REG_DWORD\s+0x0')
$peenum = Run-Cmd bcdedit @('/enum',$PE)
$peok  = ($peenum -match 'ramdisk=')

# ---------- FAZA 5: SVODKA ----------
W ''
W '---------- FAZA 5: SVODKA ----------'
function Chk([string]$name, [bool]$ok) {
  if ($ok) { $script:PASS++; W ($name + ' : PASS') } else { W ($name + ' : FAIL') }
}
Chk ('N1 BOOTMENUPOLICY=Legacy (target ' + $script:BMP_TARGET + ')') $bmpok
Chk 'N2 DISPLAYBOOTMENU=Yes' $dbmok
Chk ('N3 TIMEOUT=' + $Tmo) $tmook
Chk 'N4 HIBERBOOT=OFF' $hbok
Chk 'N5 PE-ENTRY INTACT (ramdisk Form A)' $peok
W ('ITOG: SVODKA ' + $script:PASS + '/5 PASS')
W ''
W 'CHTO DELAT TEPER:'
W ('1) PEREZAGRUZKA N1 (Pusk -> Perezagruzka): dolzhno poyavitsya menyu na ' + $Tmo + ' sek.')
W '   (2 stroki: Windows 11 + FENIKS-11 PE (WINST)). Nichego ne zhmi - Windows'
W '   gruzaetsya sama po taymautu.'
W '2) Esli menyu NE vidno - vozmozhno, ono EST, a monitor ne uspel prosnutsya.'
W '   Test: pri starte zhmi strelku VNIZ 1 raz, potom Enter. Zagruzilsya PE ->'
W ('   menyu bylo, monitor spal: zapusti snova s bolshim taymautom:')
W '   PHX_FIX13_RUN.cmd 15'
W '3) PEREZAGRUZKA N2: vybrat FENIKS-11 PE (WINST) i smotret rezultat.'
W '4) Oshibka -> FOTO ekrana + C:\Boot\PHX_FIX13_LOG.TXT mne.'
W ''
W ('Otkat (esli zachem): bcdedit /import "' + $Bak + '"')
W '=========================================================='
if ($script:PASS -eq 5) { exit 0 } else { exit 2 }
