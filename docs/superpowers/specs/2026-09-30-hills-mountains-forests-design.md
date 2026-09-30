# Colline boscose e catene montuose dentro le sezioni

## Contesto

Il pezzo precedente (`2026-09-30-interior-relief-design.md`) ha dato quote al
terreno interno: colline su tutti i campi e una zona RELIEF rara con cime
fino a circa 350 m. Il terreno disegnato sta sulla sua collisione, i dati
dei blocchi si costruiscono sui thread di lavoro.

L'utente, provato il risultato, vuole un paesaggio diverso: campi piatti,
colline boscose che coprono più lotti, e in alcune sezioni una vera catena
montuosa alta fino a 1500 m, boscosa fino a 600 m e poi solo roccia.

## Decisioni prese con l'utente

- **Campi piatti.** Sulle colline niente campi coltivati.
- **Colline:** una zona propria, circa il 10–15% dei lotti, in macchie di
  più lotti (mai un lotto solo), coperte di alberi.
- **Catena montuosa:** non in ogni sezione (circa una su tre), lungo l'asse
  della sezione, alta fino a **1500 m**, con variabilità lungo la cresta in
  altezza e in larghezza: massicci, picchi, guglie, selle e valli.
- **Alberi:** low-poly misti (conifere e latifoglie), bosco fitto, fino a
  600 m di quota; sopra solo roccia.
- **Collisione:** solo il terreno, gli alberi sono solo visivi.
- **Approccio:** zone e quote nel piano della sezione (thread di lavoro),
  posizioni degli alberi calcolate sui thread di lavoro insieme ai dati del
  terreno di ogni blocco, alberi disegnati con MultiMesh per blocco.

## Scope

Dentro:
- Zone COLLINA e MONTAGNA al posto di RELIEF; campi di nuovo piatti.
- Catena montuosa con cresta variabile e guglie.
- Colori del terreno: bosco sotto il limite degli alberi, roccia sopra e sui
  pendii ripidi.
- Alberi low-poly di due tipi, posizionati in modo deterministico.

Fuori:
- Neve, fiumi, laghi di montagna, sentieri, strade di montagna.
- Collisione con gli alberi, ombre.
- Griglia di quote più fitta per guglie sottili (la griglia resta a 50 m:
  le guglie sono larghe 100–250 m, spigolose).
- Alberi fuori da colline e montagne (campi, paesi, città).

## Numeri

- Raggio 2000 m. Un picco di 1500 m arriva a 500 m dall'asse, dove stanno i
  soli (sfere di 30 m ogni 1000 m): restano sopra.
- Lotto circa 261,8 × 250 m; griglia di quote a 50 m (come prima).
- Colline: `HILL_SHARE = 0,12` dei lotti, macchie di almeno
  `HILL_MIN_LOTS = 4` lotti, altezza 50–150 m.
- Catena: in circa un terzo delle sezioni (`CHAIN_CHANCE = 1/3`), lunga
  6–12 km, a 2 km almeno dalle calotte, cresta 450–1150 m più dettaglio e
  guglie, massimo assoluto 1500 m, mezza base 1–2 km.
- Alberi: uno ogni circa 17 m, alti 10–25 m, limite 600 ± 50 m, niente
  alberi su pendenze oltre 1,2.

## Architettura

### Dati: `scripts/section_plan.gd`

- `enum Zone { FIELD, TOWN, CITY, WATER, HILL, MOUNTAIN }` (RELIEF sparisce:
  al suo posto HILL = 4, MOUNTAIN = 5).
- `static func is_raised(zone) -> bool`: vero per HILL e MOUNTAIN.
- `var has_chain := false` (per i test e il debug).
- Spariscono `relief_threshold` e `relief_peak`.

### Generatore: `scripts/section_generator.gd`

Ordine: zone → città → **catena** → **colline** → colture → filari → strade
→ edifici → quote.

