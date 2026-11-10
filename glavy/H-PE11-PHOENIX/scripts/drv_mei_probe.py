#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# B5: скачать все 5 MEI-кабов 11.0.5.1189, распаковать, найти INF с PCI\VEN_8086&DEV_1C3A (6-series HECI)
import re, json, os, subprocess
import requests

OUT = "/home/z/my-project/build/william_drivers/cabs"
MEI_DIR = "/home/z/my-project/build/william_drivers/mei_probe"
os.makedirs(MEI_DIR, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"}
BASE = "https://www.catalog.update.microsoft.com"
UIDS = ["79c6319a", "41fb2cec", "f33a47b6", "48d5ce2f", "c637923a"]
CABEXTRACT = "/home/z/my-project/b1/tools/prefix/usr/bin/cabextract"

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
    return list(dict.fromkeys(re.findall(r"https://[^\s'\"<>]+?\.cab", r.text)))

def main():
    # полный uid по префиксу
    res = catalog_search("11.0.5.1189")
    full = {u[:8]: u for u, t in res}
    results = {}
    for pfx in UIDS:
        uid = full.get(pfx)
        if not uid: print(f"[--] {pfx}: uid не найден"); continue
        links = catalog_links(uid)
        if not links: print(f"[--] {pfx}: нет ссылок"); continue
        dst = os.path.join(OUT, f"mei_{pfx}.cab")
        r = requests.get(links[0], headers=UA, timeout=600, stream=True)
        with open(dst, "wb") as f:
            for c in r.iter_content(1 << 20): f.write(c)
        sz = os.path.getsize(dst)
        print(f"[x] {pfx}: {sz/1e6:.2f} МБ {links[0][:80]}")
        # распаковка + поиск DEV_1C3A
        xdir = os.path.join(MEI_DIR, pfx)
        os.makedirs(xdir, exist_ok=True)
        subprocess.run([CABEXTRACT, "-q", "-d", xdir, dst], check=False)
        hits = []
        for root, _, files in os.walk(xdir):
            for fn in files:
                if fn.lower().endswith(".inf"):
                    txt = open(os.path.join(root, fn), "rb").read().decode("latin1", errors="replace")
                    if "1C3A" in txt.upper():
                        hits.append(fn)
        results[pfx] = {"size": sz, "inf_1c3a_hits": hits}
        print(f"    DEV_1C3A: {hits if hits else 'НЕТ'}")
    with open("/home/z/my-project/build/william_drivers/mei_probe_result.json", "w") as f:
        json.dump(results, f, indent=1)
    print("\n=== MEI PROBE DONE ===")
    for p, v in results.items():
        if v["inf_1c3a_hits"]: print(f"  [x] {p}: ПОДДЕРЖИВАЕТ 6-series HECI -> {v['inf_1c3a_hits']}")

if __name__ == "__main__":
    main()
