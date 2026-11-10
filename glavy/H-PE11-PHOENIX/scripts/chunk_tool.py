#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PHOENIX11 chunk-tool: split | push | pull  — склад чанков в GitHub-репе.
Приказ Хозяина: «РЕПУ ЧАНКИ МЕЛКИЕ РЕЖЬ И ХРАНИ ТАМ, ПОТОМ ОТТУДА ПОДТЯГИВАЙ».

  split FILE DEST  — режет файл на чанки + манифест JSON (sha256 файла/чанков, git blob sha1)
  push MANIFEST    — Git Data API: блобы (skip существующих по blob-sha1) + одно дерево + один коммит
  pull MANIFEST DEST — качает чанки из репы, склеивает, проверяет sha256
"""
import sys, os, json, base64, hashlib, time
import urllib.request, urllib.error

REPO = 'rtynbirf/H-PE11-PHOENIX'
API = f'https://api.github.com/repos/{REPO}'
CHUNK = 40 * 2**20  # 40 MiB
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()

def hdr(extra=None):
    h = {'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
         'User-Agent': 'phoenix11-chunktool'}
    if extra: h.update(extra)
    return h

def req(url, method='GET', body=None, ct='application/json', timeout=300, retries=4):
    data = None
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
    r = urllib.request.Request(url, data=data, headers=hdr({'Content-Type': ct}), method=method)
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            code = e.code
            payload = e.read()
            if code < 500 and code != 429:
                return code, payload
            last = (code, payload)
        except Exception as e:
            last = (0, str(e).encode())
        time.sleep(3 * (i + 1))
    return last[0], last[1]

def blob_sha1(data: bytes) -> str:
    h = hashlib.sha1()
    h.update(f'blob {len(data)}\0'.encode())
    h.update(data)
    return h.hexdigest()

def cmd_split(src, dest):
    os.makedirs(dest, exist_ok=True)
    total = os.path.getsize(src)
    n = (total + CHUNK - 1) // CHUNK
    manifest = {'file': os.path.basename(src), 'size': total, 'chunks': n,
                'chunk_size': CHUNK, 'file_sha256': None, 'parts': []}
    fs = hashlib.sha256()
    with open(src, 'rb') as f:
        for i in range(n):
            data = f.read(CHUNK)
            fs.update(data)
            sha256 = hashlib.sha256(data).hexdigest()
            bsha = blob_sha1(data)
            name = f'{os.path.basename(src)}.part{i:04d}'
            with open(os.path.join(dest, name), 'wb') as p:
                p.write(data)
            manifest['parts'].append({'name': name, 'size': len(data),
                                      'sha256': sha256, 'blob_sha1': bsha})
            print(f'  part {i+1}/{n} {len(data)/2**20:.1f} MiB {sha256[:12]}')
    manifest['file_sha256'] = fs.hexdigest()
    mpath = os.path.join(dest, 'MANIFEST.json')
    with open(mpath, 'w') as f:
        json.dump(manifest, f, indent=1)
    print(f'OK split: {total/2**20:.1f} MiB -> {n} чанков, file_sha256={fs.hexdigest()}')
    print(f'manifest: {mpath}')

def cmd_push(manifest_path, repo_dir, msg):
    m = json.load(open(manifest_path))
    base = os.path.dirname(manifest_path)
    parent = _latest_commit_sha()
    tree_base = _root_tree_sha(parent)
    # 1) блобы
    items, skipped = [], 0
    for p in m['parts']:
        path = f'{repo_dir}/{p["name"]}'
        sha, body = req(f'{API}/git/blobs/{p["blob_sha1"]}')
        if sha == 200:
            skipped += 1
        else:
            data = open(os.path.join(base, p['name']), 'rb').read()
            assert blob_sha1(data) == p['blob_sha1'], f'чанк {p["name"]} повреждён локально'
            sha, body = req(f'{API}/git/blobs', 'POST',
                            {'content': base64.b64encode(data).decode(), 'encoding': 'base64'})
            assert sha == 201, f'blob fail {sha}: {body[:300]}'
            j = json.loads(body)
            assert j['sha'] == p['blob_sha1'], f'blob sha mismatch {j["sha"]}'
        items.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': p['blob_sha1']})
        print(f'  blob {p["name"]} {"SKIP(есть в репе)" if skipped else "OK"} {p["blob_sha1"][:12]}')
    # манифест и sha-файл тоже в репу
    man_bytes = json.dumps(m, indent=1).encode()
    man_sha = blob_sha1(man_bytes)
    sha, body = req(f'{API}/git/blobs/{man_sha}')
    if sha != 200:
        sha, body = req(f'{API}/git/blobs', 'POST',
                        {'content': base64.b64encode(man_bytes).decode(), 'encoding': 'base64'})
        assert sha == 201
    items.append({'path': f'{repo_dir}/MANIFEST.json', 'mode': '100644',
                  'type': 'blob', 'sha': man_sha})
    # 2) дерево поверх корня
    sha, body = req(f'{API}/git/trees', 'POST',
                    {'base_tree': tree_base, 'tree': items})
    assert sha == 201, f'tree fail {sha}: {body[:400]}'
    tree_sha = json.loads(body)['sha']
    # 3) коммит
    sha, body = req(f'{API}/git/commits', 'POST',
                    {'message': msg, 'tree': tree_sha, 'parents': [parent]})
    assert sha == 201, f'commit fail {sha}: {body[:400]}'
    commit_sha = json.loads(body)['sha']
    sha, body = req(f'{API}/git/refs/heads/main', 'PATCH', {'sha': commit_sha, 'force': False})
    assert sha == 200, f'ref fail {sha}: {body[:400]}'
    print(f'PUSH OK: {commit_sha[:12]} | новых блобов: {len(m["parts"]) - skipped}, пропущено: {skipped}')

def _latest_commit_sha():
    sha, body = req(f'{API}/git/ref/heads/main')
    assert sha == 200, f'ref fail {sha}: {body[:300]}'
    return json.loads(body)['object']['sha']

def _root_tree_sha(commit_sha):
    sha, body = req(f'{API}/git/commits/{commit_sha}')
    assert sha == 200
    return json.loads(body)['tree']['sha']

def cmd_pull(manifest_path, dest):
    m = json.load(open(manifest_path))
    repo_dir = None
    # repo_dir берём из аргумента pull: 3-й параметр
    os.makedirs(dest, exist_ok=True)
    ok = 0
    for p in m['parts']:
        out = os.path.join(dest, p['name'])
        if os.path.exists(out) and hashlib.sha256(open(out, 'rb').read()).hexdigest() == p['sha256']:
            print(f'  {p["name"]}: SKIP локально есть')
            ok += 1; continue
        sha, body = req(f'{API}/git/blobs/{p["blob_sha1"]}')
        assert sha == 200, f'pull fail {p["name"]}: {sha} {body[:200]}'
        j = json.loads(body)
        assert j['encoding'] == 'base64'
        data = base64.b64decode(j['content'])
        assert hashlib.sha256(data).hexdigest() == p['sha256'], f'sha256 mismatch {p["name"]}'
        with open(out, 'wb') as f:
            f.write(data)
        ok += 1
        print(f'  {p["name"]}: OK {len(data)/2**20:.1f} MiB')
    # склейка
    final = os.path.join(dest, m['file'])
    h = hashlib.sha256()
    with open(final, 'wb') as out:
        for p in m['parts']:
            with open(os.path.join(dest, p['name']), 'rb') as f:
                while True:
                    b = f.read(2**20)
                    if not b: break
                    h.update(b); out.write(b)
    assert h.hexdigest() == m['file_sha256'], 'ФИНАЛЬНЫЙ SHA256 НЕ СОВПАЛ!'
    print(f'PULL OK: {final} | {ok}/{len(m["parts"])} чанков | sha256 совпал')

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'split':
        cmd_split(sys.argv[2], sys.argv[3])
    elif cmd == 'push':
        cmd_push(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == 'pull':
        cmd_pull(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
