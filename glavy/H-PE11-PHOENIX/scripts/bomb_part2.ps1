
  # ---------- СЕКЦИЯ 5. .NET 3.5 (CLR2/3.5) + правка реестра ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 5. .NET 3.5 (CLR 2.0/3.5) В БОМБУ =="
  $net35Ok = $false
  try {
    $src64a = "$env:SystemRoot\Microsoft.NET\Framework64\v2.0.50727"
    $src64b = "$env:SystemRoot\Microsoft.NET\Framework64\v3.5"
    $src32a = "$env:SystemRoot\Microsoft.NET\Framework\v2.0.50727"
    $src32b = "$env:SystemRoot\Microsoft.NET\Framework\v3.5"
    if ((Test-Path $src64a) -and (Test-Path $src64b)) {
      $dst = "$mount\Windows\Microsoft.NET"
      foreach ($pair in @(@($src64a,'Framework64\v2.0.50727'),@($src64b,'Framework64\v3.5'),@($src32a,'Framework\v2.0.50727'),@($src32b,'Framework\v3.5'))) {
        $s = $pair[0]; $d = Join-Path $dst $pair[1]
        if (Test-Path $s) {
          New-Item -ItemType Directory -Path $d -Force | Out-Null
          Copy-Item -LiteralPath ($s + '\*') -Destination $d -Recurse -Force -ErrorAction SilentlyContinue
          Write-Log ("  Скопировано: " + $s + " -> " + $d)
        }
      }
      $net35Ok = (Test-Path "$dst\Framework64\v3.5\mscorlib.dll") -or (Test-Path "$dst\Framework64\v2.0.50727\mscorlib.dll")
      Set-EV1 '.NET 3.5 файлы (mscorlib/сборки)' $net35Ok 'копия Framework-дерева станции'
    } else {
      Set-EV1 '.NET 3.5 файлы' $false 'на станции нет Framework v2.0/v3.5 (не установлен); положи в payload\Net35'
    }
    # Реестр: OnlyUseLatestCLR для обоих CLR
    $hiv = "$mount\Windows\System32\config\SOFTWARE"
    if (Test-Path $hiv) {
      & reg.exe load 'HKLM\HPE11_SOFT' $hiv 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) {
        New-Item -Path 'HKLM:\HPE11_SOFT\Microsoft\.NETFramework\v2.0.50727' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\HPE11_SOFT\Microsoft\.NETFramework\v2.0.50727' -Name 'OnlyUseLatestCLR' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item -Path 'HKLM:\HPE11_SOFT\Microsoft\.NETFramework\v4.0.30319' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\HPE11_SOFT\Microsoft\.NETFramework\v4.0.30319' -Name 'OnlyUseLatestCLR' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        & reg.exe unload 'HKLM\HPE11_SOFT' 2>$null | Out-Null
        Write-Log "  Реестр SOFTWARE: политики .NET записаны"
      } else { Write-Log "  [--] SOFTWARE-hive не смонтировался (reg load)" ; $script:HpeEV1 += 'Реестр .NET :: reg load не удался' }
    }
  } catch {
    Write-Log ("СЕКЦИЯ 5 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('.NET 3.5 :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 6. PAYLOAD: DirectX, VC++, инструменты ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 6. PAYLOAD: DIRECTX / VC++ / ИНСТРУМЕНТЫ =="
  $pay = $HpePayload
  if (-not $pay) { $p1 = "$env:USERPROFILE\Desktop\H-PE11_Bomb_Payload"; if (Test-Path $p1) { $pay = $p1 } }
  $dxOk = $false; $vcOk = $false; $toolsOk = 0
  try {
    if ($pay -and (Test-Path $pay)) {
      Write-Log ("  Payload: " + $pay)
      # DirectX (d3dx-набор)
      $dxd = Join-Path $pay 'DirectX'
      if (Test-Path $dxd) {
        foreach ($to in @("$mount\Windows\System32","$mount\Windows\SysWOW64")) {
          Copy-Item -LiteralPath (Join-Path $dxd '*') -Destination $to -Recurse -Force -ErrorAction SilentlyContinue
        }
        $dxOk = Test-Path "$mount\Windows\System32\d3dx9_43.dll"
        Set-EV1 'DirectX d3dx-набор (System32+SysWOW64)' $dxOk 'из payload'
      } else { Set-EV1 'DirectX d3dx-набор' $false 'нет payload\DirectX (d3dx9_43.dll и др.)' }
      # VC++ runtime DLL
      $vcd = Join-Path $pay 'VC'
      if (Test-Path $vcd) {
        foreach ($to in @("$mount\Windows\System32","$mount\Windows\SysWOW64")) {
          Copy-Item -LiteralPath (Join-Path $vcd '*') -Destination $to -Recurse -Force -ErrorAction SilentlyContinue
        }
        $vcOk = Test-Path "$mount\Windows\System32\msvcp140.dll"
        Set-EV1 'VC++ Redistributable DLL (2015-2022+)' $vcOk 'из payload'
      } else { Set-EV1 'VC++ Redistributable DLL' $false 'нет payload\VC' }
      # Инструменты
      $tld = Join-Path $pay 'Tools'
      if (Test-Path $tld) {
        New-Item -ItemType Directory -Path "$mount\Tools" -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $tld '*') -Destination "$mount\Tools" -Recurse -Force -ErrorAction SilentlyContinue
        $toolsOk = (Get-ChildItem "$mount\Tools" -Directory -ErrorAction SilentlyContinue).Count
        Set-EV1 'Инструменты (7-Zip/Notepad++/Sysinternals...)' ($toolsOk -gt 0) ("папок: " + $toolsOk)
      } else { Set-EV1 'Инструменты' $false 'нет payload\Tools' }
    } else {
      Write-Log "  Payload не найден: положи файлы в $env:USERPROFILE\Desktop\H-PE11_Bomb_Payload (DirectX\, VC\, Tools\, Net35\)"
      Set-EV1 'DirectX d3dx-набор' $false 'payload отсутствует'
      Set-EV1 'VC++ Redistributable DLL' $false 'payload отсутствует'
      Set-EV1 'Инструменты' $false 'payload отсутствует'
      # Запасной ход: VC++ 2015-2022 и .NET35 можно снять с самой станции
      foreach ($pair in @(@("$env:SystemRoot\System32\msvcp140.dll","$mount\Windows\System32\msvcp140.dll"),@("$env:SystemRoot\SysWOW64\msvcp140.dll","$mount\Windows\SysWOW64\msvcp140.dll"))) {
        if ((Test-Path $pair[0]) -and (Test-Path (Split-Path $pair[1]))) {
          Copy-Item -LiteralPath $pair[0] -Destination $pair[1] -Force -ErrorAction SilentlyContinue
          Write-Log ("  Запасной ход: " + $pair[0] + " -> образ")
        }
      }
      $vcOk = Test-Path "$mount\Windows\System32\msvcp140.dll"
      if ($vcOk) { $script:HpeEV1 = $script:HpeEV1 | Where-Object { $_ -notlike 'VC++*' }; $script:HpeFail--; Write-Log "  [x] VC++ 2015-2022 взят со станции (частично: только хост-набор)" }
    }
  } catch {
    Write-Log ("СЕКЦИЯ 6 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('Payload :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 7. startnet.cmd + оболочка H-PE11 ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 7. STARTNET + ОБОЛОЧКА H-PE11 =="
  try {
    $sn = @(
      'wpeinit',
      'rem === H-PE11 BOMB shell ===',
      'set PATH=%PATH%;X:\Tools\7-Zip;X:\Tools\Sysinternals;X:\Tools\Notepad++',
      'rem HOLO shell hook: put your start command below',
      'rem start /wait mshta X:\HPE11\holo.hta',
      'cmd.exe'
    )
    Set-Content -LiteralPath "$mount\Windows\System32\startnet.cmd" -Value $sn -Encoding ASCII
    Write-Log "  startnet.cmd записан (wpeinit + PATH инструментов + хук оболочки)"
    Set-EV1 'startnet.cmd H-PE11' $true 'wpeinit + PATH + хук ГОЛОГРАММА'
  } catch {
    Write-Log ("СЕКЦИЯ 7 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('startnet :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 8. Демонтаж + экспорт max-сжатия ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 8. ДЕМОНТАЖ + ЭКСПОРТ =="
  $commitOk = $false
  try {
    $commitOk = Run-Dism -DismArgs @('/Unmount-Wim','/MountDir:' + $mount,'/Commit') -What 'Unmount-Wim + Commit'
    if ($commitOk) {
      $bootOut = "$work\H-PE11_BOMB.boot.wim"
      $exp = Run-Dism -DismArgs @('/Export-Image','/SourceImageFile:' + $bootWimSrc,'/SourceIndex:1','/DestinationImageFile:' + $bootOut,'/Compress:max') -What 'Export-Image compress:max'
      Set-EV1 'boot.wim бомбы собран' ($exp -and (Test-Path $bootOut)) ($bootOut)
      $szWim = if (Test-Path $bootOut) { [math]::Round((Get-Item $bootOut).Length/1MB,1) } else { 0 }
      Write-Log ("  Размер boot.wim: " + $szWim + " МБ")
    } else {
      Set-EV1 'boot.wim бомбы собран' $false 'Commit/Unmount не удался'
      if ($HpeKeepMount) { Write-Log "  Флаг HpeKeepMount=$true: mount оставлен на $mount" }
      else { & "$env:SystemRoot\System32\Dism.exe" '/Cleanup-Wim' 2>$null | Out-Null }
      return
    }
  } catch {
    Write-Log ("СЕКЦИЯ 8 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('Экспорт :: исключение ' + $_.Exception.Message)
    return
  }

  # ---------- СЕКЦИЯ 9. ISO (BIOS+UEFI двойная загрузка) ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 9. ISO BIOS+UEFI (oscdimg) =="
  try {
    $dtRoot = Join-Path $kitsRoot 'Assessment and Deployment Kit\Deployment Tools'
    $oscDir = Join-Path $dtRoot 'amd64\Oscdimg'
    $oscdimg = Join-Path $oscDir 'oscdimg.exe'
    $iso = "$work\H-PE11_BOMB.iso"
    if (Test-Path $oscdimg) {
      $etfs = Join-Path $oscDir 'etfsboot.com'
      $efis = Join-Path $oscDir 'efisys.bin'
      & $oscdimg -m -o -u2 -udfver102 -bootdata:("2#p0,e,b" + $etfs + "#pEF,e,b" + $efis) $media $iso 2>&1 | ForEach-Object { Write-Log ("  | " + ($_ | Out-String).TrimEnd()) }
      $isoOk = ($LASTEXITCODE -eq 0) -and (Test-Path $iso)
      Set-EV1 'ISO двойной загрузки BIOS+UEFI' $isoOk ($iso)
      if ($isoOk) { Write-Log ("  Размер ISO: " + [math]::Round((Get-Item $iso).Length/1MB,1) + " МБ") }
    } else {
      Set-EV1 'ISO двойной загрузки' $false 'oscdimg.exe не найден в Deployment Tools'
    }
  } catch {
    Write-Log ("СЕКЦИЯ 9 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('ISO :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 10. Дымовой контракт + SHA256 + отчёт ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 10. ДЫМОВОЙ КОНТРАКТ + SHA256 (LAW 4) + ОТЧЁТ =="
  $smoke = @()
  try {
    $chk = @(
      @('PowerShell в PE',"$mount\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"),
      @('WMI в PE',"$mount\Windows\System32\wbem\cimwin32.dll"),
      @('HTA в PE',"$mount\Windows\System32\mshta.exe"),
      @('CLR4 в PE',"$mount\Windows\Microsoft.NET\Framework64\v4.0.30319\clr.dll"),
      @('MDAC/ADO в PE',"$mount\Windows\System32\msado15.dll")
    )
    foreach ($c in $chk) {
      $have = Test-Path $c[1]
      $smoke += (@($c[0], $have))
      if ($have) { Write-Log ("  [x] " + $c[0]) } else { Write-Log ("  [--] " + $c[0] + " (файл не найден)") }
    }
    $dism = "$env:SystemRoot\System32\Dism.exe"
    $pkgs = & $dism '/Image:' + $mount '/Get-Packages' '/English' 2>$null
  } catch { }
  try {
    if (Test-Path $mount) {
      $pkgs = & "$env:SystemRoot\System32\Dism.exe" ('/Image:' + $mount) '/Get-Packages' '/English' 2>$null
      $winpePkgs = ($pkgs | Select-String -Pattern 'WinPE-').Count
      Write-Log ("  Пакетов WinPE- в образе: " + $winpePkgs)
      & "$env:SystemRoot\System32\Dism.exe" ('/Image:' + $mount) '/Get-Drivers' '/English' 2>$null | Select-String -Pattern 'oem' | ForEach-Object { } | Out-Null
    }
  } catch { }
  try {
    # демонтируем для финальной проверки (если ещё смонтирован)
    $stillMounted = Get-ChildItem "$mount\Windows" -ErrorAction SilentlyContinue
    if ($stillMounted) { & "$env:SystemRoot\System32\Dism.exe" '/Unmount-Wim','/MountDir:' + $mount,'/Discard' 2>$null | Out-Null }
  } catch { }
  try {
    $hashes = @()
    foreach ($f in @("$work\H-PE11_BOMB.boot.wim","$work\H-PE11_BOMB.iso",$log)) {
      if ($f -and (Test-Path $f)) {
        $h = Get-FileHash -LiteralPath $f -Algorithm SHA256
        $hashes += ($h.Hash + "  " + (Split-Path $f -Leaf))
      }
    }
    $sums = "$work\SHA256SUMS.txt"
    Set-Content -LiteralPath $sums -Value $hashes -Encoding ASCII
    Write-Log ("  SHA256SUMS.txt: " + $sums)
    Set-EV1 'SHA256SUMS (Law 4)' ($hashes.Count -gt 0) $sums
    $rep = "$work\BOMB-REPORT.txt"
    $r = @()
    $r += 'H-PE11 // BOMB REPORT v1.0'
    $r += ('Дата: ' + $ts)
    $r += ('Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ | ЭВ.1: недоступно = НЕ сделано')
    $r += ''
    $r += '== ЭВ.1 СВОД =='
    if ($script:HpeEV1.Count -eq 0) { $r += '  [x] все заявленные элементы bombs состоялись' }
    else { foreach ($e in $script:HpeEV1) { $r += ('  [--] ' + $e) } }
    $r += ''
    $r += '== ДЫМОВОЙ КОНТРАКТ (внутри образа, файлы) =='
    for ($i = 0; $i -lt $smoke.Count; $i += 2) {
      if ($smoke[$i+1]) { $r += ('  [x] ' + $smoke[$i]) } else { $r += ('  [--] ' + $smoke[$i]) }
    }
    $r += ''
    $r += '== ПРОВЕРКА НА ЖЕЛЕЗЕ (делает Хозяин) =='
    $r += '  1) BIOS-загрузка: выбери USB/ISO в boot-меню, дождись cmd после wpeinit [--]'
    $r += '  2) UEFI-загрузка: то же через UEFI-меню [--]'
    $r += '  3) В PE: powershell -c "Get-Disk" (StorageWMI), mshta ?, ipconfig [--]'
    $r += '  4) Сеть: netsh wlan / ipconfig; wintun: wireguard-сценарии [--]'
    $r += '  5) Ядро ГОЛОГРАММА: хук в startnet.cmd [--]'
    $r += ''
    $r += ('Лог сборки: ' + $log)
    Set-Content -LiteralPath $rep -Value $r -Encoding UTF8
    Write-Log ("  Отчёт: " + $rep)
  } catch {
    Write-Log ("СЕКЦИЯ 10 ОШИБКА: " + $_.Exception.Message)
  }

  Write-Log ""
  Write-Log "=================================================================="
  Write-Log "  БОМБА: сборка завершена. Рабочая папка: $work"
  if ($script:HpeEV1.Count -gt 0) {
    Write-Log ("  ЭВ.1: незакрытых позиций: " + $script:HpeEV1.Count + " (см. BOMB-REPORT.txt)")
  } else {
    Write-Log "  ЭВ.1: все позиции закрыты [x]"
  }
  Write-Log "=================================================================="
}
