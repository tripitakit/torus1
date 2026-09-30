# Rilievi dentro le sezioni: colline e piccole montagne

## Contesto

Il terreno interno (`2026-09-24-section-terrain-design.md`) è piatto: un
mosaico di campi, strade, paesi, città e laghi a quota 0 sulla parete del
cilindro. Questo pezzo aggiunge colline sui campi e qualche piccola montagna,
senza toccare paesi, città, laghi ed edifici.

## Decisioni prese con l'utente

- **Scala:** colline dolci 30–100 m sui campi, più una zona nuova **RILIEVO**
  rara con picchi fino a circa 350 m. Paesi, città e acqua restano piatti.
- **Aspetto del RILIEVO:** colore per quota e pendenza sui vertici (prato in
  basso, roccia sui pendii ripidi e in alto). Nessuna texture e nessun
  oggetto nuovo.
- **Architettura:** griglia di quote calcolata nel piano della sezione, nel
  thread di lavoro (approccio A). Mesh, collisione e test leggono tutti da lì.

## Scope

Dentro:
- Griglia di quote deterministica per numero di sezione.
- Zona `RELIEF` (circa 5% dei lotti), senza strade ai suoi bordi.
- Mesh del terreno che segue la quota, senza crepe fra i pezzi del mosaico.
- Collisione propria per i blocchi con rilievo.
- Colore prato/roccia nella zona RILIEVO.