- **Catena** (classe interna `Chain`, costruita da `chain_of(plan)`, `null`
  se la sezione non ne ha): generatore casuale con seme
  `hash([indice, "chain"])`.
  - C'è se il primo numero casuale è sotto `CHAIN_CHANCE`.
  - Lunghezza fra 6 e 12 km; inizio scelto in modo che resti a 2 km dalle
    calotte.
  - Posizione attorno: dalla parte opposta alla città, ± un ottavo di giro.
    Così dista almeno 4,7 km dal centro città.
  - Linea di cresta: `x0 + 400 m × meandro(z)` (rumore 1D).
  - Lungo la cresta, un rumore "massiccio" (circa 3 km) in 0..1 dà sia
    l'altezza della cresta (450–1150 m) sia la mezza base (1–2 km):
    massicci larghi e alti, creste strette e basse, selle.
  - Le due estremità si abbassano su 1500 m.
  - Profilo trasversale: `cresta × p^1,4`, con `p = 1 − distanza / mezza base`
    (cresta a spigolo, fianchi concavi, piede morbido).
  - Dettaglio: moltiplicato per `0,7 + 0,45 × (1 − |rumore|)` (rumore 3D a
    circa 600 m, sul cilindro): contrafforti e valli laterali.
  - Guglie: 3–8 coni stretti (raggio 80–125 m, alti 400–700 m in più) vicino
    alla cresta. Il raggio minimo di 80 m tiene ogni guglia visibile sulla
    griglia a 50 m (un raggio di 50 m può cadere fra due punti e sparire).
  - Massimo 1500 m.
- **Zona MONTAGNA:** ogni lotto, tranne la città, con il centro dove la
  catena supera 20 m. Vince su campi, paesi e laghi.
- **Zona COLLINA:** fra i campi rimasti, quelli con il valore più alto di un
  rumore a macchie (circa 2 km), fino al 12% di tutti i lotti. Poi le macchie
  (lotti vicini, il giro si chiude) con meno di 4 lotti tornano campo.
- **Strade:** nessuna strada su un bordo con acqua, COLLINA o MONTAGNA.
- **Quote** su ogni punto di griglia:
  - `d_piatto` = distanza dal lotto non rialzato più vicino (campo, paese,
    città, lago) o da una calotta; se è 0, quota 0. Campi, paesi, città e
    laghi restano **esattamente piatti**.
  - `d_collina` = distanza dal lotto non COLLINA più vicino, o da una
    calotta.
  - collina = `50 + 100 × rumore01(punto) × smoothstep(0, 250, d_collina)`
    (rumore a circa 700 m), solo se `d_collina > 0`;
  - catena = `altezza della catena × smoothstep(0, 250, d_piatto)`;
  - quota = il massimo dei due.

### Geometria: `scripts/terrain_dressing.gd`

- I lotti COLLINA e MONTAGNA si disegnano interi (senza strade), come prima
  RELIEF.
- **Colore:** bosco `Color(0,2, 0,34, 0,15)` e roccia `Color(0,46, 0,44, 0,41)`.
  Quanto è roccia = il più grande fra `smoothstep(550, 650, quota)` e
  `smoothstep(0,9, 1,3, pendenza)`.
