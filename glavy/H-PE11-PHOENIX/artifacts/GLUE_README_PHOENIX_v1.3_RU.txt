ФЕНИКС-11 // PHOENIX-11 v1.3 — СКЛЕЙКА ЧАСТЕЙ
=============================================
Части: H-PE11_PHOENIX_v1.3.iso.001 + .002 + .003 (простая нарезка байт, не zip)

Windows (cmd):
  copy /b H-PE11_PHOENIX_v1.3.iso.001+H-PE11_PHOENIX_v1.3.iso.002+H-PE11_PHOENIX_v1.3.iso.003 H-PE11_PHOENIX_v1.3.iso

Linux/macOS:
  cat H-PE11_PHOENIX_v1.3.iso.001 H-PE11_PHOENIX_v1.3.iso.002 H-PE11_PHOENIX_v1.3.iso.003 > H-PE11_PHOENIX_v1.3.iso

Проверка (Law 4): сверить SHA256 склеенного файла с H-PE11_PHOENIX_v1.3.SHA256
  SHA256 ISO: c0cb338a1334e8f3a2dbd27e1007a0279976b24cd89d78b98da3a81483f08c53
  certutil -hashfile H-PE11_PHOENIX_v1.3.iso SHA256   (Windows)
  sha256sum H-PE11_PHOENIX_v1.3.iso                    (Linux)

Запись: Rufus (GPT/UEFI или MBR/BIOS) или dd. Подробнее: PHOENIX_README_RU.txt (в ISO).
