PHX FIX13 - MENU FORCE (menyu vybora OS ne poyavlyaetsya pri starte)
=====================================================================
v2: ispravlen konflikt funkcii R s vstroennym aliasom PowerShell
  'r' (Invoke-History): pereimenovana v Run-Cmd + selftest v FAZE 0.
  Sistema v progone v1 NE byla izmenena (skript sam ostanovilsya
  na backup, do lyuboi zapisi).
PRICHINA (veb-issledovanie, MS Learn BCDEdit /set + praktika):
  1) bootmenupolicy = Standard (defolt Win10/11). Po MS Learn pri
     Standard menyu pokazyvaetsya "tolko pri opredelennyh usloviyah",
     a ne kazhdyi start. Legacy = klassicheskoe menyu kazhdyi start.
  2) Bystryi zapusk (Hiberboot): posle VYKLYUCHENIYa Windows
     prosypaetsya iz hiberfil i PROPUUSKAET menyu.
  3) Monitor ne uspevaet prosnutsya za 7 sek (menyu bylo, ekran chern).

CHTO DELAET FIX13 (4 shaga, zapis PE ne trogaetsya):
  [1] bcdedit /set {bootmgr} bootmenupolicy Legacy
      (esli {bootmgr} otkazhet - postavit na loader Windows)
  [2] bcdedit /set {bootmgr} displaybootmenu Yes
  [3] bcdedit /set {bootmgr} timeout <TMO>     (default 7)
  [4] reg add ... \Session Manager\Power /v HiberbootEnabled 0
      (bystryi zapusk OFF; pervaia zagruzka posle etogo dolgoshe)

KAK ZAPUSTIT:
  1) Raspakui VES arhiv v odnu papku (3 faila vmeste).
  2) Zapusti PHX_FIX13_RUN.cmd (dvoinoi klik; UAC sam zaprosit
     prava administratora - soglasis).
  3) Zhdat konca: v konsoli i v loge budet SVODKA N1..N5.
  Opcional: PHX_FIX13_RUN.cmd 15  -> menyu 15 sekund (esli
  monitor dolgo prosypaetsya).

POSLE SVODKI 5/5:
  N1 PEREZAGRUZKA (Pusk -> Perezagruzka): menyu dolzhno byt vidno
     TMO sekund, 2 stroki. Nichego ne zhmi - Windows startuet sama.
  Test "spit li monitor" (esli menyu ne vidno): pri starte zhmi
     VNIZ 1 raz + Enter. Zagruzilsya FENIKS-11 PE -> menyu bylo,
     monitor ne usel: zapusti FIX13 s parametrom 15.
  N2 PEREZAGRUZKA: vybrat FENIKS-11 PE (WINST).
  Oshibka -> FOTO ekrana + C:\Boot\PHX_FIX13_LOG.TXT.

LOG:  C:\Boot\PHX_FIX13_LOG.txt
BAK:  C:\Boot\PHX_BCD_FIX13_BAK_<timestamp>  (+ kopiya na D:)
OTKAT: bcdedit /import C:\Boot\PHX_BCD_FIX13_BAK_<timestamp>
       (tochnyi put smotri v loge, FAZA 2)
