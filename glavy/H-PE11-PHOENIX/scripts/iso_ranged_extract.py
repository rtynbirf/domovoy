#!/usr/bin/env python3
# H-PE11 // ISO RANGED EXTRACTOR: парсинг ISO9660+Joliet+El Torito по HTTP-диапазонам
# Точечно качает только нужные файлы (boot.wim + скаффолд) из 8.15 ГиБ ISO.
import struct, sys, os, subprocess
import requests

ISO_URL = open("/home/z/my-project/build/hpe11v12/base/iso_url.txt").readline().strip()
OUT = "/home/z/my-project/build/hpe11v12/base/extract"
SECT = 2048
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

def rread(start, length):
    # range download -> bytes
    end = start + length - 1
    r = requests.get(ISO_URL, headers={**UA, "Range": f"bytes={start}-{end}"}, timeout=300)
    if r.status_code not in (200, 206) or len(r.content) != length:
        raise RuntimeError(f"range {start}-{end}: HTTP {r.status_code} len {len(r.content)}")
    return r.content

def dir_record(buf, off):
    ln = buf[off]
    if ln == 0: return None
    rec = {
        "len": ln,
        "extent": struct.unpack_from("<I", buf, off + 2)[0],
        "size": struct.unpack_from("<I", buf, off + 10)[0],
        "flags": buf[off + 25],
        "name_raw": buf[off + 33: off + 33 + buf[off + 32]],
    }
    return rec

def name_of(rec, joliet):
    raw = rec["name_raw"].decode("utf-16_be" if joliet else "ascii", errors="replace")
    raw = raw.split(";")[0]
    return raw

def read_dir(extent, size, joliet):
    # read full dir extent(s), return records
    data = rread(extent * SECT, size)
    recs, off = [], 0
    while off < size:
        if data[off] == 0:
            off = ((off // SECT) + 1) * SECT
            if off >= size: break
            continue
        rec = dir_record(data, off)
        off += rec["len"]
        recs.append(rec)
    return recs

def walk(root_rec, joliet, prefix="", files=None, depth=0):
    if files is None: files = {}
    if depth > 6: return files
    for rec in read_dir(root_rec["extent"], root_rec["size"], joliet):
        nm = name_of(rec, joliet)
        if nm in ("\x00", ".", "..", ""): continue
        path = f"{prefix}/{nm}"
        if rec["flags"] & 2:
            walk(rec, joliet, path, files, depth + 1)
        else:
            files[path] = (rec["extent"], rec["size"])
    return files

def main():
    os.makedirs(OUT, exist_ok=True)
    # --- Volume descriptors (sector 16..20) ---
    vd = rread(16 * SECT, 5 * SECT)
    pvd_off = 0  # sector 16
    assert vd[0] == 1, "нет PVD"
    # Boot record descriptor (EL TORITO) — ищем в 17..20
    boot_cat_lba = None
    joliet_root = None
    pvd_root = None
    for i in range(5):
        s = vd[i * SECT:(i + 1) * SECT]
        t = s[0]
        if t == 0 and s[7:27] == b"EL TORITO SPECIFICATION"[0:20] or (t == 0 and b"EL TORITO" in s):
            boot_cat_lba = struct.unpack_from("<I", s, 71)[0]
        if t == 2 and b"%/@" in s[88:120]:
            joliet_root = dir_record(s, 156)
        if t == 1:
            pvd_root = dir_record(s, 156)
    if joliet_root is None:
        print("[!] Joliet SVD не найден — использую ISO9660 root")
        joliet_root = pvd_root
    print(f"[x] boot catalog LBA: {boot_cat_lba}, root: {joliet_root['extent']}")
    # --- Дерево файлов ---
    files = walk(joliet_root, True)
    print(f"[x] файлов в ISO: {len(files)}")
    # --- El Torito catalog ---
    cat = rread(boot_cat_lba * SECT, SECT)
    # default entry: offset 32; boot LBA @12 (LE32), sector count @10 (LE16, 512B units)
    bios_lba = struct.unpack_from("<I", cat, 32 + 12)[0]
    bios_cnt = struct.unpack_from("<H", cat, 32 + 10)[0]
    print(f"[x] BIOS boot record: LBA {bios_lba}, {bios_cnt}x512 B")
    etfs = rread(bios_lba * SECT, bios_cnt * 512)
    open(f"{OUT}/etfsboot_bootrecord.bin", "wb").write(etfs)
    # --- Качаем нужное ---
    want_prefixes = ("/sources/boot.wim", "/bootmgr", "/boot/", "/efi/")
    total = 0
    for path, (extent, size) in sorted(files.items()):
        if not any(path == p.rstrip("/") or path.startswith(p) for p in want_prefixes):
            continue
        if "/efi/microsoft/boot/" in path and path.endswith(".log"): continue
        if size == 0: continue
        rel = path.lstrip("/")
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if size < 100 * 1024 * 1024:
            data = rread(extent * SECT, size)
            open(dst, "wb").write(data)
            total += size
            print(f"[x] {path} ({size} B)")
        else:
            # крупный файл — curl с resume
            cmd = ["curl", "-sL", "--retry", "6", "--retry-delay", "3", "-r",
                   f"{extent * SECT}-{extent * SECT + size - 1}", "-o", dst, ISO_URL]
            subprocess.run(cmd, check=True)
            got = os.path.getsize(dst)
            total += got
            print(f"[x] {path} ({got} B) [curl]")
    print(f"\nИТОГО скачано: {total/1024/1024:.1f} MiB -> {OUT}")
    # список для контроля
    for root, _, fs in os.walk(OUT):
        for f in fs:
            p = os.path.join(root, f)
            print(f"  {os.path.relpath(p, OUT)}  {os.path.getsize(p)}")

if __name__ == "__main__":
    main()
