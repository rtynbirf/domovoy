#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WILLIAM B5 v2: прицельная добыча из MS Catalog (уроки v1: фильтр бьёт ATI-мусор,
титулы WU короткие). Прицел:
  igpu  — "9.17.10.4459" (WU-драйвер Intel HD 2000/3000 Sandy Bridge, Display)
  lan   — UID 8ac1152f-b170-4655-a7ae-2a42736664b2 (Realtek RTL8168/8111, cab 2009, 0.22MB)
  mei   — "11.0.5.1189" (Intel MEI interface, поддерживает 6-series DEV_1C3A)
"""
import re, json, os
import requests

OUT = "/home/z/my-project/build/william_drivers/cabs"
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"}
BASE = "https://www.catalog.update.microsoft.com"

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

def fetch_cab(key, uid, title, cap):
    links = catalog_links(uid)
    if not links:
        print(f"[--] {key}: нет cab-ссылок у {uid}"); return None
    url = links[0]
    dst = os.path.join(OUT, key + ".cab")
    print(f"[i] {key}: '{title[:80]}'\n    {url[:110]}")
    r = requests.get(url, headers=UA, timeout=900, stream=True)
    with open(dst, "wb") as f:
        for chunk in r.iter_content(1 << 20):
            f.write(chunk)
    sz = os.path.getsize(dst); head = open(dst, "rb").read(4)
    if head != b"MSCF" or sz > cap:
        print(f"[--] {key}: невалиден ({sz} B head={head!r})"); os.remove(dst); return None
    print(f"[x] {key}: {sz/1e6:.2f} МБ")
    return {"key": key, "uid": uid, "title": title, "url": url, "size": sz, "file": dst}

def main():
    got = {}
    # 1) iGPU SNB: запрос по точной версии
    res = catalog_search("9.17.10.4459")
    print(f"[i] запрос '9.17.10.4459': {len(res)} результатов")
    for u, t in res[:20]: print("      ", u[:8], t[:85])
    # Display-титулы Intel, x64, НЕ ATI
    cand = [(u, t) for u, t in res if re.search(r"Intel Corporation - Display", t) and not re.search(r"ATI|AMD|Mobile", t)]
    if cand:
        # среди них ищем 64-битный (титул обычно одинаковый; берём последний)
        u, t = cand[-1]
        r = fetch_cab("01_gpu_intel_hd2000_9.17.10.4459", u, t, 250_000_000)
        if r: got["gpu"] = r
    else:
        print("[--] igpu: нет Intel Corporation - Display в результатах")
    # 2) LAN: прицельный UID
    r = fetch_cab("04_lan_realtek_rtl8168_8111", "8ac1152f-b170-4655-a7ae-2a42736664b2",
                  "Realtek RTL8168/8111 PCI-E Gigabit Ethernet NIC", 30_000_000)
    if r: got["lan"] = r
    # 3) MEI: запрос по версии 11.0.5.1189
    res = catalog_search("11.0.5.1189")
    print(f"[i] запрос '11.0.5.1189': {len(res)} результатов")
    for u, t in res[:20]: print("      ", u[:8], t[:85])
    cand = [(u, t) for u, t in res if re.search(r"Management Engine Interface", t) and not re.search(r"Kaby|Coffee|Tiger|Alder|Raptor|Whiskey|Comet|Rocket|8th|7th|9th|10th|11th", t)]
    if cand:
        u, t = cand[-1]
        r = fetch_cab("03_mei_intel_11.0.5.1189", u, t, 30_000_000)
        if r: got["mei"] = r
    else:
        print("[--] mei: нет Management Engine Interface в результатах")
    with open("/home/z/my-project/build/william_drivers/catalog_report2.json", "w") as f:
        json.dump(got, f, indent=1, ensure_ascii=False)
    print("\n=== TARGETED DONE ===")
    for k, v in got.items(): print(f"  [x] {k}: {v['size']/1e6:.2f} МБ '{v['title'][:60]}'")

if __name__ == "__main__":
    main()
