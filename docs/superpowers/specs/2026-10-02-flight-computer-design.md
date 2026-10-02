# Computer di bordo: bersaglio, consigli, arrivo automatico

Data: 2026-10-02. Stato: approvato in chat. Pezzo 2 di 4 del riordino della navigazione (1 limite di
velocità, fatto; 3 vettori di accelerazione; 4 riordino dell'HUD).

## Decisioni dell'utente

- T scorre i bersagli: DOCK → GATE TERRA → GATE LUNA → SELENE → nessuno.
- L'arrivo automatico si ferma al punto d'ingresso, a velocità zero; l'ultimo tratto è del pilota.
- Rotta a tappe attraverso i gate.

## Bersagli e tappe (`nav_targets.gd`)

- DOCK: il dock del ponte più vicino; punto d'arrivo 1 km fuori dal pad lungo la sua normale (`Port` +X).
- GATE TERRA / GATE LUNA: 500 m davanti al lato attivo, sull'asse (+Z del portale).
- SELENE: la piazzola più vicina; 500 m sopra il suo piano.
- Ogni punto ha anche la sua velocità nel riferimento in cui vola la nave (per Selene vista dal riferimento
  dell'anello: il moto della luna).
- Tappa: se il bersaglio sta dalla parte della luna (SELENE, GATE LUNA) e la nave no (oltre 5.000 km dal
  centro della luna), la tappa è GATE TERRA; al contrario GATE LUNA. Altrimenti il bersaglio stesso.

## Consigli (`flight_computer.gd`, puro)

Con `a` = l'accelerazione del freno (spinta base × 10 × fattori di precisione):

- distanza, velocità di avvicinamento (componente della velocità relativa verso il punto);
- ETA = distanza / avvicinamento (— se ci si allontana o sotto 0,5 m/s);
- STOP = v² / 2a;
- BRAKE IN = (distanza − STOP) / avvicinamento; ≤ 0 → BRAKE NOW (rosso).

## Arrivo automatico

G lo accende e lo spegne; lo spengono anche W/S/A/D/Z/X, C, B, T. Ogni tick il computer sceglie una
velocità voluta verso il punto: il minimo fra il limite di zona (×0,98), √(2·0,8·a·d) e d/2 s, più la
velocità del punto; comanda l'accelerazione (voluta − attuale)/0,5 s, limitata ad `a`, meno le spinte esterne
(gravità, riferimento), e la traduce in spinta sui sei assi senza girare la nave. Arrivato (entro 5 m e
sotto 0,5 m/s rispetto al punto): si spegne, inserisce il freno, mostra ARRIVED.

## HUD

- Pannello NAV a destra, sotto i pannelli esistenti: `NAV <bersaglio>[ via <tappa>]`, `DIST`, `CLOSING`,
  `ETA`, `STOP`, `BRAKE IN` / `BRAKE NOW`, `AUTO ARRIVING` / `ARRIVED`.
- Marcatore verde della tappa (il marcatore di SELENE con nome e colore propri).

## Test

- `test_flight_computer`: STOP, BRAKE IN, ETA; la legge di guida in simulazione arriva e si ferma senza
  sorpassare (fermo, in moto di lato, in arrivo veloce); scelta della tappa nei due sensi.
- `test_nav_physics` (scena vera): T scorre i bersagli; G dalla partenza porta al punto del GATE TERRA,
  fermo entro 5 m; un tasto di movimento spegne l'arrivo automatico.
- `test_cockpit`: pannello NAV e marcatore.

## Cambiato durante l'esecuzione

- Etichette dei marcatori (richiesta dell'utente durante il lavoro): da lontano GATE e NAV indicavano quasi lo
  stesso punto e le scritte si coprivano. Ogni marcatore ora scrive la sua etichetta in un angolo suo, in
  fondo a una linea diagonale dal rombo: GATE in alto a sinistra, NAV in basso a destra, SELENE in alto a
  destra (`BeaconMarker.label_offset`, `leader_line`, `label_rect`).
- Il marcatore NAV porta il nome della tappa (es. `GATE TERRA 120 km`).
- Prova GPU: dalla partenza, G con bersaglio GATE TERRA arriva al punto in circa 105 s (500 m/s vicino
  all'anello e al gate, 3 km/s in mezzo), fermo a 0,6 m. In un primo volo l'arrivo automatico si era spento a
  500 m dal punto: nessun tasto risultava premuto dallo script, quindi con ogni probabilità un input vero
  arrivato alla finestra di prova (che lo spegne, come voluto); non si è ripetuto.
