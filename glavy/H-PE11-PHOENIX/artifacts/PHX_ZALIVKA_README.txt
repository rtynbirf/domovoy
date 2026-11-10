H-PE11 / FENIKS-11 -- OTCHET: ALGORITM SOZDANIYA ZALIVKI WINDOWS
================================================================

SODERZHIMOE ARKHIVA:
1) PHX_ZALIVKA_REPORT.docx  -- polnyy otchet (14 str.), otkryvat v Word/LibreOffice
2) PHX_ZALIVKA_REPORT.txt   -- ta samaya tekstovka bystrogo chteniya (v PE/iz konsoli)

CHTO VNUTRI OTCHETA (10 glav):
- Rezyume: chto takoe zalivka i iz chego ona sobiraetsya
- Karta sposobov: 5 semeystv (Sysprep+DISM / DISM++ as-is / sektornye klonirovshchiki
  tipa Clonezilla-Macrium-FFU / konveyery MDT-WDS-SCCM / sborka distribyutiva)
- Algoritm A (etalonnaya zalivka): audit-rezhim, chistka, CopyProfile,
  sysprep /generalize /oobe /shutdown, zahvat dism /capture-image iz PE,
  razvertyvanie dism /apply-image + bcdboot
- Algoritm B (bystryy, dlya etoy stantsii): DISM++ iz StrelecPE, bkap zhivoy sistemy
- Distribyutiv iz zalivki: install.wim, /split-image SWM (limit FAT32 4 GB), oscdimg ISO, Ventoy
- VERIFIKATSIONNYY PROTOKOL (glava 7): 5 proverok -- SHA256, Get-WimInfo,
  CheckIntegrity, test-apply, boot-test v VM. Bez 5/5 zalivka = [--] (zakon EV.1)
- Spetsifika stantsii: Win11 Home 24H2 build 26100, disk 0 (MBR->GPT, ESP), uroki Fix-2/3
  (bukvy tomov v PE plavayut -- privyazka k tipu razdela c12a7328 i SYSTEM-hive)
- Istochniki (glava 10): Microsoft Learn, winitpro.ru, white-windows.ru,
  schneegans.de, thesolving.com -- vse prochitany 22.10.2026

GLAVNYY VYVOD: zalivka = tehnologiya, a ne odin fail. Neispravnost proshlogo
WIM/ISO -- ne v zagruzchikah: bitye ishodniki + nulevaya verifikatsiya.
Poryadok deystviy: (1) segodnya snyat as-is obraz zhivoy sistemy cherez DISM++
na D: -- strahovka; (2) prognat 5 proverok; (3) potom reshat pro etalon v VM.
