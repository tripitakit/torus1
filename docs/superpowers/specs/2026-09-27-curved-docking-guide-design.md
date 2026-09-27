# Guida di attracco curva e mirino del moto

## Contesto

La guida di attracco (`2026-09-25-docking-hud-design.md`, poi resa curva il
2026-09-27) disegna quadrati verdi dalla navetta al dock più vicino. Com'è
adesso:
- parte in direzione del pad, non del muso, quindi spesso non si vede al centro
  dello schermo;
- finisce con un tratto dritto di circa 1700 m lungo la normale del pad, troppo
  lungo;
- compare solo entro 10 km.

Manca anche un modo per vedere se la navetta si sta muovendo lungo il percorso.
Nel volo senza attrito il muso e il moto possono andare in direzioni diverse.

## Decisioni prese con l'utente

- **Partenza:** il percorso parte sempre dal centro della vista, cioè lungo il
  muso della navetta.
- **Forma:**
  - curvo fino in fondo, senza tratto dritto fisso;
  - arriva sul pad perpendicolare alla sua superficie;
  - si ricalcola a ogni frame;
  - non passa mai attraverso la stazione.
- **Quando si vede:** fra 100 m e 20 km dal dock più vicino, in linea d'aria.
  Sotto i 100 m la guida si spegne.
- **Mirino del moto:**
  - un quadrato poco più piccolo dei quadrati verdi (20 m contro 30 m), sulla
    direzione del moto reale, cioè la velocità relativa al dock;
  - azzurro quando sta tutto dentro il primo quadrato verde, rosso altrimenti;
  - sparisce sotto 1 m/s e quando la guida è spenta.

## Il percorso (`scripts/approach_guide.gd`, funzioni pure)

Si calcola nel sistema del bridge del pad: asse Y, pad a y = 0. Qui la stazione
vicina al dock è rotonda attorno all'asse:
- due sezioni di raggio `section_radius`, a partire da `half_gap` da ogni lato
  del pad (metà lunghezza del bridge);
- il bridge fra di loro, un prisma di raggio `bridge_radius`.

Ogni punto si descrive con tre coordinate: distanza dall'asse, angolo attorno
all'asse (`atan2(x, z)`) e altezza lungo l'asse.

**Zone vietate:**
- **sezioni:** oltre `half_gap − 300 m` di altezza, la distanza dall'asse deve
  essere almeno `section_radius + 300 m` (il "ripiano"). Questo tiene 300 m dal
  mantello e 300 m dal bordo;
- **bridge:** altrove, almeno `bridge_radius + 100 m`;
- **eccezione per il pad:** entro 0,05 rad dall'angolo del pad (circa metà della
  sua faccia) basta la distanza del pad, così il percorso può scendere su di esso.

**Costruzione:**
1. **Curva unica.** Una curva di Hermite in quelle tre coordinate, 128 tratti,
   dalla navetta al pad:
   - alla partenza la tangente è il muso;
   - all'arrivo la tangente punta verso l'asse lungo la normale del pad;
   - l'ampiezza delle tangenti è la distanza navetta-pad (o l'arco attorno
     all'asse, se è più lungo).

   Girando attorno all'asse, la curva aggira il bridge invece di tagliarlo.
2. **Sopra il bordo della sezione.** Se la curva unica scende sotto il ripiano
   dove ci sono le sezioni, si usano due pezzi:
   - dalla navetta al punto sul ripiano, 300 m prima del bordo della sezione più
     vicina, all'angolo del pad. Si arriva lì diretti verso lo spazio fra le
     sezioni;
   - da lì al pad, con un quarto d'ellisse (32 tratti) che scende morbido e
     arriva perpendicolare.
3. **Sollevamento.** Dove un punto resta dentro una zona vietata, viene
   allontanato dall'asse di quanto serve. Il sollevamento:
   - scende ai lati con una pendenza massima di 0,5 m per metro di percorso;
   - è addolcito da tre medie mobili su 9 punti;
   - vicino ai due capi cresce da zero, così la partenza lungo il muso e
     l'arrivo sul pad non cambiano.

