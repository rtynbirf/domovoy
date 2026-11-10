H-PE11 BOMB v1.2 // WinPE 11 26H2 x64 (26300.9457 ru-RU)
=============================================================
Закон проекта: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ. ЭВ.1: недоступно = НЕ сделано ([--]).
Режим: БОМБА — официальные матрицы поддержки не ограничивают интеграцию.

ЧТО ЭТО
  Оригинальная сборка WinPE 11 на базе официального boot.wim Microsoft
  (Windows 11 26H2 ru-RU, ISO собран в песочнице, без ADK/DISM:
  wimlib + pycdlib; стартовые записи BIOS+UEFI — подлинные файлы MS).

КАК ЗАГРУЗИТЬСЯ
  1) Rufus (GPT/UEFI или MBR/BIOS) -> записать H-PE11_BOMB_v1.2.iso на USB 4 ГБ+.
     Либо dd if=...iso of=/dev/sdX bs=4M status=progress.
  2) Загрузиться с USB (F7/F8/F11/Boot Menu).
  3) После wpeinit откроется консоль H-PE11 (меню). Мышь работает.

СОСТАВ
  В WIM (X:): curl.exe, VC++ runtime DLL, курсоры XpucT (схема активна
  с загрузки), X:\Tools: Python 3.12, wget(обёртка curl), 7-Zip (7zr),
  Notepad++, Sysinternals, консоль H-PE11.
  На носителе (Y:\HPE11): PowerShell 7.4.6 portable, отчёты ЭВ.1, SHA256SUMS.
  \Programs\Volume2 (v1.1.9.470, скины), \Programs\HMS (медиа-сервер).
  \Drivers\HPE11: whitelist драйверы станции (drvload при загрузке).
  \DriverPacks: положите сюда паки SSTR (H:\SSTR\DriverPacks) — при
  наличии папки startnet объявит DPPATH.

ЭВ.1 ОГОВОРКИ (честно)
  -- PowerShell 5.1/HTA/NetFx/DISM в WIM НЕТ (без ADK их не добавить):
     компенсировано PowerShell 7 portable на носителе.
  -- HMS требует .NET 4.x [--]: размещён, но полноценный запуск ограничен.
  -- DirectX d3dx, Login Unlocker, SSTR DriverPacks, часть драйверов
     whitelist [--]: хостинги недоступны из песочницы; пути доложения в README.
  -- Драйверы грузятся через drvload (runtime), не через DISM /Add-Driver.

ПРОВЕРКИ НА ЖЕЛЕЗЕ (делает Хозяин)
  1) BIOS-загрузка USB;  2) UEFI-загрузка;
  3) мышь+клавиатура (USB/тачпад Apollo Lake);  4) сеть (ipconfig);
  5) WLAN (netwtw04 drvload);  6) Volume2;  7) pwsh -v;  8) python -V.

SHA256SUMS.txt — Law 4: рядом с ISO и в \HPE11\docs.
