#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# B1 monitor: ждёт свежие URL (P1 > now+600), затем докачивает недостающие файлы.
import json, re, subprocess, time, os, sys

ID = '687d1ced-aab1-4cd5-ad05-705189769731'
SCRIPTS = '/home/z/my-project/scripts'
DL = '/home/z/my-project/b1/uup_files'
SHA = '/home/z/my-project/b1/uup_sha1.txt'
CFG = '/home/z/my-project/b1/curl_cfg.txt'

def fresh_urls():
    r = subprocess.run(['curl', '-s', f'https://api.uupdump.net/get.php?id={ID}&pack=ru-ru&edition=0'],
                       capture_output=True, timeout=120)
    j = json.loads(r.stdout)
    files = j.get('response', {}).get('files', {})
    if not files:
        return None
    return files

def p1_max(files):
    mx = 0
    for v in files.values():
        u = v.get('url', '')
        m = re.search(r'P1=(\d+)', u)
        if m:
            mx = max(mx, int(m.group(1)))
    return mx

# парс старого pro-листа (имена+sha1)
entries = []
block = {}
for line in open('/home/z/my-project/b1/aria2_pro_fresh.txt'):
    line = line.rstrip('\n')
    if not line.strip():
        if block: entries.append(block); block = {}
        continue
    if line.startswith('http'): block['url_old'] = line
    elif line.strip().startswith('out='): block['name'] = line.strip()[4:]
    elif line.strip().startswith('checksum=sha-1='): block['sha1'] = line.strip().split('=', 2)[-1]
if block: entries.append(block)

while True:
    files = fresh_urls()
    if files is None:
        print('API пуст, ждём 180с', flush=True); time.sleep(180); continue
    mx = p1_max(files)
    now = time.time()
    print(f'P1max={mx} ({time.strftime("%H:%M:%S", time.gmtime(mx))} UTC) now={time.strftime("%H:%M:%S", time.gmtime(now))} UTC', flush=True)
    if mx > now + 600:
        sha1_to_url = {v.get('sha1', ''): v.get('url', '') for v in files.values() if v.get('url')}
        with open(CFG, 'w') as fc:
            for e in entries:
                name, sha1 = e.get('name', ''), e.get('sha1', '')
                if not name or name in ('Windows11.0-KB5127936-x64.msu', 'Windows11.0-KB5043080-x64.msu'):
                    continue
                u = sha1_to_url.get(sha1)
                if not u:
                    print('НЕТ URL для', name, flush=True); continue
                fc.write(f'url = "{u}"\noutput = "{name}"\n\n')
        print('Свежий лист готов -> ' + CFG, flush=True)
        break
    time.sleep(240)
print('MONITOR_DONE', flush=True)