Fuori:
- Alberi, rocce sparse, erosione, fiumi, laghi in quota.
- Edifici su pendio (restano solo in zone piatte).
- Ombre (i soli sull'asse restano senza ombre).
- Rilievo dentro i bridge o sulle calotte.

## Numeri

- Raggio 2000 m. I soli sono sull'asse: un picco di 350 m resta a 1650 m da
  loro.
- Lotto: circa 261,8 m attorno × 250 m lungo. Blocco: 3 × 4 lotti.
- **Griglia di quote: 5 punti per lotto in ogni senso.** Passo circa 52,4 m
  attorno e 50 m lungo. 240 colonne (il giro si chiude: la colonna 240 è la
  colonna 0) × 401 righe (da `z = 0` a `z = 20 000`) = 96 240 quote.
  - Perché 50 m e non 25 m: il generatore costa oggi circa 118 ms per
    sezione; 96 000 campioni di rumore costano circa 20 ms. Con 25 m i punti
    sarebbero 4 volte tanti, come i vertici da vestire per frame. Per
    colline di ~800 m e montagne di ~1500 m, in stile low-poly, 50 m bastano.
- Le linee della griglia cadono sui bordi dei lotti e dei blocchi: ogni blocco
  ha esattamente 16 × 21 punti di griglia.

## Architettura

### Dati: `scripts/section_plan.gd`

- `Zone.RELIEF` si aggiunge in fondo all'enum (`FIELD, TOWN, CITY, WATER,
  RELIEF`): i valori esistenti non cambiano.
- Costanti `RELIEF_POINTS_PER_LOT := 5`, `RELIEF_COLUMNS := LOTS_AROUND * 5`,
  `RELIEF_ROWS := LOTS_ALONG * 5 + 1`.
- `heights: PackedFloat32Array`, indice `row * RELIEF_COLUMNS + column`, in
  metri verso l'asse.
- `height_step() -> Vector2`: passo della griglia (attorno, lungo).
- `grid_height(column, row) -> float`: la colonna gira (`posmod`), la riga è
  bloccata fra 0 e l'ultima.
- `height_at(x, z) -> float`: interpolazione bilineare dei 4 punti di griglia
  attorno a (x, z). `x` gira come le distanze.
- `chunk_has_relief(chunk_around, chunk_along) -> bool`: vero se almeno un
  punto di griglia del blocco (bordi compresi) ha quota > 0.
- `slope_at(x, z) -> Vector2`: pendenza (dh/dx, dh/dz) per differenze
  centrali sulla griglia, interpolata come la quota.

### Generatore: `scripts/section_generator.gd`

Ordine in `generate()`: zone → città → **rilievo** (zona RELIEF) → colture →
filari → strade → edifici → **quote**. La zona RELIEF viene prima delle
strade, così le strade la vedono.

- **Rumore delle montagne:** `FastNoiseLite`, seme `hash([indice, "relief"])`,
  scala circa 1500 m, frattale a 4 ottave. Campionato sul punto 3D del
  cilindro, come le zone, così combacia dove il giro si chiude.
- **Zona RELIEF:** fra i lotti di campo, quelli con il rumore delle montagne
  più alto al centro del lotto, fino al **5% di tutti i lotti** (soglia per
  quantile, come per laghi e paesi). La soglia `relief_threshold` resta nel
  piano: serve alle quote.
- **Rumore delle colline:** secondo `FastNoiseLite`, seme
  `hash([indice, "hills"])`, scala circa 800 m.
- **Quota grezza** in ogni punto di griglia:
  - colline: `HILL_HEIGHT * (hills + 1) / 2`, con `HILL_HEIGHT = 100`;
  - montagne: `(MOUNTAIN_HEIGHT - HILL_HEIGHT) * smoothstep(soglia,
    massimo, rumore)`, con `MOUNTAIN_HEIGHT = 350` e `massimo` il valore più
    alto del rumore fra i centri dei lotti. Sotto la soglia vale 0.
  - quota grezza = colline + montagne, al massimo 350 m.
- **Raccordo a zero:** la quota grezza si moltiplica per
  `smoothstep(0, BLEND, d)`, con `BLEND = 250 m` e `d` la distanza più
  piccola fra:
  - la distanza dal lotto piatto più vicino (paese, città, acqua), cercato
    fra il lotto del punto e gli 8 vicini (BLEND è meno di un lotto, quindi
    basta; attorno le distanze girano);
  - la distanza dalle due calotte (`z` e `length - z`).
  Un punto su un lotto piatto o sul suo bordo ha `d = 0`: **quota esattamente
  0**. Così laghi, paesi, città e il loro contorno restano piani, e gli edifici
  (solo in paesi e città) stanno tutti a quota 0.
- **Strade:** in `_edge_road`, un bordo con un lotto RELIEF da un lato non ha
  strada, come per l'acqua. Le strade principali fra due campi seguono le
  colline.
- **Colture e filari:** calcolati per tutti i lotti come oggi (non cambiano i
  semi); un lotto RELIEF li ignora.

### Geometria: `scripts/terrain_dressing.gd`

- **Blocco piatto** (`chunk_has_relief` falso): tutto come oggi, stessi
  vertici e stessa collisione condivisa.
- **Blocco con rilievo:**
  - Ogni rettangolo del mosaico (campo, strada, selciato, acqua, RILIEVO) si
    divide su **tutte le linee della griglia di quote** che lo attraversano,
    sui **bordi di ogni possibile fascia stradale del suo lotto** (4 e 6 m da
    ogni lato del lotto), più i suoi bordi. Così due rettangoli che
    condividono un lato hanno esattamente gli stessi vertici su quel lato,
    nei due sensi. Niente crepe, anche fra una strada di 6 m e un campo di
    250 m.
  - Vertice: `(R - h) * (cos a, sin a, 0) + z * Z`, con `a = x / R` e
    `h = height_at` in coordinate della sezione (`x` del blocco + inizio del
    blocco).
  - Normale: con `u` verso l'asse, `t` attorno (verso x crescente) e
    `k = (R - h) / R`: `normalize(k * u - h_x * t - k * h_z * Z)`. Su terreno
    piatto è `u`; su un pendio che sale verso +x si inclina verso -x.
  - UV dei filari come oggi (metri piatti).
- **Colore del RILIEVO** (solo i lotti RELIEF; i campi in collina tengono il
  colore della coltura):
  - prato `Color(0.36, 0.5, 0.26)`, roccia `Color(0.46, 0.44, 0.41)`;
  - quanto è roccia = il più grande fra `smoothstep(0.5, 0.9, pendenza)` e
    `smoothstep(180, 300, h)`, con pendenza = lunghezza di `slope_at`.
  - Materiale: quello del selciato (colore dei vertici, niente strisce).
- **Collisione:** un blocco con rilievo sostituisce la forma del suo nodo
  `Collision` con una `ConcavePolygonShape3D` fatta con gli stessi triangoli
  di tutte le sue superfici del terreno (acqua compresa). È propria del
  blocco e sparisce con lui. Gli edifici tengono i loro collisori.
- **Budget di vestizione:** oggi 16 blocchi per frame (frame peggiore misurato
  27 ms, limite del test 50 ms). Quasi ogni blocco con campi avrà colline,
  quindi non serve un costo diverso per i blocchi con rilievo: si misura il
  frame peggiore e, se supera 35 ms, si abbassa `CHUNKS_DRESSED_PER_FRAME`
  finché torna sotto, controllando che le sezioni siano ancora pronte in
  volo.

### `scripts/interior_world.gd`

- Al massimo cambia `CHUNKS_DRESSED_PER_FRAME` (vedi sopra).
- Tutto il resto non cambia: la forma condivisa resta la forma iniziale di ogni
  blocco, e il rivestimento la sostituisce solo dove serve.

## Test (TDD, ogni test visto rosso prima)

`tests/test_section_generator.gd`:
- stessa sezione, stesse quote; sezioni diverse, quote diverse;
- quota 0 su ogni punto di griglia dentro o sul bordo di lotti paese, città,
  acqua, e alle due estremità della sezione;
- quota fra 0 e 350; oltre 100 m solo dove il rumore delle montagne supera la
  soglia;
- lotti RELIEF: il 5% di tutti i lotti (più o meno un lotto), solo dove prima
  c'era campo;
- nessuna strada su un bordo di un lotto RELIEF;
- la quota combacia dove il giro si chiude: `height_at(0, z)` =
  `height_at(circonferenza, z)`;
- `height_at` sui punti di griglia vale la griglia; a metà fra due punti vale
  la media;
- quota 0 sotto ogni angolo di ogni edificio;
- esiste almeno un punto oltre 200 m (le montagne ci sono davvero).

`tests/test_terrain_dressing.gd`:
- i test di oggi su quota 0 e area restano, su blocchi piatti;
- blocco con rilievo: ogni vertice sta a `R - height_at(x, z)` dall'asse;
- blocco con rilievo: le normali puntano verso l'asse (prodotto scalare
  positivo) e su un pendio si inclinano verso la discesa;
- nessuna crepa: ogni lato di triangolo usato da un solo triangolo sta sul
  bordo del blocco;
- l'area proiettata del blocco con rilievo sul cilindro resta quella del
  blocco (niente buchi né sovrapposizioni);
- colore RILIEVO: prato in basso e in piano, roccia su un pendio ripido o in
  alto;
- collisione: un blocco con rilievo ha una `ConcavePolygonShape3D` propria con
  gli stessi triangoli della mesh; un blocco piatto tiene la forma data.

`tests/test_interior_world.gd`:
- il test sulla forma condivisa diventa: blocchi piatti condividono la forma,
  blocchi con rilievo ne hanno una propria;
- il test sui vertici sul cilindro usa un blocco piatto;
- attracco sotto i 3 s (oggi circa 1 s).

`tests/test_interior_streaming.gd`:
- frame peggiore sotto i 50 ms in volo lungo la catena (misurato e annotato;
  sopra 35 ms si abbassa il budget di blocchi per frame).

`tests/test_interior_world_physics.gd` (o nuovo test di fisica):
- la navetta interna non ha gravità: spinta verso un pendio con
  `move_and_collide`, si ferma sulla superficie (entro mezza altezza dello
  scafo dalla quota giusta) e non ci passa attraverso.

Test esistenti da adattare: solo quelli di `test_interior_world.gd` elencati
sopra. `_test_zone_shares` conta solo acqua, paesi e città: non cambia.

Verifica finale nel gioco dal vivo con la build a precisione doppia (non solo
render di prova): colline visibili, montagne in zona RILIEVO, nessuna crepa,
nessun sfarfallio, collisione con i pendii.
