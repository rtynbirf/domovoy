#!/usr/bin/env python3
# H-PE11 // UDF EXTRACTOR: pycdlib + HTTP-range RemoteFile -> точечное извлечение из 8.15 ГиБ ISO
import os, struct, sys, requests

ISO_URL = open("/home/z/my-project/build/hpe11v12/base/iso_url.txt").readline().strip()
OUT = "/home/z/my-project/build/hpe11v12/base/extract"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

class RemoteFile:
    """seek/read поверх HTTP Range (одна активная window)."""
    def __init__(self, url, window=4 << 20):
        self.url, self.win = url, window
        r = requests.head(url, headers=UA, timeout=60, allow_redirects=True)
        self.size = int(r.headers.get("Content-Length", 0))
        self.pos = 0
        self.buf = b""
        self.buf_off = -1
        self.fetched = 0
    def _ensure(self, start, n):
        if self.buf_off <= start and start + n <= self.buf_off + len(self.buf):
            return
        wstart = start
        wlen = max(n, self.win)
        wlen = min(wlen, self.size - wstart)
        r = requests.get(self.url, headers={**UA, "Range": f"bytes={wstart}-{wstart + wlen - 1}"}, timeout=600)
        if r.status_code not in (200, 206):
            raise RuntimeError(f"HTTP {r.status_code} @ {wstart}")
        self.buf, self.buf_off = r.content, wstart
        self.fetched += len(r.content)
    def read(self, n=-1):
        if n == -1: n = self.size - self.pos
        if n == 0: return b""
        self._ensure(self.pos, n)
        off = self.pos - self.buf_off
        data = self.buf[off:off + n]
        self.pos += len(data)
        return data
    def seek(self, off, whence=0):
        if whence == 0: self.pos = off
        elif whence == 1: self.pos += off
        elif whence == 2: self.pos = self.size + off
        return self.pos
    def tell(self): return self.pos

def main():
    os.makedirs(OUT, exist_ok=True)
    import pycdlib
    rf = RemoteFile(ISO_URL)
    print(f"[i] ISO size: {rf.size} B")
    iso = pycdlib.PyCdlib()
    iso._managing_fp = False
    iso._open_fp(rf)
    print(f"[x] pycdlib открыл ISO; has_udf={iso._has_udf}")
    # --- дерево UDF ---
    tree = []
    def rec(path, depth=0):
        if depth > 6: return
        kids = iso.list_children(udf_path=path) or []
        for entry in kids:
            name = entry.file_identifier()
            if isinstance(name, bytes):
                name = name.decode("utf-16-be", "replace")
            if name in (None, ".", "..", ""):
                continue
            isdir = entry.is_dir()
            full = path.rstrip("/") + "/" + name
            if isdir:
                rec(full, depth + 1)
            else:
                try:
                    size = entry.file_length()
                except Exception:
                    size = None
                tree.append((full, size))
    rec("/")
    print(f"[x] файлов в UDF-дереве: {len(tree)}")
    for p, s in tree[:400]:
        print(f"    {p}  {s}")
    # --- El Torito BIOS boot record (правильные оффсеты) ---
    vd = rf.seek(17 * 2048) or True
    rf.seek(17 * 2048)
    brd = rf.read(2048)
    assert brd[0] == 0 and b"EL TORITO" in brd, "нет El Torito BRD"
    cat_lba = struct.unpack_from("<I", brd, 71)[0]
    rf.seek(cat_lba * 2048)
    cat = rf.read(2048)
    ent = cat[32:64]
    assert ent[0] == 0x88, f"не bootable entry: {ent[0]:02x}"
    bios_cnt = struct.unpack_from("<H", ent, 6)[0]
    bios_lba = struct.unpack_from("<I", ent, 8)[0]
    print(f"[x] BIOS boot record: LBA {bios_lba}, {bios_cnt} x 512 B")
    rf.seek(bios_lba * 2048)
    etfs = rf.read(bios_cnt * 512)
    open(f"{OUT}/etfsboot_bootrecord.bin", "wb").write(etfs)
    print(f"[x] etfsboot_bootrecord.bin: {len(etfs)} B, magic: {etfs[:2]!r}")
    # --- целевые файлы ---
    targets = []
    for p, s in tree:
        pl = p.lower()
        if pl.startswith("/sources/boot.wim") or pl == "/bootmgr" or pl.startswith("/boot/") or pl.startswith("/efi/"):
            targets.append(p)
    print(f"[x] к извлечению: {len(targets)} файлов")
    total = 0
    for p in targets:
        rel = p.lstrip("/")
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst) or OUT, exist_ok=True)
        with open(dst, "wb") as f:
            iso.get_file_from_iso_fp(f, udf_path=p)
        sz = os.path.getsize(dst)
        total += sz
        print(f"[x] {p} -> {rel} ({sz} B)")
    print(f"\nИТОГО: {total/1024/1024:.1f} MiB, HTTP fetched: {rf.fetched/1024/1024:.1f} MiB")

if __name__ == "__main__":
    main()
