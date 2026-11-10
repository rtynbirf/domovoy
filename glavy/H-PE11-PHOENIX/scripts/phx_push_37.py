#!/usr/bin/env python3
# PHX Task 37: sha-aware push worklog.md (кролик принят, разбор AIDA 6ORMAN-i3) -> rtynbirf/H-PE11-PHOENIX (main)
import base64, json, os, sys, urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from gh_auth import gh_token  # AUDIT-2026-1030: env/credential store вместо plaintext
TOKEN = gh_token()
REPO = 'rtynbirf/H-PE11-PHOENIX'
API = f'https://api.github.com/repos/{REPO}/contents'

FILES = {
    'worklog.md': '/home/z/my-project/worklog.md',
}

def api(method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', f'Bearer {TOKEN}')
    req.add_header('Accept', 'application/vnd.github+json')
    if data:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')

fail = 0
for path, local in FILES.items():
    body = open(local, 'rb').read()
    print(f'== {path}: {len(body)} bytes')
    st, j = api('GET', f'{API}/{path}?ref=main')
    if st == 200:
        sha = j['sha']
        remote_bytes = base64.b64decode(j['content'])
        if remote_bytes == body:
            print(f'   [{path}] уже идентичен в репе — пропускаем PUT')
            continue
    elif st == 404:
        sha = None
    else:
        print(f'   GET FAIL HTTP {st}: {j}'); fail += 1; continue

    payload = {'message': 'PHX Task 37: worklog append (стенд 6ORMAN-i3 принят, разбор отчёта AIDA)', 'branch': 'main'}
    if sha:
        payload['sha'] = sha
    payload['content'] = base64.b64encode(body).decode()
    st, j = api('PUT', f'{API}/{path}', payload)
    if st in (200, 201):
        print(f'   PUSH OK -> commit {j["commit"]["sha"][:12]}')
    else:
        print(f'   PUSH FAIL HTTP {st}: {json.dumps(j)[:400]}'); fail += 1

sys.exit(1 if fail else 0)
