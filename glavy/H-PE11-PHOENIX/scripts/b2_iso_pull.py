#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
B2/B4: стрим-пулер ISO из репы (версия для ограниченного диска).
Качает блобы по blob_sha1, ДОПИСЫВАЕТ в финальный файл, чанк на диске не копит.
В конце: sha256 сверка. Запуск: b2_iso_pull.py MANIFEST.json FINAL_PATH
"""
import sys, os, json, base64, hashlib, time
import urllib.request, urllib.error

REPO = 'rtynbirf/H-PE11-PHOENIX'
API = f'https://api.github.com/repos/{REPO}'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()

def hdr(extra=None):
    h = {'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
         'User-Agent': 'phoenix11-b2pull'}
    if extra: h.update(extra)
    return h

def req(url, method='GET', body=None, timeout=600, retries=6):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers=hdr({'Content-Type': 'application/json'}), method=method)
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            code = e.code; payload = e.read()
            if code < 500 and code != 429:
                return code, payload
            last = (code, payload)
        except Exception as e:
            last = (0, str(e).encode())
        time.sleep(5 * (i + 1))
    return last[0], last[1]

def main():
    man_path, final = sys.argv[1], sys.argv[2]
    m = json.load(open(man_path))
    if os.path.exists(final) and os.path.getsize(final) == m['size']:
        h = hashlib.sha256(open(final, 'rb').read()).hexdigest()
        if h == m['file_sha256']:
            print(f'PULL SKIP: {final} уже цел ({m["size"]} B)'); return
        os.remove(final)
    todo = []
    offset = 0
    if os.path.exists(final):
        # докачка с середины: определяем сколько уже есть (кратно чанкам)
        done = os.path.getsize(final)
        acc = 0
        for p in m['parts']:
            if acc + p['size'] <= done:
                todo.append(None); acc += p['size']
            else: break
        todo_idx = len(todo)
        print(f'RESUME: {acc/2**20:.0f} MiB уже на диске, осталось {m["chunks"]-todo_idx} чанков')
    else:
        open(final, 'wb').close()
        todo_idx = 0
    fh = hashlib.sha256()
    with open(final, 'r+b') as out:
        out.seek(0); total_read = 0
        for i, p in enumerate(m['parts']):
            if i < todo_idx:
                out.seek(p['size'], 1); total_read += p['size']
                continue
            blob_path = os.path.join(os.path.dirname(os.path.abspath(man_path)), p['name'])
            # локальный чанк если есть и валиден (после сплита) — экономит сеть
            data = None
            if os.path.exists(blob_path):
                d = open(blob_path, 'rb').read()
                if hashlib.sha256(d).hexdigest() == p['sha256']:
                    data = d
            if data is None:
                st, body = req(f'{API}/git/blobs/{p["blob_sha1"]}')
                assert st == 200, f'blob fail {p["name"]}: {st} {body[:200]}'
                j = json.loads(body)
                assert j.get('encoding') == 'base64'
                data = base64.b64decode(j['content'])
                assert hashlib.sha256(data).hexdigest() == p['sha256'], f'sha256 mismatch {p["name"]}'
            out.write(data); out.flush()
            total_read += len(data)
            print(f'  [{i+1}/{m["chunks"]}] {p["name"][-12:]} {len(data)/2**20:.1f} MiB '
                  f'({total_read/2**20:.0f}/{m["size"]/2**20:.0f} MiB)', flush=True)
    h = hashlib.sha256()
    with open(final, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 22), b''):
            h.update(chunk)
    assert h.hexdigest() == m['file_sha256'], f'ФИНАЛЬНЫЙ SHA256 НЕ СОВПАЛ: {h.hexdigest()}'
    print(f'PULL OK: {final} | {m["size"]} B | sha256 {h.hexdigest()}')

if __name__ == '__main__':
    main()
