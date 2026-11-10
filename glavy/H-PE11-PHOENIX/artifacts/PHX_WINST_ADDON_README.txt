H-PE11 / FENIKS-11 -- DOPOLNENIE: WINST, MLF, DBF (ANDER_73)
=============================================================

SODERZHIMOE ARKHIVA:
1) PHX_WINST_ADDON.docx -- dopolnenie k otchetu (7 str.), Word/LibreOffice
2) PHX_WINST_ADDON.txt   -- tekstovaya kopiya bystrogo chteniya (v PE)

CHEM OTVECHAET NA SSYLKI HOZYAINA (usbtor.ru):
- WInst (Ander_73) -- ustanovshchik Windows iz WIM/ESD bez setup.exe;
  sam spraSHIVAET, kak stavit zagruzchik: BIOS / UEFI / OBA VMESTE [x].
  Vhodit v sostav PE Streltsa -- uzhe na flesHKE Hozyaina.
  Eto gotovyy ispolnitel SHAGOV 5-6 nashego algoritma (apply + bcdboot).
- MLF = Multi-loader flash -- skelet mul'tizagruzochnoy flesHki [x].
- DBF = Dual Boot Flash -- dvuhrazdel'naya flesHka (zagruzka + hranilische),
  reSHAET limit FAT32 4 GB bez SWM-narezki [x]. Alternativa Ventoy.
- Prakticheskiy plan: zalivku PHX11_ASIS.wim (DISM++) proverit 5 proverok,
  zatem postavit ee obratno WInst-om iz StrelecPE -- i test zalivki,
  i trenirovka instrumenta.

STATUS PO EV.1:
- [x] = doslovno iz s NIpetov stranits usbtor.ru i perepechatok SFST (sewin.me,
  fost.club, nelegal-edition.ru), data obrashcheniya 22.10.2026.
- [--] = detali menyu/opciy WInst i sostav razdelov DBF: usbtor iz pesocHnitsy
  ne otkryvaetsya (TCP refused), sverit po zhivym temam iz brauzera Hozyaina.

OSNOVNOY OTCHET: PHX_ZALIVKA_REPORT.zip (https://filebin.net/phx-diag-20261022/)
Protokol verifikatsii (glava 7 osnovnogo otcheta) ostayetsya obyazatelnym.
