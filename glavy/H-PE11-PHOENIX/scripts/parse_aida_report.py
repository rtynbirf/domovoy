#!/usr/bin/env python3
# H-PE11 // AIDA64 Report.htm -> железо для whitelist v1.3 (быстрая версия)
import re, html

raw = open('/home/z/my-project/upload/Report.htm', 'rb').read().decode('cp1251', errors='replace')
raw = raw.replace('\r', '\n')

# 1) Пары полей: AIDA64 кладёт имя и значение в соседние ячейки одной строки <tr>
cells = []
for chunk in raw.split('<t'):           # дёшево режем по началу ячейки
    end = chunk.find('>')
    if end == -1:
        continue
    tag = chunk[:end].lower()
    body = chunk[end+1:]
    close = body.find('</t')
    if close == -1:
        close = len(body)
    if tag.startswith('d') or tag.startswith('h'):
        txt = html.unescape(re.sub(r'<[^>]*>', ' ', body[:close]))
        txt = re.sub(r'\s+', ' ', txt).strip()
        if txt:
            cells.append(txt)

print(f'ячеек: {len(cells)}')

want = {'Тип компьютера','Тип ЦП','Имя компьютера','Системная плата','Чипсет системной платы',
        'Тип BIOS','Дата выпуска BIOS','Версия BIOS','Загрузка UEFI','Безопасная загрузка',
        'Системная память','Видеоадаптер','Звуковой адаптер','Дисковый накопитель',
        'Сетевой адаптер','Операционная система','Язык системы','Разрешение',
        'Объём физической памяти','Физическая память','Код продукта','Тип сборки'}

seen = set()
for i, c in enumerate(cells):
    if c in want and i + 1 < len(cells):
        line = f'{c} :: {cells[i+1]}'
        if line not in seen:
            seen.add(line); print(line)

# 2) Поиск моделей/чипов одним проходом
full = html.unescape(re.sub(r'<[^>]*>', ' ', raw))
full = re.sub(r'\s+', ' ', full)
probes = re.compile(r'(Wireless[- ]?[\w]*|Wi-?Fi|WLAN|Bluetooth[\w ]*|Realtek[\w ]*|MediaTek[\w ]*|Alder[\w ]*|N\d{2,3}(?= C| \(|\s)|Celeron[\w ]*|Pentium[\w ]*|Core i\d[\w-]*|Ryzen[\w ]*|NVMe|SSD|M\.2|eMMC|UHD Graphics[\w ]*|Radeon[\w ]*|GeForce[\w ]*|I21\d|I22\d|AX\d{3}|9560|8265|3165|3168|7265|MT79\d\d|RTL8\d{3}|Kunlun|Xeon[\w ]*)', re.I)
out, pos, n = [], 0, len(full)
hits = {}
for m in probes.finditer(full):
    key = m.group(0)
    if key.lower() in hits:
        continue
    hits[key.lower()] = True
    s = max(0, m.start()-50); e = min(n, m.end()+70)
    out.append(full[s:e].strip())
    if len(out) >= 50:
        break
print()
print('=== УПОМИНАНИЯ ЧИПОВ ===')
for f in out:
    print(' *', f)
