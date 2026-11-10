H-PE11 // PHOENIX-ALPHA 0.2-BISECT (Plan B)
=====================================================================
ЗАЧЕМ ЭТА СБОРКА
  Бисекция после двух провалов установки alpha-0.1 на станции
  i3-2120 (H67, Legacy BIOS, MBR). Провал #1: BCD c000000f.
  Провал #2: жёсткий обрыв на specialize, «реестр заблокирован».

ЧТО ИЗМЕНИЛОСЬ ПРОТИВ ALPHA-0.1 (всё остальное - БАЙТ-В-БАЙТ)
  1. autounattend.xml v4: НЕТ авто-юзера 6orman, НЕТ AutoLogon,
     НЕТ пароля Phoenix-2026 на носителе (аудит: пароль открытым
     текстом). Юзер создаётся РУКАМИ в OOBE.
  2. SetupComplete = ТОЛЬКО драйверы (pnputil C:\\Drivers).
     TWEAKPACK и аудит НЕ запускаются автоматом.
  3. Драйверы вшиты: $WinPEDriver$ (PE-фаза) + C:\\Drivers
     (OS-фаза). Комплект DP_6ORMAN_x64 (экспорт с рабочего
     железа, 95 INF: чипсет 6 Series/C200, SATA AHCI 1C02,
     ASMedia USB3 xHCI, VIA HD Audio, Realtek GbE, HD Graphics).
  4. Патчи аудита 001 (CONTROL меню) и 002 (PHX-RUN) применены
     к киту в C:\\PHX\\bin.
  5. install.wim / boot.wim / bootmgr / efisys - НЕ ТРОНУТЫ
     (хеши в TREE_PROVENANCE_SHA256.txt на релизе).

КАК СТАВИТЬ (Legalacy/MBR, станция CSM-only)
  1. Склеить ISO: PHX-GLUE-ISO.bat v5 (или 7-Zip: .001 Extract Here)
  2. Проверка Law 4: SHA256 = см. SHA256SUMS.txt релиза
  3. Rufus: MBR, BIOS (или UEFI-CSM), NTFS
  4. Загрузка Legacy. Диск выбрать ВРУЧНУЮ: незанятое ~60 ГБ
     на Диске 0 (System+C: установщик создаст сам).
     E: Data и F: STREL НЕ ТРОГАТЬ.
  5. OOBE: юзера создать РУКАМИ (локальная учётка).
  6. После входа: C:\\PHX\\bin\\PHOENIX-CONTROL.cmd - всё руками.
     TWEAKPACK применять профилями (Report -> Apply) ПОСЛЕ того,
     как система признана живой.

ЛОГИ ПОСЛЕ УСТАНОВКИ
  C:\\PHX\\logs\\setupcomplete.log  (pnputil: exit=N)
  Если установка снова умрёт жёстко на specialize при чистом
  BurnInTest/MemTest - вердикт: конфликт начинки среды/BIOS,
  бисекция продолжается на следующем уровне.
=====================================================================
