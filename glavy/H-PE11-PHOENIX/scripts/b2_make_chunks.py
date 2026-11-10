#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
B2 v2: genisoimage stdout -> чанки на диск + манифест (потоковая нарезка).
Запуск: b2_make_chunks.py <chunk_dir> <manifest_out> <iso_basename>
Съедает stdin, режет по 40MiB, пишет partNNNN, sha256, blob_sha1.
"""
import sys, os, json, hashlib

CHUNK = 40 * 2**20

def blob_sha1(d: bytes) -> str:
    return hashlib.sha1(f'blob {len(d)}\0'.encode() + d).hexdigest()

def main():
    chunk_dir, manifest_out, base = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(chunk_dir, exist_ok=True)
    parts = []
    total = 0
    idx = 0
    h_file = hashlib.sha256()
    buf = b''
    while True:
        data = sys.stdin.buffer.read(1 << 22)
        if not data:
            break
        buf += data
        while len(buf) >= CHUNK:
            piece, buf = buf[:CHUNK], buf[CHUNK:]
            h_file.update(piece)
            name = f'{base}.part{idx:04d}'
            with open(os.path.join(chunk_dir, name), 'wb') as f:
                f.write(piece)
            parts.append({'name': name, 'size': len(piece),
                          'sha256': hashlib.sha256(piece).hexdigest(),
                          'blob_sha1': blob_sha1(piece)})
            total += len(piece)
            print(f'  part {idx}: {total/2**20:.0f} MiB', flush=True)
            idx += 1
    if buf:
        h_file.update(buf)
        name = f'{base}.part{idx:04d}'
        with open(os.path.join(chunk_dir, name), 'wb') as f:
            f.write(buf)
        parts.append({'name': name, 'size': len(buf),
                      'sha256': hashlib.sha256(buf).hexdigest(),
                      'blob_sha1': blob_sha1(buf)})
        total += len(buf)
        idx += 1
    manifest = {'file': base, 'size': total, 'chunks': len(parts), 'chunk_size': CHUNK,
                'file_sha256': h_file.hexdigest(), 'parts': parts,
                'repo_dir': 'artifacts/iso_26100.1_pro_ru_v2'}
    json.dump(manifest, open(manifest_out, 'w'), indent=1)
    print(f'CHUNKS_DONE: {total} B, {len(parts)} чанков, sha256={h_file.hexdigest()}', flush=True)

if __name__ == '__main__':
    main()
