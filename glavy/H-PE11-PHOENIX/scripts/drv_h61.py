#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WILLIAM B5: добытчик драйверов стенда 6ORMAN (Asus P8H61-I + i3-2120) из Microsoft Update Catalog.
Паттерн drv_catalog.py (проверен на Apollo Lake). Whitelist H61:
  igpu_snb  — Intel HD Graphics 2000 (SNB) 9.17.10.x (WU-ветка для Win10/11)
  chipset   — Intel 6 Series/C200 Series Chipset (INF)
  me        — Intel Management Engine Interface (6-series = ME7)
  lan_rtl   — Realtek RTL8168/8111 GbE
  audio_via — VIA VT1708S HDA
Выход: /home/z/my-project/build/william_drivers/cabs/*.cab + report JSON
"""
import re, json, sys, os
import requests

OUT = "/home/z/my-project/build/william_drivers/cabs"
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"}
BASE = "https://www.catalog.update.microsoft.com"

# (ключ, поисковая строка, лимит размера cab, фильтр-заголовка regex или None)
# igpu: по девайс-именам SNB; WU-титулы вида "Intel Corporation - Display - Intel(R) HD Graphics 2000"
QUERIES = [
    ("igpu_snb",  "Intel(R) HD Graphics 2000",                  250_000_000, r"HD Graphics 2000|HD Graphics"),
    ("igpu_snb2", "Intel(R) 2nd Generation Core Processor",     250_000_000, r"2nd Generation"),
    ("chipset",   "6 Series/C200 Series Chipset Family",        30_000_000,  r"6 Series/C200"),
    ("me",        "Intel(R) Management Engine Interface",       30_000_000,  r"Management Engine"),
    ("lan_rtl",   "Realtek RTL8168",                            30_000_000,  r"RTL8168|8111"),
    ("audio_via", "VIA VT1708S",                                30_000_000,  r"VT1708S"),
]
MIN_CAB = 40_000  # INF-кабы бывают 50-70 КБ (LPC и пр.) — это валидно

def catalog_search(q):
    r = requests.get(f"{BASE}/Search.aspx", params={"q": q}, headers=UA, timeout=60)
    rows = re.findall(r"onclick='goToDetails\(\"([0-9a-f-]{36})\"\);'", r.text)
    out = []
    for uid in rows:
        m = re.search(r"id='%s_link'[^>]*>\s*(.*?)</a>" % uid, r.text, re.S)
        title = re.sub(r"<[^>]+>", "", m.group(1)).strip() if m else ""
        out.append((uid, title))
    return out

def catalog_links(uid):
    body = json.dumps([{"size": 0, "updateID": uid, "uidInfo": uid}], separators=(",", ":"))
    r = requests.post(f"{BASE}/DownloadDialog.aspx",
                      headers={**UA, "Content-Type": "application/x-www-form-urlencoded"},
                      data="updateIDs=" + body, timeout=60)
    urls = re.findall(r"https://[^\s'\"<>]+?\.cab", r.text)
    return list(dict.fromkeys(urls))

def pick(entries, title_re):
    # выбираем лучший: фильтр по заголовку; среди подходящих берём последний (обычно свежая версия)
    ok = [(u, t) for u, t in entries if re.search(title_re, t)]
    return ok[-1] if ok else None

def titles_dump(entries, n=15):
    return [f"{u[:8]} {t[:80]}" for u, t in entries[:n]]

def main():
    report = {}
    for key, q, cap, tre in QUERIES:
        try:
            res = catalog_search(q)
        except Exception as e:
            report[key] = {"status": "search_error", "err": str(e)}; print(f"[--] {key}: search error {e}"); continue
        if not res:
            report[key] = {"status": "no_results", "query": q}; print(f"[--] {key}: пусто по '{q}'"); continue
        sel = pick(res, tre)
        if not sel:
            report[key] = {"status": "no_title_match", "titles": titles_dump(res)}
            print(f"[--] {key}: {len(res)} результатов, но фильтр '{tre}' не сработал:")
            for t in titles_dump(res): print("      ", t)
            continue
        uid, title = sel
        print(f"[i] {key}: выбрано '{title[:90]}' ({uid})")
        try:
            links = catalog_links(uid)
        except Exception as e:
            report[key] = {"status": "links_error", "err": str(e)}; continue
        if not links:
            report[key] = {"status": "no_cab_links", "title": title}; continue
        url = links[0]
        dst = os.path.join(OUT, key + ".cab")
        print(f"    cab: {url[:120]}")
        r = requests.get(url, headers=UA, timeout=900, stream=True)
        size = int(r.headers.get("Content-Length", 0))
        if size > cap:
            report[key] = {"status": "too_big", "size": size}; print(f"[--] {key}: {size/1e6:.0f} МБ > лимита"); r.close(); continue
        with open(dst, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
        sz = os.path.getsize(dst)
        head4 = open(dst, "rb").read(4)
        if sz < MIN_CAB or head4 != b"MSCF":
            report[key] = {"status": "invalid_cab", "size": sz, "head": head4[:4].decode('latin1')}
            print(f"[--] {key}: cab невалиден ({sz} B, head={head4!r})"); os.remove(dst); continue
        report[key] = {"status": "ok", "title": title, "uid": uid, "url": url, "size": sz,
                       "file": dst}
        print(f"[x] {key}: {sz/1e6:.2f} МБ")
    with open("/home/z/my-project/build/william_drivers/catalog_report.json", "w") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print("\n=== CATALOG H61 DONE ===")
    for k, v in report.items():
        print(f"  {k}: {v.get('status')} {v.get('title','')[:60]} {v.get('size',0)/1e6:.1f}MB" if isinstance(v, dict) and 'title' in v else f"  {k}: {v.get('status')}")

if __name__ == "__main__":
    main()
