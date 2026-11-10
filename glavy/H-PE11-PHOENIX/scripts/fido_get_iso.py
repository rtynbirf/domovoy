#!/usr/bin/env python3
# H-PE11 // FIDO-клиент: получение официальной ссылки Microsoft на Win11 26H2 ru-RU x64 ISO
# Репликация Fido.ps1 (pbatard): vlscppe tag -> ov-df -> SKU -> links
import re, sys, time, uuid, json
import requests

ORG_ID = "y6jn8c31"
PROFILE_ID = "606624d44113"
INSTANCE_ID = "560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"
REF = "https://www.microsoft.com/software-download/windows11"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

EDITIONS = [3813, 3816]  # Win11 26H2 Home/Pro/Edu (x64+x86 | ARM64)
LANG_WANT = "russian"
ARCH_WANT = 1  # x64

def log(m): print(m, flush=True)

def main():
    s = requests.Session()
    s.headers.update({"User-Agent": UA})
    results = []
    for edition_id in EDITIONS:
        sid = str(uuid.uuid4())
        log(f"[i] edition {edition_id} session {sid}")

        # 1) vlscppe tag (whitelist session)
        r = s.get("https://vlscppe.microsoft.com/tags",
                  params={"org_id": ORG_ID, "session_id": sid}, timeout=30, allow_redirects=False)
        log(f"    vlscppe: {r.status_code}")

        # 2) mdt.js -> w, rticks
        r = s.get("https://ov-df.microsoft.com/mdt.js",
                  params={"instanceId": INSTANCE_ID, "PageId": "si", "session_id": sid}, timeout=30)
        m_w = re.search(r'[?&]w=([A-F0-9]+)', r.text)
        m_r = re.search(r'rticks\=\"\+?(\d+)', r.text)
        if not (m_w and m_r):
            log(f"[!] ov-df mdt.js parse fail: {r.status_code} {r.text[:200]!r}")
            return 1
        w, rticks = m_w.group(1), m_r.group(1)
        log(f"    mdt.js: w={w[:8]}... rticks={rticks}")

        # 3) ov-df reply
        r = s.get("https://ov-df.microsoft.com/",
                  params={"session_id": sid, "CustomerId": INSTANCE_ID, "PageId": "si",
                          "w": w, "mdt": str(int(time.time() * 1000)), "rticks": rticks},
                  timeout=30, allow_redirects=False)
        log(f"    ov-df reply: {r.status_code}")

        # 4) SKU info
        for attempt in range(3):
            r = s.get("https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition",
                      params={"profile": PROFILE_ID, "productEditionId": edition_id, "SKU": "undefined",
                              "friendlyFileName": "undefined", "Locale": "en-US", "sessionID": sid},
                      timeout=60)
            try:
                data = r.json()
            except Exception:
                log(f"    sku api: HTTP {r.status_code} non-json: {r.text[:150]!r}"); time.sleep(3); continue
            if data.get("Errors"):
                log(f"    sku api errors: {data['Errors']}"); time.sleep(3); continue
            break
        else:
            log("[!] sku api failed"); return 1
        skus = data.get("Skus", [])
        log(f"    skus: {len(skus)}; languages: {sorted(set(x.get('Language','') for x in skus))[:8]}")
        ru = [x for x in skus if x.get("Language", "").lower() == LANG_WANT]
        if not ru:
            log(f"[!] язык '{LANG_WANT}' не найден"); return 1
        for sku in ru:
            sku_id = sku["Id"]
            # 5) download links (Referer обязателен)
            r = s.get("https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku",
                      params={"profile": PROFILE_ID, "productEditionId": "undefined", "SKU": sku_id,
                              "friendlyFileName": "undefined", "Locale": "en-US", "sessionID": sid},
                      headers={"Referer": REF}, timeout=60)
            try:
                d2 = r.json()
            except Exception:
                log(f"    links api HTTP {r.status_code}: {r.text[:150]!r}"); continue
            if d2.get("Errors"):
                log(f"    links errors: {d2['Errors']}"); continue
            for opt in d2.get("ProductDownloadOptions", []):
                results.append({"edition": edition_id, "sku": sku_id, "arch": opt.get("DownloadType"),
                                "uri": opt.get("Uri"), "name": opt.get("FriendlyFileName", "")})
    if not results:
        log("[!] ссылок нет"); return 1
    for x in results:
        log(f"[link] arch={x['arch']} sku={x['sku']} {x['name']}\n       {x['uri']}")
    pick = next((x for x in results if x["arch"] == ARCH_WANT), None)
    if not pick:
        log("[!] x64 не найден"); return 1
    with open("/home/z/my-project/build/hpe11v12/base/iso_url.txt", "w") as f:
        f.write(pick["uri"] + "\n" + (pick["name"] or "Win11.iso") + "\n")
    log(f"\nX64_URL_SAVED: {pick['uri'][:120]}...")
    return 0

if __name__ == "__main__":
    sys.exit(main())
