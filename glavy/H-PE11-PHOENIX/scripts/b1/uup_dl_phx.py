#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PHOENIX WINDOWS 11 // загрузчик UUP-пака 26300.9711 amd64 (Core ru-RU)
Источник имён: aria2_script.txt (96 файлов). Источник URL+sha1: uup_meta.json (12296).
Исключения (экономия ~6 ГБ, AddUpdates=0/SkipEdge): LCU MSU, старый CU, Edge.wim,
WebView FOD, KB-кабы (SSU/NDP481). Плюс: ищет NetFx3 FOD в полном паке.
"""
import json, os, re, subprocess, sys, hashlib, concurrent.futures as cf

META = '/tmp/my-project/scripts/uup_meta_9807.json'
OUT = '/tmp/my-project/build/uup_work/UUPs'
os.makedirs(OUT, exist_ok=True)

import re as _re
EXCLUDE_RX = [
    r'\.msu$',                     # LCU/старые CU — AddUpdates=0
    r'^Windows11\.0-KB',           # SSU/NDP — in-box
    r'^Edge\.wim$',                # SkipEdge
    r'Edge-WebView',               # WebView FOD
    r'Hello-Face',                 # биометрия-балласт
    r'^professional_',             # вторая редакция (fallback при нехватке блобов)
    r'EditionPack-Professional',
]

def sha1(path):
    h = hashlib.sha1()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 22), b''):
            h.update(chunk)
    return h.hexdigest()

def fetch(task):
    name, url, want = task
    dest = os.path.join(OUT, name)
    if os.path.exists(dest):
        sz = os.path.getsize(dest)
        if sz > 0:
            return name, 'EXISTS', sz
    for attempt in range(4):
        r = subprocess.run(['curl', '-sSL', '--fail', '--retry', '2',
                            '--connect-timeout', '25', '--max-time', '1800',
                            '-o', dest + '.part', url],
                           capture_output=True)
        if r.returncode == 0 and os.path.exists(dest + '.part'):
            os.replace(dest + '.part', dest)
            got = sha1(dest)
            if got == want:
                return name, 'OK', os.path.getsize(dest)
            return name, 'SHA1_MISMATCH', got
        # частичная докачка curl -C - на следующей попытке
        for a in range(2):
            r = subprocess.run(['curl', '-sSL', '--fail', '--retry', '2', '-C', '-',
                                '--connect-timeout', '25', '--max-time', '1800',
                                '-o', dest + '.part', url], capture_output=True)
            if r.returncode == 0 and os.path.exists(dest + '.part') and os.path.getsize(dest + '.part') > 0:
                os.replace(dest + '.part', dest)
                got = sha1(dest)
                if got == want:
                    return name, 'OK', os.path.getsize(dest)
                return name, 'SHA1_MISMATCH', got
    return name, 'FAIL', 0

def main():
    meta = json.load(open(META))
    files = meta['response']['files']
    netfx = [n for n in files if 'netfx' in n.lower() and int(files[n].get('size', 0)) > 0]
    print('[i] NetFx3 в паке:', [(n, int(files[n]['size']) // 1048576) for n in netfx[:4]] or 'НЕТ')
    tasks = []
    total = 0
    skipped = []
    for n, v in files.items():
        if any(_re.search(rx, n) for rx in EXCLUDE_RX):
            skipped.append(n); continue
        sz = int(v.get('size', 0))
        if sz <= 0:
            continue  # пустые/не-файловые записи
        tasks.append((n, v['url'], v['sha1']))
        total += sz
    print(f'[i] к закачке: {len(tasks)} файлов, {total/1e9:.2f} GB  (пропущено {len(skipped)})')
    ok = 0
    with cf.ThreadPoolExecutor(max_workers=4) as ex:
        for name, st, sz in ex.map(fetch, tasks):
            mark = '✓' if st == 'OK' else ('•' if st == 'EXISTS' else '✗')
            print(f'  {mark} {st:14s} {sz:>12,} {name}', flush=True)
            if st in ('OK', 'EXISTS', 'SHA1_MISMATCH'):
                ok += 1
    print(f'[i] готово: {ok}/{len(tasks)}')

if __name__ == '__main__':
    main()
