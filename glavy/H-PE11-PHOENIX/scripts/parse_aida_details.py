#!/usr/bin/env python3
# H-PE11 // AIDA64: вытащить RAM / диск / разделы / модель / BIOS / ОС
import re, html

raw = open('/home/z/my-project/upload/Report.htm', 'rb').read().decode('cp1251', errors='replace')
text = re.sub(r'<[^>]*>', ' ', html.unescape(raw))
text = re.sub(r'\s+', ' ', text)

# --- RAM: объём и модули ---
print('=== RAM ===')
for pat in [r'([\w\W]{0,90}(?:Kingston|Samsung|Hynix|Micron|Crucial|Adata|Timetec|Ramaxel|Plexhd|Noname)[\w\W]{0,90})',
            r'(\d+\s*ГБ\s*(?:SDRAM|DDR[\w]*)[\w\W]{0,60})',
            r'(Физическая память[\w\W]{0,120})',
            r'(Каналов памяти[\w\W]{0,60})',
            r'(DDRL?4?[\w\W]{0,40}(?:МГц|MHz)[\w\W]{0,40})']:
    hits = set()
    for m in re.finditer(pat, text):
        s = re.sub(r'\s+', ' ', m.group(1)).strip()
        if s not in hits:
            hits.add(s); print(' *', s[:180])
        if len(hits) >= 6: break

# --- Диск: модели и объёмы ---
print()
print('=== ДИСК ===')
for pat in [r'(Kingston[\w\W]{0,80})', r'(SanDisk[\w\W]{0,80})', r'(Samsung[\w\W]{0,5}SSD[\w\W]{0,60})',
            r'(SSD[\w\W]{0,70})', r'(eMMC[\w\W]{0,70})', r'(NVMe[\w\W]{0,70})', r'(M\.2[\w\W]{0,70})',
            r'(WDC[\w\W]{0,70})', r'(Toshiba[\w\W]{0,70})', r'(Hynix[\w\W]{0,70})', r'(BIWIN[\w\W]{0,70})',
            r'(GD\d[\w\W]{0,60})', r'(Способ подключения диска[\w\W]{0,100})']:
    hits = set()
    for m in re.finditer(pat, text, flags=re.I):
        s = re.sub(r'\s+', ' ', m.group(1)).strip()
        if s not in hits:
            hits.add(s); print(' *', s[:180])
        if len(hits) >= 4: break

# --- Разделы ---
print()
print('=== РАЗДЕЛЫ/ТОМА ===')
for pat in [r'((?:Локальный|Логический) диск[\w\W]{0,110})', r'(Дисковый накопитель #[\w\W]{0,110})',
            r'(NTFS[\w\W]{0,80})', r'(Файловая система[\w\W]{0,90})', r'(Загрузочный[\w\W]{0,80})',
            r'(Ёмкость[\w\W]{0,60})']:
    hits = set()
    for m in re.finditer(pat, text):
        s = re.sub(r'\s+', ' ', m.group(1)).strip()
        if s not in hits:
            hits.add(s); print(' *', s[:180])
        if len(hits) >= 5: break

# --- Модель/платы/BIOS/ОС ---
print()
print('=== СИСТЕМА ===')
for pat in [r'(Системная плата[\w\W]{0,90})', r'(Default string[\w\W]{0,60})', r'(Y116[\w\W]{0,60})',
            r'(Тип BIOS[\w\W]{0,80})', r'(AMI[\w\W]{0,60})', r'(Загрузка UEFI[\w\W]{0,60})',
            r'(Безопасная загрузка[\w\W]{0,60})', r'(Операционная система[\w\W]{0,90})',
            r'(10\.0\.28000[\w\W]{0,40})', r'(Разрешение[\w\W]{0,70})',
            r'(Серийный номер системы[\w\W]{0,60})', r'(Тип компьютера[\w\W]{0,70})',
            r'(Тачпад|Touchpad|I2C HID)[\w\W]{0,70}', r'(SMBIOS[\w\W]{0,60})']:
    hits = set()
    for m in re.finditer(pat, text):
        s = re.sub(r'\s+', ' ', m.group(0)).strip()
        if s not in hits:
            hits.add(s); print(' *', s[:180])
        if len(hits) >= 3: break
