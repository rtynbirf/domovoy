#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Бенчмарк: агрегатная скорость параллельного POST'а блобов в GitHub (N потоков x 8MB)
import base64, hashlib, json, os, sys, time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
API = 'https://api.github.com/repos/rtynbirf/H-PE11-PHOENIX'
N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
SZ = 8 * 2**20

def post(i):
    data = bytes([i]) * SZ
    body = json.dumps({'content': base64.b64encode(data).decode(), 'encoding': 'base64'}).encode()
    r = urllib.request.Request(f'{API}/git/blobs', data=body, method='POST', headers={
        'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json', 'User-Agent': 'phx-bench'})
    t0 = time.time()
    with urllib.request.urlopen(r, timeout=300) as resp:
        resp.read()
    return time.time() - t0

t0 = time.time()
with ThreadPoolExecutor(max_workers=N) as ex:
    dts = list(ex.map(post, range(N)))
dt = time.time() - t0
total = N * SZ
print(f'N={N}: {total/2**20:.0f} MiB за {dt:.1f}s -> {total/2**20/dt:.1f} MiB/s aggregate')
print('per-post:', [f'{d:.1f}s' for d in dts])
