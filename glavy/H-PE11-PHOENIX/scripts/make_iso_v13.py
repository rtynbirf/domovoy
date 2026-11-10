#!/usr/bin/env python3
# PHOENIX-11 // ISO BUILDER v1.3: pycdlib, ISO9660 L3 + Joliet + UDF, El Torito BIOS (etfsboot) + UEFI (efisys)
import os, sys, math
import pycdlib

MEDIA = "/tmp/my-project/build/v13/media_v13"
OUT = "/tmp/my-project/download/H-PE11_PHOENIX_v1.3.iso"
LABEL = "PHOENIX11_V13"

def iso_name(rel):
    """ISO9660 d1-имя (A-Z 0-9 _) из пути."""
    name = os.path.basename(rel)
    base, ext = os.path.splitext(name)
    base = "".join(c if (c.isalnum() or c == "_") else "_" for c in base.upper())
    ext = "".join(c if c.isalnum() else "_" for c in ext.upper().lstrip("."))
    return base + ("." + ext if ext else "")

def main():
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=3, joliet=True, udf="2.60", vol_ident=LABEL)

    # --- каталоги (явно, включая вложенные) ---
    for root, dirs, _ in os.walk(MEDIA):
        rel_root = os.path.relpath(root, MEDIA)
        if rel_root == ".":
            continue
        parts = rel_root.split(os.sep)
        san = []
        for p in parts:
            p = "".join(c if (c.isalnum() or c == "_") else "_" for c in p.upper())
            san.append(p)
        iso_p = "/" + "/".join(san)
        j_p = "/" + rel_root.replace(os.sep, "/")
        try:
            iso.add_directory(iso_path=iso_p, joliet_path=j_p, udf_path=j_p)
        except Exception as e:
            print(f"[i] dir {iso_p}: {e}")

    # --- файлы медиа (boot.cat НЕ добавляем: pycdlib создаёт El Torito каталог сама) ---
    count = 0
    used_iso = {}
    for root, dirs, files in os.walk(MEDIA):
        rel_root = os.path.relpath(root, MEDIA)
        for f in sorted(files):
            rel = os.path.normpath(os.path.join(rel_root, f)) if rel_root != "." else f
            if rel.lower() == "boot.cat":
                continue
            local = os.path.join(root, f)
            parent = os.path.dirname(rel)
            if parent and parent != ".":
                san_par = []
                for p in parent.split(os.sep):
                    san_par.append("".join(c if (c.isalnum() or c == "_") else "_" for c in p.upper()))
                iso_p = "/" + "/".join(san_par) + "/" + iso_name(rel)
            else:
                iso_p = "/" + iso_name(rel)
            # гарантируем уникальность iso-имён
            if iso_p in used_iso:
                base, ext = os.path.splitext(iso_p)
                n = 2
                while f"{base}_{n}{ext}" in used_iso:
                    n += 1
                iso_p = f"{base}_{n}{ext}"
            used_iso[iso_p] = rel
            j_p = "/" + rel.replace(os.sep, "/")
            try:
                iso.add_file(local, iso_path=iso_p, joliet_path=j_p, udf_path=j_p)
            except Exception:
                print(f"[!] FAIL на файле: {rel} -> {iso_p}")
                raise
            count += 1
    print(f"[x] файлов добавлено: {count}")

    # --- El Torito: BIOS (etfsboot.com, load seg 2000h, 8x512) + UEFI (efisys.bin) ---
    etfs_size = os.path.getsize(os.path.join(MEDIA, "boot", "etfsboot.com"))
    assert etfs_size == 4096, f"etfsboot.com неожиданный размер {etfs_size}"
    iso.add_eltorito("/BOOT/ETFSBOOT.COM", bootcatfile="/BOOT.CAT", boot_load_size=8,
                     boot_load_seg=0x2000, media_name="noemul", boot_info_table=False)
    efisys = os.path.join(MEDIA, "efi", "microsoft", "boot", "efisys.bin")
    efisys_size = os.path.getsize(efisys)
    efi_sectors = math.ceil(efisys_size / 512)
    iso.add_eltorito("/EFI/MICROSOFT/BOOT/EFISYS.BIN", bootcatfile="/BOOT.CAT", efi=True,
                     boot_load_size=efi_sectors, media_name="noemul", boot_info_table=False)
    print(f"[x] El Torito: BIOS etfsboot ({etfs_size} B, seg 0x2000) + UEFI efisys ({efisys_size} B, {efi_sectors}x512)")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)
    iso.write(OUT)
    sz = os.path.getsize(OUT)
    print(f"[x] ISO собран: {OUT} ({sz/1024/1024:.1f} MiB)")

if __name__ == "__main__":
    main()
