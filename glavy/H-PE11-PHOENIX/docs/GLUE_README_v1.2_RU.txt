Склейка частей (Windows cmd):
  copy /b H-PE11_BOMB_v1.2.zip.001+H-PE11_BOMB_v1.2.zip.002 H-PE11_BOMB_v1.2.zip
Проверка после склейки:
  certutil -hashfile H-PE11_BOMB_v1.2.zip SHA256
Должно быть:
  cacfd4db619259dc501b69830474c8e586d4c46af02a2bee9980a8ac5e4b8420
Внутри ZIP: H-PE11_BOMB_v1.2.iso (SHA256 4cb319f6347b95f11436951aeff58f629227e4d03510ea96b031a154c8b512fb) + SHA256 + README_RU + BOMB-REPORT
Bin: https://filebin.net/XXXXXXXXXx7z  (живёт до 2026-10-25)
