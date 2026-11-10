#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# B1 верификатор ISO: PVD, El Torito (BIOS+EFI), UDF, лейбл, размер.
# Работает по файлу ISO (склеенному из чанков).
import sys, struct

def main(path):
    sz = None
    import os
    sz = os.path.getsize(path)
    print(f'ISO: {path}')
    print(f'размер: {sz} байт ({sz/2**20:.1f} MiB)')
    print(f'2048-кратно: {sz % 2048 == 0}')

    sigs = {}
    with open(path, 'rb') as f:
        for sector in range(16, 22):
            f.seek(sector * 2048)
            d = f.read(2048)
            for name, sig in (('CD001', b'CD001'), ('BEA01', b'BEA01'),
                              ('NSR02', b'NSR02'), ('NSR03', b'NSR03'),
                              ('TEA01', b'TEA01')):
                if sig in d[:8] + d[8:40]:
                    sigs.setdefault(name, []).append(sector)

        print('сигнатуры (секторы):', {k: v for k, v in sigs.items()})

        # PVD: ищем сектор с CD001 и типом 1
        pvd_sector = None
        for s in sigs.get('CD001', []):
            f.seek(s * 2048)
            d = f.read(2048)
            if d[0] == 1:
                pvd_sector = s
                label = d[40:72].decode('ascii', 'replace').rstrip()
                print(f'PVD: сектор {s}, Volume Label = "{label}"')
                vol_size = struct.unpack('<I', d[80:84])[0]
                print(f'Volume Space Size: {vol_size} секторов = {vol_size*2048} байт',
                      '(совпадает с файлом)' if vol_size*2048 == sz else '(НЕ совпадает!)')
                break
        if pvd_sector is None:
            print('ОШИБКА: PVD не найден!')

        # El Torito Boot Record
        for s in range(16, 22):
            f.seek(s * 2048)
            d = f.read(2048)
            if d[0] == 0 and b'EL TORITO SPECIFICATION' in d[7:39]:
                cat_lba = struct.unpack('<I', d[71:75])[0]
                print(f'El Torito Boot Record: сектор {s}, catalog LBA = {cat_lba}')
                f.seek(cat_lba * 2048)
                cat = f.read(2048)
                if cat[:2] != b'\x00\x01':
                    print('ОШИБКА: некорректный Validation Entry каталога!')
                    sys.exit(1)
                checksum = struct.unpack('<H', cat[2:4])[0]
                words = struct.unpack('<16H', cat[:32])
                total = (sum(words) & 0xFFFF)
                print(f'Validation Entry: checksum OK' if total == 0 else f'Validation Entry checksum FAIL ({total})')
                # записи каталога
                p = 32
                n_ent = 0
                while p < 2048:
                    b0 = cat[p]
                    if b0 == 0: break
                    if b0 & 0x80:
                        # section header
                        n = struct.unpack('<H', cat[p+2:p+4])[0]
                        print(f'  Section Header: платформа {hex(cat[p+1])}, записей {n}')
                        p += 32
                        continue
                    if b0 == 0x88 or b0 == 0x00 or b0 == 0x90 or b0 == 0x91:
                        lba = struct.unpack('<I', cat[p+8:p+12])[0]
                        cnt = struct.unpack('<H', cat[p+6:p+8])[0]
                        media = cat[p+1]
                        bootable = 'BOOT' if b0 & 0x88 else 'not-boot'
                        print(f'  Entry {n_ent}: {bootable} media={hex(media)} LBA={lba} sectors={cnt}')
                        n_ent += 1
                    p += 32
                if n_ent < 2:
                    print('ПРЕДУПРЕЖДЕНИЕ: меньше 2 загрузочных записей (BIOS+EFI)!')

    print('VERIFY_DONE')

if __name__ == '__main__':
    main(sys.argv[1])
