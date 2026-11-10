
  # ---------- СЕКЦИЯ 7. startnet.cmd + PATH всех снарядов ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 7. STARTNET + PATH СНАРЯДОВ =="
  try {
    $sn = @(
      'wpeinit',
      'rem === H-PE11 BOMB shell v1.1 ===',
      'set PATH=%PATH%;X:\Tools\Python;X:\Tools\wget;X:\Tools\7-Zip;X:\Tools\Sysinternals;X:\Tools\Notepad++',
      'rem DriverPacks (если есть на носителе):',
      'for %%i in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist "%%i:\DriverPacks" set DPPATH=%%i:\DriverPacks',
      'if defined DPPATH echo DriverPacks: %DPPATH%',
      'rem HOLO shell hook: put your start command below',
      'rem start "" /wait mshta X:\HPE11\holo.hta',
      'rem start "" "X:\Programs\Volume2\Volume2.exe" /tray',
      'cmd.exe'
    )
    Set-Content -LiteralPath "$mount\Windows\System32\startnet.cmd" -Value $sn -Encoding ASCII
    Write-Log "  startnet.cmd: wpeinit + PATH (Python/wget/Tools) + DriverPacks-детект + хуки"
    Set-EV1 'startnet.cmd H-PE11 v1.1' $true 'wpeinit + PATH + хуки ГОЛОГРАММА/Volume2'
  } catch {
    Write-Log ("СЕКЦИЯ 7 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('startnet :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 8. Дым по файлам (пока смонтирован) + демонтаж + экспорт ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 8. ДЫМ ПО ФАЙЛАМ + ДЕМОНТАЖ + ЭКСПОРТ =="
  $commitOk = $false
  try {
    $chk = @(
      @('PowerShell в PE',"$mount\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"),
      @('WMI в PE',"$mount\Windows\System32\wbem\cimwin32.dll"),
      @('HTA в PE',"$mount\Windows\System32\mshta.exe"),
      @('CLR4 в PE',"$mount\Windows\Microsoft.NET\Framework64\v4.0.30319\clr.dll"),
      @('MDAC/ADO в PE',"$mount\Windows\System32\msado15.dll"),
      @('curl in-box',"$mount\Windows\System32\curl.exe"),
      @('Курсор XpucT normal',"$mount\Windows\Cursors\XpucT\01 XpucT - normal.cur")
    )
    foreach ($c in $chk) {
      $have = Test-Path $c[1]
      $script:HpeSmoke += @($c[0], $have)
      if ($have) { Write-Log ("  [x] " + $c[0]) } else { Write-Log ("  [--] " + $c[0] + " (файла нет)") }
    }
    $commitOk = Run-Dism -DismArgs @('/Unmount-Wim','/MountDir:' + $mount,'/Commit') -What 'Unmount-Wim + Commit'
    if ($commitOk) {
      $bootOut = "$work\H-PE11_BOMB.boot.wim"
      $exp = Run-Dism -DismArgs @('/Export-Image','/SourceImageFile:' + $bootWimSrc,'/SourceIndex:1','/DestinationImageFile:' + $bootOut,'/Compress:max') -What 'Export-Image compress:max'
      Set-EV1 'boot.wim бомбы собран' ($exp -and (Test-Path $bootOut)) $bootOut
      if (Test-Path $bootOut) { Write-Log ("  Размер boot.wim: " + [math]::Round((Get-Item $bootOut).Length/1MB,1) + " МБ") }
    } else {
      Set-EV1 'boot.wim бомбы собран' $false 'Commit/Unmount не удался'
      & "$env:SystemRoot\System32\Dism.exe" '/Cleanup-Wim' 2>$null | Out-Null
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
      $etfs = "$work\etfsboot.com"
      $efis = "$work\efisys.bin"
      Copy-Item -LiteralPath (Join-Path $oscDir 'etfsboot.com') -Destination $etfs -Force
      Copy-Item -LiteralPath (Join-Path $oscDir 'efisys.bin') -Destination $efis -Force
      if ((Test-Path $etfs) -and (Test-Path $efis)) {
        $bootdata = "-bootdata:2#p0,e,b$etfs#pEF,e,b$efis"
        & $oscdimg -m -o -u2 -udfver102 $bootdata $media $iso 2>&1 | ForEach-Object { $s = ($_ | Out-String).TrimEnd(); if ($s.Length -gt 0) { Write-Log ("  | " + $s) } }
        $isoOk = ($LASTEXITCODE -eq 0) -and (Test-Path $iso)
      } else { Write-Log "  [--] etfsboot.com/efisys.bin не найдены"; $isoOk = $false }
      Set-EV1 'ISO двойной загрузки BIOS+UEFI' $isoOk $iso
      if ($isoOk) { Write-Log ("  Размер ISO: " + [math]::Round((Get-Item $iso).Length/1MB,1) + " МБ") }
    } else {
      Set-EV1 'ISO двойной загрузки' $false 'oscdimg.exe не найден в Deployment Tools'
    }
  } catch {
    Write-Log ("СЕКЦИЯ 9 ОШИБКА: " + $_.Exception.Message)
    $script:HpeEV1 += ('ISO :: исключение ' + $_.Exception.Message)
  }

  # ---------- СЕКЦИЯ 10. SHA256 (LAW 4) + ОТЧЁТ ЭВ.1 ----------
  Write-Log ""
  Write-Log "== СЕКЦИЯ 10. SHA256 (LAW 4) + ОТЧЁТ ЭВ.1 =="
  try {
    $hashes = @()
    foreach ($f in @("$work\H-PE11_BOMB.boot.wim","$work\H-PE11_BOMB.iso")) {
      if (Test-Path $f) {
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
    $r += 'H-PE11 // BOMB REPORT v1.1'
    $r += ('Дата: ' + $ts)
    $r += 'Закон: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ | ЭВ.1: недоступно = НЕ сделано'
    $r += ''
    $r += '== ЭВ.1 СВОД =='
    if ($script:HpeEV1.Count -eq 0) { $r += '  [x] все заявленные элементы бомбы состоялись' }
    else { foreach ($e in $script:HpeEV1) { $r += ('  [--] ' + $e) } }
    $r += ''
    $r += '== ДЫМОВОЙ КОНТРАКТ (файлы внутри образа) =='
    for ($i = 0; $i -lt $script:HpeSmoke.Count; $i += 2) {
      if ($script:HpeSmoke[$i+1]) { $r += ('  [x] ' + $script:HpeSmoke[$i]) } else { $r += ('  [--] ' + $script:HpeSmoke[$i]) }
    }
    $r += ''
    $r += ('== ПАКЕТЫ WinPE- в образе: ' + $script:HpePkgCount + ' | Сторонних драйверов: ' + $script:HpeDrvCount + ' ==')
    $r += ''
    $r += '== ПРОВЕРКА НА ЖЕЛЕЗЕ (делает Хозяин) =='
    $r += '  1) BIOS-загрузка ISO с USB, дождись cmd после wpeinit [--]'
    $r += '  2) UEFI-загрузка того же ISO [--]'
    $r += '  3) В PE: powershell -c "Get-Disk" (StorageWMI), mshta ?, ipconfig [--]'
    $r += '  4) python --version; wget --help (обёртка curl); curl --version [--]'
    $r += '  5) X:\Programs\Volume2\Volume2.exe — скины, вкл. Office 2019 Black [--]'
    $r += '  6) X:\Programs\HMS\HMS.exe — медиа-сервер UPnP/DLNA [--]'
    $r += '  7) X:\Tools\LoginUnlocker — сброс входа [--]'
    $r += '  8) Мышь: курсоры XpucT должны быть активны сразу [--]'
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
