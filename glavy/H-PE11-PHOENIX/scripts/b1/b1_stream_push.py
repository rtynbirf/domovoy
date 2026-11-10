#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# «split»-заместитель: читает поток ISO со stdin, режет по 40MiB и СРАЗУ
# пушит каждый чанк как Git Blob в репу rtynbirf/H-PE11-PHOENIX.
# На диск не пишет почти ничего. В конце: манифест JSON + дерево + ОДИН коммит.
import sys, os, json, base64, hashlib, time
import urllib.request, urllib.error

REPO = 'rtynbirf/H-PE11-PHOENIX'
API = f'https://api.github.com/repos/{REPO}'
CHUNK = 40 * 2**20
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
REPO_DIR = 'artifacts/iso_26100.1_pro_ru'   # каталог чанков ISO в репе
MANIFEST_OUT = '/home/z/my-project/b1/ISO_MANIFEST.json'

def hdr(extra=None):
    h = {'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
         'User-Agent': 'phoenix11-stream'}
    if extra: h.update(extra)
    return h

def req(url, method='GET', body=None, timeout=600, retries=5):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers=hdr({'Content-Type': 'application/json'}), method=method)
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as e:
            code = e.code
            try: payload = json.loads(e.read())
            except Exception: payload = {}
            if code < 500 and code != 429:
                return code, payload
            last = (code, payload)
        except Exception as e:
            last = (0, {'err': str(e)})
        time.sleep(5 * (i + 1))
    return last

def blob_sha1(d: bytes) -> str:
    return hashlib.sha1(f'blob {len(d)}\0'.encode() + d).hexdigest()

def push_blob(data: bytes) -> str:
    sha = blob_sha1(data)
    st, j = req(f'{API}/git/blobs/{sha}')
    if st == 200:
        return sha  # уже в репе
    st, j = req(f'{API}/git/blobs', 'POST',
                {'content': base64.b64encode(data).decode(), 'encoding': 'base64'})
    assert st in (200, 201), f'blob POST fail {st}: {str(j)[:200]}'
    assert j.get('sha') == sha, f'blob sha mismatch: {j.get("sha")} vs {sha}'
    return sha

def main():
    prefix = sys.argv[1] if len(sys.argv) > 1 else 'ISO'
    parts = []
    total = 0
    fh = hashlib.sha256()
    idx = 0
    t0 = time.time()
    while True:
        data = sys.stdin.buffer.read(CHUNK)
        if not data:
            break
        fh.update(data)
        total += len(data)
        sha = push_blob(data)
        name = f'{os.path.basename(prefix)}.part{idx:04d}'
        parts.append({'name': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                      'blob_sha1': sha})
        dt = time.time() - t0
        print(f'  part {idx}: {len(data)/2**20:.0f} MiB, всего {total/2**20:.0f} MiB, {dt/60:.1f} мин', flush=True)
        idx += 1
    file_sha256 = fh.hexdigest()
    manifest = {'file': '26100.1_PROFESSIONAL_X64_RU-RU.ISO', 'size': total,
                'chunks': len(parts), 'chunk_size': CHUNK,
                'file_sha256': file_sha256, 'parts': parts, 'repo_dir': REPO_DIR}
    json.dump(manifest, open(MANIFEST_OUT, 'w'), indent=1)
    print(f'STREAM_DONE: {total/2**20:.0f} MiB, {len(parts)} чанков, sha256={file_sha256}', flush=True)

    # пуш манифеста + одного коммита
    man_bytes = json.dumps(manifest, indent=1).encode()
    man_sha = blob_sha1(man_bytes)
    st, j = req(f'{API}/git/blobs/{man_sha}')
    if st != 200:
        st, j = req(f'{API}/git/blobs', 'POST',
                    {'content': base64.b64encode(man_bytes).decode(), 'encoding': 'base64'})
        assert st in (200, 201)
    st, j = req(f'{API}/git/ref/heads/main')
    parent = j['object']['sha']
    st, j = req(f'{API}/git/commits/{parent}')
    base_tree = j['tree']['sha']
    items = [{'path': f'{REPO_DIR}/{p["name"]}', 'mode': '100644', 'type': 'blob', 'sha': p['blob_sha1']}
             for p in parts]
    items.append({'path': f'{REPO_DIR}/MANIFEST.json', 'mode': '100644', 'type': 'blob', 'sha': man_sha})
    st, j = req(f'{API}/git/trees', 'POST', {'base_tree': base_tree, 'tree': items})
    assert st == 201, f'tree fail {st}: {str(j)[:300]}'
    st, j = req(f'{API}/git/commits', 'POST',
                {'message': 'PHOENIX11: WILLIAM B1 ISO 26100.1_PROFESSIONAL_X64_RU-RU (26300.9807 ru-RU Pro, uupdump converter v0.7.3) — chunk store [Task 40]',
                 'tree': j['sha'], 'parents': [parent]})
    assert st == 201, f'commit fail {st}'
    commit_sha = j['sha']
    st, j = req(f'{API}/git/refs/heads/main', 'PATCH', {'sha': commit_sha})
    assert st == 200, f'ref fail {st}: {str(j)[:300]}'
    print(f'COMMIT_OK {commit_sha}', flush=True)

if __name__ == '__main__':
    main()
