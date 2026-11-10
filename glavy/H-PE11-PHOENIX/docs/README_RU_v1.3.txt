ФЕНИКС-11 // PHOENIX-11 v1.3 (PHOENIX EDITION) // WinPE 11 26H2 x64
====================================================================
Слоган: Встаёт из пепла. Поднимает другие.
Закон проекта: ЧЕЛОВЕК=СИСТЕМА=ЦЕЛОЕ. ЭВ.1: недоступно = НЕ сделано ([--]).
Режим: БОМБА — официальные матрицы поддержки не ограничивают интеграцию.

ЧТО ЭТО
  Оригинальная сборка WinPE 11 на базе официального boot.wim Microsoft
  (Windows 11 26H2 ru-RU, ISO собран без ADK/DISM: wimlib + pycdlib;
  стартовые записи BIOS+UEFI — подлинные файлы MS).
  v1.3 — первое издание ФЕНИКС: лёгкий перелёт с v1.2, арсенал не тронут.

ЧТО НОВОГО В v1.3 ПРОТИВ v1.2
  1) Бренд ФЕНИКС-11: обои (background.bmp + winpe.jpg — жар-птица из углей),
     консоль (меню [F]), метка тома PHOENIX11_V13, README/тег/отчёты.
  2) Политика тачпада (решение Хозяина): СТАНДАРТНЫЙ in-box Microsoft
     (hidi2c + iaLPSS2i_I2C уже в базе boot.wim). Вендорные паки Synaptics/
     ELAN/ALPS НЕ включены (0 байт): весят духуя, толку от настроек нулевые.
     Тачпад работает как обычная мышь — жесты не нужны, Хозяин его не юзает.
  3) Арсенал v1.2 перенесён без изменений (список ниже).

КАК ЗАГРУЗИТЬСЯ
  1) Rufus (GPT/UEFI или MBR/BIOS) -> записать H-PE11_PHOENIX_v1.3.iso на USB 4 ГБ+.
     Либо dd if=...iso of=/dev/sdX bs=4M status=progress.
  2) Загрузиться с USB (F7/F8/F11/Boot Menu).
  3) После wpeinit откроется консоль ФЕНИКС-11 (меню). Мышь работает.

СОСТАВ (унаследован от v1.2 без изменений)
  В WIM (X:): curl.exe, курсоры XpucT (схема активна с загрузки),
  X:\Tools: Python 3.12, wget(обёртка curl), 7-Zip (7zr), Notepad++,
  Sysinternals, консоль ФЕНИКС-11.
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
  -- Тачпад: стандартный in-box, жестов НЕТ (и не надо).

ПРОВЕРКИ НА ЖЕЛЕЗЕ (делает Хозяин)
  1) BIOS-загрузка USB;  2) UEFI-загрузка;
  3) мышь+клавиатура (USB/тачпад);  4) сеть (ipconfig);
  5) WLAN (netwtw04 drvload);  6) Volume2;  7) pwsh -v;  8) python -V.

SHA256SUMS.txt — Law 4: рядом с ISO и в \HPE11\docs.
