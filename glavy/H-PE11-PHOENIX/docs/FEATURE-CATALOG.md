# H-PE11 // КАТАЛОГ ФУНКЦИЙ БОМБЫ v1.0

Закон: ЧЕЛОВЕК = СИСТЕМА = ЦЕЛОЕ > суммы частей. ЭВ.1: недоступно = НЕ сделано (метка `[--]`).
Режим: **БОМБА** (решение Хозяина: человек >共识=протокол; официальные матрицы поддержки не ограничивают интеграцию).
Статус каталога: утверждён Хозяином («все условия согласованы»).

---

## 1. Официальные опциональные компоненты ADK (WinPE_OCs)

Порядок интеграции жёсткий: сначала языковой пакет (если есть), затем зависимости, затем потребители.
Команда каждого: `DISM /Image:<mnt> /Add-Package /PackagePath:<WinPE_OCs>\<имя>.cab`
(+ языкозависимая версия из `<WinPE_OCs>\ru-RU\`, если присутствует).

| # | Компонент | Зависимости | Что даёт бомбе | Риск загрузки | Статус |
|---|-----------|-------------|----------------|---------------|--------|
| 1 | WinPE-WMI | — | WMI/CIM-инфраструктура: база для PowerShell, StorageWMI, DismCmdlets, диагностики железа | Низкий | план [x] |
| 2 | WinPE-Scripting | — | cscript/wscript, VBScript/JScript: legacy-утилиты OEM и HTA-обвязка | Низкий | план [x] |
| 3 | WinPE-NetFx | — | CLR .NET 4.x в PE: запуск exe/dll-сборок .NET Framework | Низкий (проверить на 26H1) | план [x] |
| 4 | WinPE-PowerShell | WMI, NetFx, Scripting | Полноценный PS 5.1 в PE: модули, скрипты, сценарии восстановления | Средний: +~120 МБ к WIM | план [x] |
| 5 | WinPE-StorageWMI | WMI, PowerShell | Storage/CIM: Get-Disk, Get-Partition, работа с RAID/NVMe-хранилищами | Низкий | план [x] |
| 6 | WinPE-DismCmdlets | PowerShell | DISM внутри PS: ремонт WIM/образов из самой бомбы | Низкий | план [x] |
| 7 | WinPE-MDAC | — | ADO/OLEDB/ODBC: доступ к SQL/данным, восстановление реестров и БД | Низкий | план [x] |
| 8 | WinPE-HTA | — | mshta: графические оболочки восстановления без полного UI-стека | Низкий | план [x] |
| 9 | WinPE-FMAPI | — | Доступ к файловой системе из кастомных приложений (File Management API) | Низкий | план [x] |
| 10 | WinPE-SecureStartup | WMI | BitLocker: manage-bde, разблокировка зашифрованных томов | Низкий | план [x] |
| 11 | WinPE-WDS-Tools | — | PXE-клиент/WDSTftp: загрузка образов по сети (пресет сети со станции) | Низкий | план [x] |
| 12 | WinPE-Setup (Main/Client) | — | Среда установки Windows (setup.exe внутри PE) | Высокий: +~200 МБ | опция, по умолчанию `[--]` (флаг `$AddSetupPkgs`) |
| 13 | WinPE-SRT | Setup | Среда восстановления (сценарии «восстановление системы») | Высокий: +~250 МБ | опция, по умолчанию `[--]` |

Примечание по порядку: фактический порядок добавления в скрипте — WMI → Scripting → NetFx →
PowerShell → StorageWMI → DismCmdlets → MDAC → HTA → FMAPI → SecureStartup → WDS-Tools.
DISM сам разрешит остаточные зависимости; сбой одного cab не останавливает сборку (журнал + отчёт).

## 2. .NET в бомбе

| Слой | Источник | Метод интеграции | Риск | Статус |
|------|----------|------------------|------|--------|
| .NET 4.x (CLR4) | ADK WinPE-NetFx | /Add-Package (официально) | Низкий | план [x] |
| .NET 3.5 / CLR 2.0 | Рабочая станция: `C:\Windows\Microsoft.NET\Framework64\v2.0.50727`, `Framework64\v3.5`, `Framework\v3.5` (или payload `Net35\`) | Копирование дерева в `<mnt>\Windows\Microsoft.NET\` + правка SOFTWARE-hive (политики Fusion, `OnlyUseLatestCLR`) | Средний: часть API зависит от GAC ОС; WPF 3.5 может не подняться — консоль/WinForms обычно работают | метод [x], факт `[--]` до дымового прогона |

## 3. DirectX

| Слой | Источник | Метод | Риск | Статус |
|------|----------|-------|------|--------|
| DX-ядро (d3d10/11/12, dxgi, D3DCompiler_47) | База WinPE 11 (in-box) | уже в boot.wim | Нулевой | [x] |
| d3dx9_43 / d3dx10_43 / d3dx11_43 / d3dx9_24..42 | DirectX End-User Runtime (июнь 2010) или payload `DirectX\` | Копия DLL в `<mnt>\Windows\System32` (x64) и `SysWOW64` (x86) | Низкий: user-mode DLL, загрузке не мешает | payload → [x], иначе `[--]` |
| GPU-драйвер пользовательского режима | Драйвер станции iigd_dch.inf v26.20.100.6813 | DISM /Add-Driver (тянет igdUM/igd10iumd64) | Низкий | план [x] |

## 4. Visual C++ Redistributable

| Год/версия | DLL (x64 + x86) | Источник | Статус |
|-----------|------------------|----------|--------|
| 2015–2022 | msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll, concrt140.dll | payload `VC\` или `%SystemRoot%\System32` + `SysWOW64` станции | payload/станция → [x], иначе `[--]` |
| 2013 | msvcr120.dll, msvcp120.dll | то же | то же |
| 2012 | msvcr110.dll, msvcp110.dll | то же | то же |
| 2010 | msvcr100.dll, msvcp100.dll | то же | то же |
| 2008 | msvcr90.dll, msvcp90.dll | то же | то же |
| 2005 | msvcr80.dll, msvcp80.dll | то же | то же |

## 5. Сторонние инструменты (снаряды)

| Инструмент | Источник на станции | Куда в PE | Риск | Статус |
|-----------|--------------------|-----------|------|--------|
| 7-Zip (7z.exe, 7z.dll, x64+x86) | `%ProgramFiles%\7-Zip` или payload `Tools\7-Zip` | `<mnt>\Tools\7-Zip` + PATH-обвязка в startnet | Низкий | план [x] |
| Notepad++ | `%ProgramFiles%\Notepad++` или payload | `<mnt>\Tools\Notepad++` | Низкий | план [x] |
| Sysinternals: procexp64, procmon64, handle64, autorunsc64, pslist, psexec | payload `Tools\Sysinternals` | `<mnt>\Tools\Sysinternals` | Низкий | план [x] |
| Сетевой набор: ipconfig/netsh/ping (in-box), wintun-драйвер | in-box + драйвер станции | — | Низкий | [x] |
| WireGuard (wintun.inf v0.14.0.0) | Драйвер станции | /Add-Driver | Низкий | план [x] |

## 6. Драйверы станции 6ORMAN → boot.wim (критичный whitelist, 11 INF)

Источник: лог `H-PE11_STATION_COLLECT_2026-10-17_10-03-06.log`, экспорт `WinPE_Drivers` (1150 МБ).
Интеграция: только whitelisted папки (НЕ весь экспорт целиком — экономия ~1 ГБ).

| Класс | INF | Версия | Зачем в PE | Статус |
|-------|-----|--------|-----------|--------|
| Display | iigd_dch.inf | 26.20.100.6813 | Intel HD Graphics (Apollo Lake): рабочее разрешение 1366×768 | план [x] |
| Net | netwtw04.inf | 19.51.50.2 | Intel Wi-Fi: PXE/сетевые сценарии | план [x] |
| Net | wintun.inf | 0.14.0.0 | WireGuard-туннель | план [x] |
| System | apollolakesystem.inf | 10.1.1.38 | SoC Apollo Lake: базовые устройства чипсета | план [x] |
| System | dptf_acpi.inf | 8.3.10207.5567 | Тепло/энергополитика | план [x] |
| System | dptf_cpu.inf | 8.3.10207.5567 | Тепло CPU | план [x] |
| System | esif_manager.inf | 8.3.10207.5567 | ESIF-менеджер (зависимость DPTF) | план [x] |
| System | ialpss2_spi_bxt_p.inf | 30.100.1631.3 | SPI-контроллер LPSS | план [x] |
| System | ialpss2_uart2_bxt_p.inf | 30.100.1631.3 | UART2 LPSS | план [x] |
| System | txei.inf | 3.0.0.1115 | TXE-интерфейс (платформа Intel) | план [x] |
| USB | rtsuer.inf | 10.0.17134.31243 | Realtek USB (картридер/USB-устройства) | план [x] |

Хранилище: контроллеры eMMC/SD (SLD64G) и SATA (WD3200) закрываются in-box драйверами Win11
(storahci/sdstor) — сторонних storage-драйверов на станции нет, добавлять нечего `[--] нет данных о NAS/SAS/RAID`.

## 7. Ограничения платформы (из лога станции)

- CPU Celeron N3350 (2 ядра), RAM 4 ГБ → целевой размер boot.wim ≤ ~800 МБ, ISO ≤ ~1.2 ГБ.
- Secure Boot = False, AMI BIOS 2020 → подписи не критичны, `/ForceUnsigned` допустим.
- Локаль ru-RU, ACP 1251 / OEM 866 → PS-скрипты проекта хранить в UTF-8 BOM.
- Лог станции оборван на секции 5 (СЕТЬ) → секции 5–10 (PXE-пресет, софт, winget, appx, деинсталляторы, оформление) `[--]`; интеграция пресетов будет отдельным шагом после повторного сбора.

## 8. ЭВ.1 — свод по бомбе

- Каталог и метод сборки: [x] (этот документ + build-bomb.ps1).
- Собранный boot.wim: `[--]` — собирается на станции Хозяина скриптом build-bomb.ps1.
- Дымовой контракт 5/5 (BIOS+UEFI): `[--]` — проверка после сборки.
- Payload (DirectX d3dx, VC++, Sysinternals, Notepad++): `[--]` — появится, когда положишь файлы в `H-PE11_Bomb_Payload\`.
- Секции 5–10 лога станции: `[--]`.
