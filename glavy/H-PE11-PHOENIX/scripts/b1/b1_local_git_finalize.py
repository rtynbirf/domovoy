#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Гарантированная финализация: блобы из репы -> локальный git -> push.
import json, base64, subprocess, os, sys, time, hashlib
import urllib.request, urllib.error

API = 'https://api.github.com/repos/rtynbirf/H-PE11-PHOENIX'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
W = '/home/z/my-project/b1/gitwork'

def fetch_blob(sha, retries=6):
    for i in range(retries):
        try:
            r = urllib.request.Request(f'{API}/git/blobs/{sha}',
                headers={'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json'})
            with urllib.request.urlopen(r, timeout=300) as resp:
                j = json.loads(resp.read())
            return base64.b64decode(j['content'])
        except Exception as e:
            print(f'  blob {sha[:12]} retry {i+1}: {e}', flush=True)
            time.sleep(10)
    raise SystemExit(f'blob {sha} недоступен')

def sh(args, inp=None):
    r = subprocess.run(args, input=inp, capture_output=True, cwd=W)
    if r.returncode != 0:
        print('FAIL:', ' '.join(args), r.stderr.decode()[:300], flush=True)
        sys.exit(1)
    return r.stdout.decode().strip()

m = json.load(open('/home/z/my-project/b1/ISO_MANIFEST.json'))
repo_dir = m.get('repo_dir', 'artifacts/iso_26100.1_pro_ru')

lines = []
for i, p in enumerate(m['parts']):
    data = fetch_blob(p['blob_sha1'])
    assert hashlib.sha256(data).hexdigest() == p['sha256'], f'часть {p["name"]}: sha256 НЕ совпал!'
    real_sha = sh(['git', 'hash-object', '-w', '--stdin'], inp=data)
    assert real_sha == p['blob_sha1'], f'часть {p["name"]}: git sha {real_sha} != {p["blob_sha1"]}'
    lines.append(f"100644 blob {real_sha}\t{repo_dir}/{p['name']}")
    if (i+1) % 10 == 0:
        print(f'{i+1}/{len(m["parts"])} блобов в локальном git', flush=True)

man_bytes = json.dumps(m, indent=1).encode()
man_sha = sh(['git', 'hash-object', '-w', '--stdin'], inp=man_bytes)
lines.append(f"100644 blob {man_sha}\t{repo_dir}/MANIFEST.json")
print('все блобы локальны', flush=True)

sh(['git', 'update-index', '--index-info'], inp='\n'.join(lines) + '\n')
TREE = sh(['git', 'write-tree'])
print('tree:', TREE[:12], flush=True)
PARENT = sh(['git', 'rev-parse', 'FETCH_HEAD'])
msg = ('PHOENIX11: WILLIAM B1 ISO 26100.1_PROFESSIONAL_X64_RU-RU.ISO '
       '(26300.9807 ru-RU Pro, 26H2, uupdump converter v0.7.3, 103 чанка x 40MiB, '
       'sha256 f08f504ee044e83942b79660b773021ebadf66b3d45195f2156237a2a771e1c0) [Task 40]')
COMMIT = sh(['git', 'commit-tree', TREE, '-p', PARENT, '-m', msg])
print('commit:', COMMIT[:12], flush=True)

# AUDIT-2026-1030 / FINDING-C4: URL без токена (виден в ps), push через credential helper из env
url = 'https://github.com/rtynbirf/H-PE11-PHOENIX.git'
helper = '!f(){ echo username=x-access-token; echo "password=$GH_TOKEN"; };f'
r = subprocess.run(['git', '-c', f'credential.helper={helper}', 'push', url,
                    f'{COMMIT}:refs/heads/main'], cwd=W, capture_output=True,
                   env={**os.environ, 'GH_TOKEN': TOKEN})
print('push rc:', r.returncode, r.stdout.decode()[-200:], r.stderr.decode()[-300:], flush=True)
if r.returncode != 0:
    sys.exit(1)
print('PUSH_OK — склад ISO в main', flush=True)
