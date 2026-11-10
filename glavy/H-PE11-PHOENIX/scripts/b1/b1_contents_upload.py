#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Заливка ISO-чанков через Contents API PUT (короткие запросы, по одному).
# Блобы берём из локального git (git cat-file), сеть вниз не нужна.
import json, base64, subprocess, os, sys, time
import urllib.request, urllib.error

API = 'https://api.github.com/repos/rtynbirf/H-PE11-PHOENIX'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
W = '/home/z/my-project/b1/gitwork'

def req(url, method='GET', body=None, retries=7, timeout=600):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers={
        'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json', 'User-Agent': 'phoenix11-put'}, method=method)
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as e:
            try: payload = json.loads(e.read())
            except Exception: payload = {}
            if e.code < 500 and e.code != 429:
                return e.code, payload
            last = (e.code, payload)
        except Exception as e:
            last = (0, {'err': str(e)})
        time.sleep(6 * (i + 1))
    return last

def cat_blob(sha):
    r = subprocess.run(['git', 'cat-file', 'blob', sha], cwd=W, capture_output=True)
    if r.returncode != 0:
        print('cat-file FAIL', sha, r.stderr.decode()[:200]); sys.exit(1)
    return r.stdout

m = json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json'))
repo_dir = m.get('repo_dir', 'artifacts/iso_26100.1_pro_ru')

import hashlib
def hashlib_ok(data, expected):
    return hashlib.sha256(data).hexdigest() == expected

done = 0
for i, p in enumerate(m['parts']):
    path = f'{repo_dir}/{p["name"]}'
    st, j = req(f'{API}/contents/{path}?ref=main')
    if st == 200:
        done += 1
        print(f'{i+1}/{len(m["parts"])} SKIP {p["name"]}', flush=True)
        continue
    data = cat_blob(p['blob_sha1'])
    assert hashlib_ok(data, p['sha256']), f'sha256 mismatch {p["name"]}'
    st, j = req(f'{API}/contents/{path}', 'PUT', {
        'message': f'PHOENIX11: ISO part {i+1}/{len(m["parts"])} [Task 40]',
        'content': base64.b64encode(data).decode(), 'branch': 'main'})
    if st not in (200, 201):
        print(f'PUT FAIL {st} {p["name"]}: {str(j)[:200]}', flush=True)
        sys.exit(1)
    done += 1
    print(f'{i+1}/{len(m["parts"])} OK {p["name"]}', flush=True)

# манифест
man_bytes = json.dumps(m, indent=1).encode()
st, j = req(f'{API}/contents/{repo_dir}/MANIFEST.json?ref=main')
if st != 200:
    st, j = req(f'{API}/contents/{repo_dir}/MANIFEST.json', 'PUT', {
        'message': f'PHOENIX11: ISO MANIFEST (sha256 {m["file_sha256"]}) [Task 40]',
        'content': base64.b64encode(man_bytes).decode(), 'branch': 'main'})
    print('MANIFEST PUT:', st, flush=True)
else:
    print('MANIFEST SKIP', flush=True)
print(f'CONTENTS_UPLOAD_DONE {done}/{len(m["parts"])}', flush=True)

def hashlib_ok(data, expected):
    import hashlib
    return hashlib.sha256(data).hexdigest() == expected
