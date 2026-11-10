#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
B2 v2 stream-push: stdin (genisoimage.real -o -) -> параллельный POST блобов
с backpressure (tmp-чанки на диске, максимум QUEUE_CAP, удаление после пуша).
Финал: манифест + дерево + коммит (API); при отказе ref-PATCH -> REF_NEEDS_NATIVE.
Запуск: b2_stream_push.py <iso_basename>
"""
import sys, os, json, base64, hashlib, time, tempfile, queue, threading
import urllib.request, urllib.error

REPO = 'rtynbirf/H-PE11-PHOENIX'
API = f'https://api.github.com/repos/{REPO}'
CHUNK = 40 * 2**20
WORKERS = 14
QUEUE_CAP = 10          # tmp-чанков на диске максимум (~400 МБ)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
REPO_DIR = 'artifacts/iso_26100.1_pro_ru_v2'
MANIFEST_OUT = '/home/z/my-project/b1/ISO_MANIFEST_v2.json'
TMPDIR = '/home/z/my-project/b1/stream_tmp'

def hdr(extra=None):
    h = {'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
         'User-Agent': 'phoenix11-v2stream'}
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
        time.sleep(4 * (i + 1))
    return last[0], last[1]

def blob_sha1(d: bytes) -> str:
    return hashlib.sha1(f'blob {len(d)}\0'.encode() + d).hexdigest()

def push_blob_from(path, blob_sha):
    # GET-skip (байты свежие — обычно 404, но пусть будет безопасно)
    st, _ = req(f'{API}/git/blobs/{blob_sha}')
    if st == 200:
        return
    data = open(path, 'rb').read()
    assert blob_sha1(data) == blob_sha, 'чанк изменился на диске?!'
    st, j = req(f'{API}/git/blobs', 'POST',
                {'content': base64.b64encode(data).decode(), 'encoding': 'base64'})
    assert st in (200, 201), f'blob POST fail {st}: {str(j)[:200]}'
    assert j.get('sha') == blob_sha

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else 'ISO_V2'
    os.makedirs(TMPDIR, exist_ok=True)
    for f in os.listdir(TMPDIR): os.remove(os.path.join(TMPDIR, f))
    parts = {}
    lock = threading.Lock()
    q = queue.Queue(maxsize=QUEUE_CAP)
    errors = []

    def worker():
        while True:
            item = q.get()
            if item is None:
                return
            idx, path, bsha, csha = item
            try:
                push_blob_from(path, bsha)
                with lock:
                    parts[idx] = {'name': f'{base}.part{idx:04d}', 'size': os.path.getsize(path),
                                  'sha256': csha, 'blob_sha1': bsha}
                os.remove(path)
            except Exception as e:
                errors.append((idx, str(e)[:200]))
            finally:
                q.task_done()

    pool = [threading.Thread(target=worker, daemon=True) for _ in range(WORKERS)]
    for t in pool: t.start()

    fh = hashlib.sha256()
    total = 0
    idx = 0
    t0 = time.time()
    buf = b''
    eof = False
    while not eof:
        while len(buf) < CHUNK and not eof:
            data = sys.stdin.buffer.read(1 << 22)
            if not data:
                eof = True
            else:
                buf += data
                fh.update(data)
        if buf:
            piece, buf = (buf, b'') if len(buf) < CHUNK else (buf[:CHUNK], buf[CHUNK:])
            if piece:
                bsha = blob_sha1(piece)
                csha = hashlib.sha256(piece).hexdigest()
                path = os.path.join(TMPDIR, f'c{idx:04d}.tmp')
                with open(path, 'wb') as f:
                    f.write(piece)
                q.put((idx, path, bsha, csha))
                total += len(piece)
                if idx % 10 == 0:
                    print(f'  queued {idx}: {total/2**20:.0f} MiB, {time.time()-t0:.0f}s', flush=True)
                idx += 1
    for _ in pool: q.put(None)
    for t in pool: t.join()
    assert not errors, f'push errors: {errors[:3]}'
    plist = [parts[i] for i in sorted(parts)]
    print(f'STREAM_DONE: {total} B, {len(plist)} чанков, {time.time()-t0:.0f}s, sha256={fh.hexdigest()}', flush=True)

    manifest = {'file': base, 'size': total, 'chunks': len(plist), 'chunk_size': CHUNK,
                'file_sha256': fh.hexdigest(), 'parts': plist, 'repo_dir': REPO_DIR}
    json.dump(manifest, open(MANIFEST_OUT, 'w'), indent=1)
    # манифест-блоб
    man_bytes = json.dumps(manifest, indent=1).encode()
    man_sha = blob_sha1(man_bytes)
    st, j = req(f'{API}/git/blobs/{man_sha}')
    if st != 200:
        st, j = req(f'{API}/git/blobs', 'POST',
                    {'content': base64.b64encode(man_bytes).decode(), 'encoding': 'base64'})
        assert st in (200, 201), f'manifest blob fail {st}'
    # дерево + коммит
    st, j = req(f'{API}/git/ref/heads/main')
    assert st == 200, f'ref fail {st}'
    parent = j['object']['sha']
    st, j = req(f'{API}/git/commits/{parent}')
    base_tree = j['tree']['sha']
    items = [{'path': f'{REPO_DIR}/{p["name"]}', 'mode': '100644', 'type': 'blob', 'sha': p['blob_sha1']}
             for p in plist]
    items.append({'path': f'{REPO_DIR}/MANIFEST.json', 'mode': '100644', 'type': 'blob', 'sha': man_sha})
    st, j = req(f'{API}/git/trees', 'POST', {'base_tree': base_tree, 'tree': items})
    assert st == 201, f'tree fail {st}: {str(j)[:300]}'
    tree_sha = j['sha']
    msg = ('PHOENIX11: WILLIAM B1 ISO v2 TURNKEY (26100.1 base + autounattend baked + WILLIAM tweaks '
           '+ 26H2 chain SSU/eKB5121794/CU5127648) — chunk store [Task 41]')
    st, j = req(f'{API}/git/commits', 'POST', {'message': msg, 'tree': tree_sha, 'parents': [parent]})
    assert st == 201, f'commit fail {st}: {str(j)[:300]}'
    commit_sha = j['sha']
    st, j = req(f'{API}/git/refs/heads/main', 'PATCH', {'sha': commit_sha})
    if st == 200:
        print(f'COMMIT_OK {commit_sha}', flush=True)
    else:
        print(f'REF_NEEDS_NATIVE {commit_sha} (ref PATCH {st}: {str(j)[:200]})', flush=True)

if __name__ == '__main__':
    main()
