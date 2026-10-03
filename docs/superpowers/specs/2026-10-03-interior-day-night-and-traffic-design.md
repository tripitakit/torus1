# Interno: giorno/notte a fusi orari e traffico sulle strade — progetto

Pezzo 1 di 4 per popolare l'interno delle sezioni (poi treno, traffico aereo, barche e attracco).
Vincolo: niente calo di frame rate sensibile (obiettivo: non oltre ~5% di FPS in meno all'interno).

## Scelte dell'utente

- Giorno completo in **24 minuti** (1 minuto = 1 ora), notte in **penombra (~15%)**.
- **Fusi orari continui** lungo l'anello: l'ora avanza di 24 h sulle 2000 sezioni; il lato opposto ha
  sempre 12 h di differenza.
- Traffico **medio, più denso in città, più rado di notte**.

## A. Ora e luce

### Orologio (`scripts/interior_clock.gd`, solo calcoli)

- `base_hour(seconds)`: ora della sezione 0; `START_HOUR` 10 all'avvio del gioco, `SECONDS_PER_HOUR` 60,
  modulo 24. Il tempo è quello dall'avvio (`Time.get_ticks_msec()`): scorre anche fuori.
- `ring_position(chain_z, docked_bridge, period)`: posizione continua sull'anello in sezioni:
  `docked + 0.5 - chain_z / period` (al centro della sezione di slot s vale il suo indice d'anello).
- `hour_at(base, ring_position, ring_sections)`: `base + 24 * ring_position / ring_sections`, modulo 24.
- `daylight(hour)`: 1 dalle 7 alle 17, `NIGHT_LIGHT` 0.15 dalle 20 alle 4, rampe smoothstep 4–7 e 17–20.
- `night(hour)`: `(1 - daylight) / (1 - NIGHT_LIGHT)`, 0 di giorno, 1 di notte.
- `sun_color(hour)`: colore dei soli, più caldo (arancio) a metà delle rampe.
- `format(hour)`: `"ORA 21:40"`.

### Applicazione

- **Uniform globali degli shader** (in `project.godot`, `[shader_globals]`): `interior_hour_origin` e
  `interior_hour_slope`; l'ora in un punto dell'interno è `origin + slope * z` (z del mondo interno).
  InteriorWorld le aggiorna a ogni frame (tengono conto della traslazione della catena). Una sola
  funzione GLSL `interior_night(hour)` replica `night()`.
- **Soli**: ogni sole prende potenza `SUN_ENERGY * daylight` e `sun_color` dalla propria z, a ogni frame
  (60 nodi: trascurabile). I globi usano un piccolo shader che legge le globali.
- **Luce ambientale**: l'ambiente è unico; prende `daylight` della posizione della nave (penombra anche
  per l'ambiente) e torna al valore originale all'uscita dall'interno.
- **Finestre**: lo shader degli edifici, con `use_hour = true` (solo all'interno; la base lunare resta
  com'è), brilla meno di giorno (`DAY_GLOW` 0.6) e più di notte (`NIGHT_GLOW` 2.0); di sera la quota di
  finestre accese sale di `EVENING_LIT` 0.2.
- **HUD interno**: sotto l'ID della sezione, `ORA hh:mm` della sezione dove si trova la nave.

## B. Traffico (`scripts/road_traffic.gd`)

### Corsie e anelli

- Per ogni linea di strada della sezione (lati ovest dei lotti = strade lungo la sezione; lati sud = strade
  intorno) si cercano i tratti continui ("run"). Il tipo è costante sulla linea (MAIN sui bordi dei pezzi,
  STREET altrove). Strade solo su terreno piatto: quota 0.
- Guida a destra, due corsie: MAIN a ±3 m dal centro, STREET a ±2 m.
- **Run chiuso** (strada intorno senza interruzioni): ogni corsia è un anello a sé, lungo la circonferenza.
- **Run aperto**: un solo anello per le due corsie, lungo 2L: andata su una corsia, inversione a U in fondo,
  ritorno sull'altra (niente auto che compaiono o spariscono a un vicolo cieco).

### Moto solo nello shader

- Su un anello di lunghezza C ci sono N posti a passo fisso d = C / N; le auto avanzano a velocità v.
- v è scelta perché ogni auto faccia un numero intero q di giri all'ora (`v = C q / 3600`): il `TIME` degli
  shader ricomincia ogni 3600 s e così il ricominciare non si vede.
- Ogni pezzo di terreno ha, per ogni tratto di corsia che contiene, i posti del tratto: un'istanza per
  posto. L'istanza parte da un punto della griglia globale e avanza di `fract(f·TIME)·d` (f = v/d); è
  visibile solo fra i suoi limiti `lo` / `hi` (il tratto). Così ogni auto è disegnata da un solo pezzo e
  passa al pezzo vicino senza salti.
- **Identità dell'auto** `n = (n0 - floor(f·TIME)) mod N`: un numero casuale fisso per n decide se il posto
  è occupato (85% di giorno, 35% di notte) e il colore. Un'auto resta la stessa lungo tutto il giro.
- **Strade intorno** curve: lo shader segue l'arco (raggio della sezione, uniform).
- **Dati per istanza**: il transform è la vera posizione e orientazione del posto all'avvio (assi: sinistra,
  su, avanti); le lunghezze delle colonne portano i valori che chiedono precisione (|avanti| = d,
  |su| = f). Colore e dati custom (in Compatibility sono a 16 bit) portano solo numeri piccoli o interi:
  custom = (lo, hi, n0, N), colore = (curva 0/1, seme, 0, 0).

### Densità e velocità

| Strada | Passo | Velocità |
| --- | --- | --- |
| MAIN | 90 m | ~25 m/s |
| STREET | 160 m | ~14 m/s |
| run che tocca la città | passo / 2,5 | uguale |

### Livelli di dettaglio

- **Vicino** (MultiMesh per pezzo di terreno, fino a `NEAR_END` 2 km): scatoletta 4,4 × 1,8 m con
  abitacolo, fari bianchi davanti e rossi dietro (emissivi, più forti di notte), colore da una tavolozza.
- **Lontano** (un MultiMesh per sezione, stessi dati portati nel riferimento della sezione): un punto con
  dimensione minima in pixel, da 1,5 a 12 km dalla telecamera; bianco se l'auto viene verso la
  telecamera, rosso se si allontana; di giorno quasi spento (grigio scuro), di notte acceso.
- Niente collisioni, ombre o luci vere.

## Test

- `test_interior_clock`: ore, fusi, curva della luce, formato.
- `test_road_traffic`: run e anelli (chiusi/aperti), corsie a destra sulla strada e a quota 0, ogni posto
  in un solo pezzo, continuità al confine fra pezzi e al ricominciare di TIME (con una copia in GDScript
  della formula dello shader), densità per tipo, velocità con giri interi all'ora.
- `test_interior_world`: soli più deboli di notte, HUD con l'ora, MultiMesh del traffico presenti.
- Prova GPU: FPS prima/dopo, immagini di giorno e di notte.

## Cambiato durante l'esecuzione

- **Velocità di una corsia**: non più letta dalla lunghezza di un vettore del transform (l'arrotondamento a
  32 bit cambiava da un'istanza all'altra e, nell'istante in cui un posto passa al successivo, due pezzi
  vicini non erano d'accordo: un'auto spariva per un frame). Ora il colore porta i "posti passati in
  un'ora" (intero, `f · 3600`) in due parti da 1024: tutte le istanze della corsia calcolano lo stesso
  valore. I limiti `lo` / `hi` sono arrotondati al millimetro e ogni tratto ha un posto in più per lato.
- **Auto in stile sci-fi low poly** (richiesta dell'utente): auto a levitazione senza ruote, scocca a
  sezione esagonale sfaccettata, cupola di vetro, alettone, barra di luce davanti (bianca) e dietro (rossa),
  striscia luminosa sotto la scocca nei colori d'accento degli edifici; leggera oscillazione. Tinte:
  bianco perla, canna di fucile, grafite, blu acciaio, argento, rosso scuro.
- **Auto non illuminate dalle luci vere** (`unshaded`, luce calcolata nello shader dall'ora): nel renderer
  Compatibility ogni luce che tocca un oggetto è una passata in più, e su un pezzo arrivano fino a 8 soli.
- **Notte**: carrozzeria al 30% (non 15%: spariva sull'asfalto), quota di auto di notte 50% (non 35%),
  barre di luce più grandi; di notte i punti lontani partono da 250 m (le barre sotto il pixel lasciavano un
  vuoto fra 300 e 1.200 m); punto da 0,8 m (non 2).
- **Tramonto**: tinta arancio al 60% del picco (era troppo forte).
- **Misure FPS** (vsync spento, 1920×1080, rumore ±5% fra esecuzioni): volo basso 146–148 senza traffico,
  139–147 con; dall'alto 155–160 senza, 153–155 con; all'attracco 214–218 senza, 210–221 con. Costo del
  traffico: 0–5%.
- I "cruiser interni" dell'utente sono il traffico aereo (pezzo 3): stesso stile delle auto.
