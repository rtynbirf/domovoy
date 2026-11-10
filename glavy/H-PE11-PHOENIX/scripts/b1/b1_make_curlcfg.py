#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# B1: генерация curl-конфига из свежего aria2-листа (без MSU) + sha1-манифест
import os

SRC = '/home/z/my-project/b1/aria2_pro_fresh.txt'
DLDIR = '/home/z/my-project/b1/uup_files'
CFG = '/home/z/my-project/b1/curl_cfg.txt'
SHA = '/home/z/my-project/b1/uup_sha1.txt'
SKIP = ('Windows11.0-KB5127936-x64.msu', 'Windows11.0-KB5043080-x64.msu')  # MSU: AddUpdates=0, не нужны

entries = []
with open(SRC) as f:
    block = {}
    for line in f:
        line = line.rstrip('\n')
        if not line.strip():
            if block: entries.append(block); block = {}
            continue
        if line.startswith('http'):
            block['url'] = line
        elif line.strip().startswith('out='):
            block['name'] = line.strip()[4:]
        elif line.strip().startswith('checksum=sha-1='):
            block['sha1'] = line.strip().split('=', 2)[-1]
    if block: entries.append(block)

os.makedirs(DLDIR, exist_ok=True)
n_cfg = 0
tot = 0
with open(CFG, 'w') as fc, open(SHA, 'w') as fs:
    for e in entries:
        name = e.get('name', '')
        if not name or not e.get('url'): continue
        if name in SKIP:
            print('SKIP (MSU):', name)
            continue
        fc.write(f'url = "{e["url"]}"\noutput = "{name}"\n\n')
        fs.write(f'{e["sha1"]}  {name}\n')
        n_cfg += 1
print(f'curl cfg: {n_cfg} файлов -> {CFG}')
