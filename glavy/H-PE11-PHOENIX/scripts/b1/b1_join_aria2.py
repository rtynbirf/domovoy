#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# B1: JOIN старого pro-листа (имена+sha1) со свежим JSON edition=0 (sha1->url)
# Выход: свежий aria2-лист pro-only + таблица состава
import json, sys, re, os

SCRIPTS = '/home/z/my-project/scripts'
PRO = os.path.join(SCRIPTS, 'aria2_pro.txt')
ED0 = os.path.join(SCRIPTS, 'get_ed0.json')
OUT = '/home/z/my-project/b1/aria2_pro_fresh.txt'
TBL = '/home/z/my-project/b1/pro_composition.tsv'

# 1) парс старого pro-листа: блоки url/out/checksum
entries = []
with open(PRO, 'r', encoding='utf-8') as f:
    block = {}
    for line in f:
        line = line.rstrip('\n')
        if not line.strip():
            if block: entries.append(block); block = {}
            continue
        if line.startswith('http'):
            block['url_old'] = line
        elif line.strip().startswith('out='):
            block['name'] = line.strip()[4:]
        elif line.strip().startswith('checksum=sha-1='):
            block['sha1'] = line.strip().split('=', 2)[-1]
    if block: entries.append(block)

print(f'pro entries: {len(entries)}')

# 2) sha1 -> url из свежего JSON
j = json.load(open(ED0))
r = j['response']
print('updateName:', r.get('updateName'))
files = r['files']
sha1_to_url = {}
dups = 0
for k, v in files.items():
    s = v.get('sha1', '')
    u = v.get('url', '')
    if not s or not u: continue
    if s in sha1_to_url and sha1_to_url[s] != u:
        dups += 1
    sha1_to_url[s] = u
print(f'json files: {len(files)}, unique sha1 urls: {len(sha1_to_url)}, dup sha1: {dups}')

# size по sha1 тоже
sha1_to_size = {}
for k, v in files.items():
    s = v.get('sha1', '')
    if s and s not in sha1_to_size:
        try: sha1_to_size[s] = int(v.get('size', 0) or 0)
        except: sha1_to_size[s] = 0

# 3) JOIN
rows = []
miss = 0
for e in entries:
    name = e.get('name', '')
    sha1 = e.get('sha1', '')
    url_new = sha1_to_url.get(sha1)
    size = sha1_to_size.get(sha1, 0)
    if url_new:
        rows.append((name, size, sha1, url_new, 'fresh'))
    else:
        miss += 1
        rows.append((name, size, sha1, e.get('url_old', ''), 'OLD-URL'))

print(f'matched fresh: {len(rows)-miss}, miss (old url fallback): {miss}')

# 4) свежий aria2-лист
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8') as f:
    for name, size, sha1, url, src in rows:
        f.write(url + '\n')
        f.write(f'  out={name}\n')
        f.write(f'  checksum=sha-1={sha1}\n\n')

# 5) таблица состава
tot = 0
with open(TBL, 'w', encoding='utf-8') as f:
    for name, size, sha1, url, src in sorted(rows, key=lambda x: -x[1]):
        tot += size
        f.write(f'{size}\t{src}\t{name}\n')
print(f'total size: {tot/2**30:.2f} GiB ({tot/2**20:.0f} MiB)')
big = [x for x in rows if x[1] > 100*2**20]
print('files >100MiB:')
for name, size, sha1, url, src in sorted(big, key=lambda x: -x[1]):
    print(f'  {size/2**20:8.1f} MiB  {name}')
