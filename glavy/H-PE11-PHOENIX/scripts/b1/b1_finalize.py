#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Финализатор: манифест-блоб + дерево + коммит + ref. Блобы УЖЕ в репе (проверено).
import json, base64, hashlib, os, sys, time
import urllib.request, urllib.error

API = 'https://api.github.com/repos/rtynbirf/H-PE11-PHOENIX'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()

def hdr(ct='application/json'):
    return {'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
            'Content-Type': ct, 'User-Agent': 'phoenix11-fin'}

def req(url, method='GET', body=None, retries=6):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers=hdr(), method=method)
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(r, timeout=180) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as e:
            try: payload = json.loads(e.read())
            except Exception: payload = {}
            if e.code < 500 and e.code != 429:
                return e.code, payload
            last = (e.code, payload)
        except Exception as e:
            last = (0, {'err': str(e)})
        time.sleep(8 * (i + 1))
    return last

def blob_sha1(d): return hashlib.sha1(f'blob {len(d)}\0'.encode() + d).hexdigest()

m = json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json'))
repo_dir = m.get('repo_dir', 'artifacts/iso_26100.1_pro_ru')
man_bytes = json.dumps(m, indent=1).encode()
man_sha = blob_sha1(man_bytes)

st, j = req(f'{API}/git/blobs/{man_sha}')
if st != 200:
    st, j = req(f'{API}/git/blobs', 'POST', {'content': base64.b64encode(man_bytes).decode(), 'encoding': 'base64'})
    print('манифест-блоб:', st, j.get('sha'))
    assert st in (200, 201) and j.get('sha') == man_sha
else:
    print('манифест-блоб уже есть')

st, j = req(f'{API}/git/ref/heads/main')
parent = j['object']['sha']
st, j = req(f'{API}/git/commits/{parent}')
base_tree = j['tree']['sha']
print('parent:', parent[:12], 'base_tree:', base_tree[:12])

items = [{'path': f'{repo_dir}/{p["name"]}', 'mode': '100644', 'type': 'blob', 'sha': p['blob_sha1']} for p in m['parts']]
items.append({'path': f'{repo_dir}/MANIFEST.json', 'mode': '100644', 'type': 'blob', 'sha': man_sha})
print('дерево: записей', len(items))
st, j = req(f'{API}/git/trees', 'POST', {'base_tree': base_tree, 'tree': items}, retries=8)
assert st == 201, f'tree fail {st}: {str(j)[:300]}'
tree_sha = j['sha']
print('tree OK:', tree_sha[:12])

msg = ('PHOENIX11: WILLIAM B1 ISO 26100.1_PROFESSIONAL_X64_RU-RU.ISO '
       '(базис 26300.9807 ru-RU Pro, 26H2; uupdump converter v0.7.3; '
       '103 чанка x 40MiB; sha256 f08f504ee044e83942b79660b773021ebadf66b3d45195f2156237a2a771e1c0) [Task 40]')
st, j = req(f'{API}/git/commits', 'POST', {'message': msg, 'tree': tree_sha, 'parents': [parent]}, retries=8)
assert st == 201, f'commit fail {st}: {str(j)[:300]}'
commit_sha = j['sha']
print('commit OK:', commit_sha[:12])

for attempt in range(8):
    st, j = req(f'{API}/git/refs/heads/main', 'PATCH', {'sha': commit_sha})
    if st == 200:
        print('REF OK ->', commit_sha[:12])
        break
    print('ref retry', st, j)
    time.sleep(10)
else:
    raise SystemExit('REF НЕ ОБНОВЛЁН')

# проверка через contents
st, j = req(f'{API}/contents/{repo_dir}')
print('в каталоге репы файлов:', len(j) if isinstance(j, list) else j)