- **Alberi** (in `build_ground`, sui thread di lavoro):
  - griglia globale di celle da 17 m in coordinate della sezione;
  - per cella un hash intero di (indice sezione, cella x, cella z), da cui
    si ricavano sei numeri casuali: spostamento x e z nella cella, tipo,
    altezza, larghezza, rotazione e colore;
  - un albero appartiene al lotto che contiene il suo punto, se il lotto è
    COLLINA o MONTAGNA;
  - niente alberi entro 5 m dal bordo con un lotto non rialzato;
  - niente alberi sopra `600 + 50 × (2 × caso − 1)` m o su pendenze oltre
    1,2;
  - conifera con probabilità 0,4 sotto i 300 m, poi fino a 1 a 450 m;
  - alti 10–25 m, larghi il 35–50% dell'altezza, rotazione casuale attorno
    alla verticale (la verticale punta all'asse), base 0,5 m sotto il
    terreno;
  - colore della chioma variato attorno a un verde per tipo.
- **Modelli:** `scripts/tree_shapes.gd` crea due mesh unitarie (base a y = 0,
  cima a y = 1), a facce piatte, 30–60 triangoli: conifera (due coni su un
  tronco) e latifoglia (chioma sfaccettata su un tronco). Colore dei vertici:
  tronco marrone con alfa 0, chioma bianca con alfa 1.
- **Disegno:** per blocco un nodo `Trees` con due `MultiMeshInstance3D`
  (`Conifers`, `Broadleaves`), buffer preparato sul thread di lavoro (12
  numeri di trasformazione + 4 di colore di istanza: il verde della chioma),
  uno shader che tiene il tronco marrone dove l'alfa del vertice è 0 e usa il
  colore (vertice bianco × istanza verde) sulla chioma, niente ombre, visibili
  fino a 3 km, `custom_aabb` fino alla cima più alta.
  - Cambiato dopo il primo render: con i dati propri (`custom data`) il
    renderer di compatibilità mostrava chiome rosse, blu e magenta.
  - La larghezza della chioma (35–50% dell'altezza) tiene conto della
    larghezza della mesh unitaria (0,6 conifera, 0,72 latifoglia): corretto
    dopo la revisione finale, prima le chiome uscivano al 24–36%.
- Sul thread principale solo la creazione delle MultiMesh con il buffer.

### `scripts/interior_world.gd`

Nessun cambiamento previsto: gli alberi viaggiano dentro i dati del terreno
di ogni blocco.

## Test (TDD, ogni test visto rosso prima)

`tests/test_section_plan.gd`: HILL = 4, MOUNTAIN = 5, `is_raised`.

`tests/test_section_generator.gd`:
- colline: fra l'8% e il 13% dei lotti, ogni macchia di almeno 4 lotti,
  solo su lotti che prima erano campo;
- nessuna strada tocca COLLINA o MONTAGNA;
- quota esattamente 0 su ogni punto di griglia di campi, paesi, città e
  laghi, e alle estremità;
- fuori dalla catena al massimo 150 m;
- catena: fra 5 e 16 sezioni su 30 ne hanno una; in una sezione con catena
  il punto più alto è fra 1000 e 1500 m; la zona MONTAGNA sta a 1500 m almeno
  dalle calotte e lontana dalla città;
- variabilità: il profilo della cresta (massimo per fasce di 500 m lungo la
  sezione) varia di almeno 400 m; ci sono almeno 3 guglie (punti più alti di
  150 m di tutti i punti a 100 m di distanza);
- edifici a quota 0, determinismo, giunto del giro (come prima).

`tests/test_tree_shapes.gd`: mesh unitarie, facce verso l'esterno, alfa 0 sul
tronco e 1 sulla chioma.

`tests/test_terrain_dressing.gd`:
- colori bosco e roccia;
- alberi solo su COLLINA e MONTAGNA, con la base sul terreno, mai sopra
  650 m, mai su pendenze oltre 1,2, solo conifere sopra 450 m;
- densità: in un blocco tutto bosco circa un albero ogni 17 × 17 m (±30%);
- stessi alberi a ogni costruzione e dai thread di lavoro;
- nessun albero su un blocco piatto.

`tests/test_interior_world.gd`, `tests/test_interior_streaming.gd`: attracco
sotto 3 s, frame peggiore sotto 50 ms, al massimo 8 luci per oggetto (anche
le MultiMesh degli alberi).

Verifica finale nel gioco dal vivo, con la build a precisione doppia: FPS
sopra i boschi, aspetto di catena e guglie.

## Misure dopo l'esecuzione

- 8 sezioni su 30 con catena; cime fra circa 1050 e 1500 m.
- Circa 90.000 alberi per sezione senza catena, 140–166.000 con catena.
- Attracco 2,2–2,4 s (limite 3 s); frame peggiore in volo 25 ms (limite 50).
- GPU reale (GTX 1650 Super, 1600 × 900): 60 FPS stabili (vsync) sopra la
  catena e il bosco, 2,5–2,9 milioni di primitive, 735–1480 draw call.
