#!/usr/bin/env python3
# H-PE11 // Добытчик драйверов станции из Microsoft Update Catalog (timebox/sizebox)
# whitelist: iigd_dch, netwtw04, apollolakesystem, dptf_acpi/dptf_cpu/esif_manager,
#            ialpss2_spi_bxt_p, ialpss2_uart2_bxt_p, txei, rtsuer  (+ wintun уже есть)
import re, json, sys, os, subprocess, requests

OUT = "/home/z/my-project/build/hpe11v12/ammo/drivers"
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"}
BASE = "https://www.catalog.update.microsoft.com"

QUERIES = [
    ("chipset",       "Intel Serial IO", 60_000_000),
    ("iigd_dch",      "Intel Corporation - Display - 26.20", 550_000_000),
]

GOT_KEYS = {"netwtw04", "dptf", "txei", "rtsuer"}
QUERIES = [q for q in QUERIES if q[0] not in GOT_KEYS]

def catalog_search(q):
    r = requests.get(f"{BASE}/Search.aspx", params={"q": q}, headers=UA, timeout=60)
    rows = re.findall(r"onclick='goToDetails\(\"([0-9a-f-]{36})\"\);'", r.text)
    # заголовки берём по id ссылки
    out = []
    for uid in rows:
        m = re.search(r"id='%s_link'[^>]*>\s*(.*?)</a>" % uid, r.text, re.S)
        title = re.sub(r"<[^>]+>", "", m.group(1)).strip() if m else ""
        out.append((uid, title))
    return out

def catalog_links(uid):
    body = json.dumps([{"size": 0, "updateID": uid, "uidInfo": uid}], separators=(",", ":"))
    r = requests.post(f"{BASE}/DownloadDialog.aspx", headers={**UA, "Content-Type": "application/x-www-form-urlencoded"},
                      data="updateIDs=" + body, timeout=60)
    urls = re.findall(r"https://[^\s'\"<>]+?\.cab", r.text)
    return list(dict.fromkeys(urls))

def main():
    got = {}
    for key, q, cap in QUERIES:
        try:
            res = catalog_search(q)
        except Exception as e:
            print(f"[--] {key}: search error {e}"); continue
        if not res:
            print(f"[--] {key}: нет результатов по '{q}'"); continue
        # берём первый (обычно свежий) результат
        uid, title = res[0]
        print(f"[i] {key}: {len(res)} результатов; берём '{title[:70]}' ({uid})")
        try:
            links = catalog_links(uid)
        except Exception as e:
            print(f"[--] {key}: links error {e}"); continue
        if not links:
            print(f"[--] {key}: ссылок .cab нет"); continue
        url = links[0]
        dst = os.path.join(OUT, key + ".cab")
        print(f"    cab: {url[:110]}")
        r = requests.get(url, headers=UA, timeout=600, stream=True)
        size = int(r.headers.get("Content-Length", 0))
        if size > cap:
            print(f"[--] {key}: cab {size/1e6:.0f} МБ > лимита {cap/1e6:.0f} МБ — пропускаю")
            r.close(); continue
        with open(dst, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
        sz = os.path.getsize(dst)
        head4 = open(dst, "rb").read(4)
        print(f"    DBG {key}: sz={sz} head={head4!r}")
        if sz < 100_000 or head4 != b"MSCF":
            print(f"[--] {key}: cab невалиден ({sz} B)"); os.remove(dst); continue
        got[key] = (dst, sz, title)
        print(f"[x] {key}: {sz/1e6:.1f} МБ")
    print("\n=== CATALOG DONE ===")
    for k, (p, s, t) in got.items():
        print(f"  [x] {k}: {s/1e6:.1f} МБ  ({t[:60]})")
    missing = [k for k, _, _ in QUERIES if k not in got]
    for m in missing:
        print(f"  [--] {m}")

if __name__ == "__main__":
    sys.exit(main())
