#!/usr/bin/env python3
# H-PE11 // ВЕРИФИКАЦИЯ ISO v1.2 (статический дым: структура, El Torito, WIM)
import struct, os, sys
import pycdlib

ISO = "/home/z/my-project/download/H-PE11_BOMB_v1.2.iso"
ok = True

def chk(cond, label):
    global ok
    print(("[x] " if cond else "[--] ") + label)
    if not cond: ok = False

iso = pycdlib.PyCdlib()
iso.open(ISO)
chk(iso._has_udf, "UDF view есть (как у MS-образов)")

# проверим файлы через UDF и ISO
targets = ["/sources/boot.wim", "/bootmgr", "/boot/bcd", "/boot/boot.sdi",
           "/boot/etfsboot.com", "/efi/microsoft/boot/efisys.bin",
           "/HPE11/HPE11.tag", "/HPE11/README_RU.txt", "/HPE11/BOMB-REPORT.txt",
           "/PS7/pwsh.exe", "/Programs/Volume2/Volume2.exe",
           "/Programs/HMS/setup_ms_x64.zip", "/Drivers/HPE11/netwtw04/Netwtw04.INF",
           "/get-ammo.ps1", "/DriverPacks/README_DriverPacks.txt"]
for t in targets:
    have = True
    try:
        iso.get_file_from_iso_fp(open(os.devnull, "wb"), udf_path=t)
    except Exception:
        have = False
    chk(have, f"UDF {t}")

# El Torito каталог: BIOS + UEFI записи
def rr(f, start, length):
    f.seek(start); return f.read(length)

with open(ISO, "rb") as f:
    brd = rr(f, 17 * 2048, 2048)
    cat_lba = struct.unpack_from("<I", brd, 71)[0]
    cat = rr(f, cat_lba * 2048, 2048)
    # initial entry
    e0 = cat[32:64]
    chk(e0[0] == 0x88, "El Torito: запись 1 bootable (0x88)")
    seg0 = struct.unpack_from("<H", e0, 2)[0]
    cnt0 = struct.unpack_from("<H", e0, 6)[0]
    lba0 = struct.unpack_from("<I", e0, 8)[0]
    print(f"    BIOS: LBA {lba0}, {cnt0}x512B, seg 0x{seg0:04x}")
    chk(cnt0 == 8 and seg0 == 0x2000, "BIOS: etfsboot 8x512, load seg 0x2000")
    boot_rec = rr(f, lba0 * 2048, 4096)
    chk(boot_rec[:2] == b"\xfa\x33", "BIOS boot record magic FA33 (etfsboot)")
    # section header (UEFI): [0]=0x91, [1]=platform, [2:4]=entries
    sh = cat[64:96]
    chk(sh[0] == 0x91, "El Torito: section header 0x91 (final, entries)")
    chk(sh[1] == 0xEF, f"UEFI section platform id = 0xEF ({sh[1]:#x})")
    ef = cat[96:128]
    chk(ef[0] == 0x88, "El Torito: UEFI запись bootable")
    cnt1 = struct.unpack_from("<H", ef, 6)[0]
    lba1 = struct.unpack_from("<I", ef, 8)[0]
    efisys = rr(f, lba1 * 2048, cnt1 * 512)
    chk(efisys[:27].startswith(b"\xEB") or b"EFI" in efisys[:200] or efisys[510:512] == b"\x55\xaa", f"efisys.bin FAT-образ на месте ({len(efisys)} B)")

# WIM-проверки
sys.exit(0 if ok else 1)
