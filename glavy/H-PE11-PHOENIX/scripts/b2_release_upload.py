#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Заливка WILLIAM_v2.ISO в Release 423108931 ассетами ~920MiB (resume: скип существующих).
import json, os, hashlib, subprocess, sys
import urllib.request, urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
REL = 423108931
API = f'https://api.github.com/repos/rtynbirf/H-PE11-PHOENIX/releases/{REL}'
UP = f'https://uploads.github.com/repos/rtynbirf/H-PE11-PHOENIX/releases/{REL}/assets?name='
ISO = '/home/z/my-project/b1/work/WILLIAM_v2.ISO'
ADIR = '/home/z/my-project/b1/asset'
os.makedirs(ADIR, exist_ok=True)
N = 5

def api(url, method='GET', body=None, ct='application/json'):
    data = json.dumps(body).encode() if isinstance(body, dict) else body
    r = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
        'Content-Type': ct, 'User-Agent': 'phx-rel'})
    try:
        with urllib.request.urlopen(r, timeout=600) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try: return e.code, json.loads(e.read())
        except Exception: return e.code, {}

def upload(path, name):
    size = os.path.getsize(path)
    # curl с octet-stream (urllib с большими телами капризен).
    # AUDIT-2026-1030 / EXTRA: токен подаётся через '-K -' (config из stdin),
    # чтобы Authorization-заголовок не светился в argv/process listing.
    r = subprocess.run(['curl', '-sS', '-X', 'POST',
        '-K', '-',
        '-H', 'Content-Type: application/octet-stream',
        '--data-binary', f'@{path}', f'{UP}{name}',
        '-w', '%{http_code}', '-o', f'{ADIR}/resp.json'],
        input=f'header = "Authorization: Bearer {TOKEN}"\n',
        capture_output=True, text=True, timeout=900)
    return r.stdout.strip()

def main():
    size = os.path.getsize(ISO)
    base = (size + N - 1) // N
    st, assets = api(f'{API}/assets')
    uploaded = {a['name'] for a in assets} if st == 200 else set()
    print(f'SIZE={size} BASE={base} uploaded={sorted(uploaded)}')
    sums = []
    for k in range(N):
        name = f'iso.v2.part{k:02d}.iso'
        skip, cnt = k * base, min(base, size - k * base)
        if cnt <= 0: break
        afile = f'{ADIR}/{name}'
        h = hashlib.sha256()
        if not os.path.exists(afile) or os.path.getsize(afile) != cnt:
            with open(ISO, 'rb') as src, open(afile, 'wb') as dst:
                src.seek(skip); left = cnt
                while left > 0:
                    b = src.read(min(1 << 22, left))
                    dst.write(b); h.update(b); left -= len(b)
        else:
            with open(afile, 'rb') as f:
                for b in iter(lambda: f.read(1 << 22), b''): h.update(b)
        sha = h.hexdigest()
        sums.append(f'{sha}  {name}')
        print(f'[{k}] {name}: {cnt} B sha256={sha[:16]}...')
        if name in uploaded:
            print('    SKIP (уже залит)'); continue
        code = upload(afile, name)
        print(f'    upload HTTP={code}')
        if code != '201':
            print('    RESP:', open(f'{ADIR}/resp.json').read()[:300]); sys.exit(1)
        os.remove(afile)
    with open(f'{ADIR}/SHA256SUMS_ISO_v2.txt', 'w') as f:
        f.write('\n'.join(sums) + '\n')
    code = upload(f'{ADIR}/SHA256SUMS_ISO_v2.txt', 'SHA256SUMS_ISO_v2.txt')
    print(f'SHA256SUMS upload HTTP={code}')
    fh = hashlib.sha256()
    with open(ISO, 'rb') as f:
        for b in iter(lambda: f.read(1 << 24), b''): fh.update(b)
    print(f'TOTAL_SHA256={fh.hexdigest()}')
    print('ALL_ASSETS_DONE')

if __name__ == '__main__':
    main()