**Casi limite:**
- se il muso punta contro la stazione da vicino, o se la navetta è già dentro un
  margine, il percorso piega subito. Resta comunque fuori dalla stazione;
- se il muso punta dalla parte opposta, la curva prima va avanti e poi torna
  indietro.

Nel prototipo un calcolo costa circa 0,6–0,9 ms.

## Quadrati e mirino

**Quadrati:**
- fino a 40 (prima erano 20), a passo `lunghezza / 40`, fra 50 e 500 m. Il primo
  è a 100 m. Coprono circa 19,6 km;
- `gate_centres(path)` dà centro e direzione di ogni quadrato;
- `gates_along` li disegna come prima: quadrati di 30 m perpendicolari al
  percorso.

**Mirino:**
- `marker_segments(centre, along, up)`: un quadrato di 20 m perpendicolare al
  moto;
- `marker_on_path(gate_centre, gate_along, up, marker_centre)`: vero se il
  centro del mirino dista dal centro del primo quadrato al massimo 5 m lungo
  ciascuno dei due lati del quadrato. Vuol dire che il mirino ci sta dentro
  tutto: circa 3° a 100 m.

## Navetta (`scripts/void_cruiser.gd`)

- **Nodi:** due nodi `top_level` a linee, con materiale unshaded trasparente:
  - `ApproachGuide`: verde, come ora;
  - `HeadingMarker`: rosso `(1, 0.25, 0.2, 0.9)` o azzurro `(0.3, 0.85, 1, 0.9)`.
- **A ogni frame:**
  1. trova il dock più vicino e la distanza dal pad;
  2. se la distanza è fuori da 100 m – 20 km, nasconde tutti e due i nodi;
  3. altrimenti calcola il percorso nel sistema del bridge (muso = −Z della
     navetta; raggi e metà del bridge letti dalla stazione) e lo riporta nel
     mondo, relativo alla navetta;
  4. il moto è `velocity − get_docking_port_velocity(bridge)`. Il mirino sta su
     quella direzione, alla distanza del primo quadrato.

## Fuori scope

- Mirino sul muso.
- Marcatori sulla navball.
- Suoni.
- Guida per l'internal-cruiser.

## Testing

- **Percorso** (funzioni pure, bridge come quello vero):
  - parte dalla navetta e finisce sul pad;
  - parte lungo il muso;
  - arriva perpendicolare;
  - nessun punto, anche fra un campione e l'altro, entra in una sezione o nel
    bridge;
  - nessuna curva oltre 15° fra un tratto e il successivo;
  - dritto quando la navetta è davanti al pad con il muso su di esso;
  - da dietro una sezione, a 1 km dal pad lungo il percorso sta ancora curvando.

  Le navette di prova sono: davanti, dietro una sezione, dall'altra parte del
  bridge, a 20 km, dal lato del pianeta, fra le sezioni dal lato opposto, lungo
  l'asse, vicina davanti, muso all'indietro. Tre casi scomodi (muso contro una
  sezione, a pelo di una sezione, muso contro il bordo) controllano solo capi e
  zone vietate.
- **Quadrati:** 40 al massimo, e i quadrati seguono un percorso piegato.
- **Mirino:** quadrato di 20 m perpendicolare al moto; dentro con 4 m di scarto,
  fuori con 6 m.
- **Scena vera:**
  - primo quadrato lungo il muso;
  - visibile a 15 km, nascosto a 25 km e a 95 m. A 95 m il muso è rivolto
    all'indietro: così il percorso supera i 100 m e il test verifica davvero
    la regola della distanza;
  - nessun quadrato nelle sezioni da dietro una sezione;
  - mirino azzurro e rosso secondo lo scarto;
  - mirino nascosto da fermi.
- **Render (xvfb):** cockpit dietro una sezione con il mirino rosso, e vista
  laterale.
