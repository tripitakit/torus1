# A piedi — progetto

Il giocatore può scendere a piedi dall'Eagle e dal Moon Buggy sulla luna, e dall'internal cruiser posato su una
piazzola di un paese o di una città dentro le sezioni. Vista in prima persona; da fuori si vedono i mezzi.
L'auto per le strade interne è abbandonata (il cruiser interno basta).

## Scelte dell'utente

- **K** per scendere e per risalire (un tasto solo). V (nave ↔ rover) e F (attracco) restano.
- A piedi: W/S avanti/indietro, **A/D di lato**, mouse per girarsi e **guardare su/giù**, **J** (tenuto) per
  correre, **Spazio** per saltare.
- Internal cruiser: **posa assistita** su piazzole generate, una per paese/città.

## Struttura

- `scripts/on_foot.gd` — nucleo, solo funzioni pure: velocità dai comandi, sguardo, salto, distanza di risalita.
- `scripts/moon_walker.gd` — il pedone sulla luna (`CharacterBody3D`): suolo calcolato (`moon.ground_altitude`,
  `moon.up_at`, come il rover), gira con la luna, urta la base e i mezzi con `move_and_collide`, porta la toppa
  della luna.
- `scripts/interior_walker.gd` — il pedone dentro le sezioni (`CharacterBody3D`): collisioni vere con
  `move_and_slide`, gravità verso la parete del cilindro.
- `scripts/walker_hud.gd` — HUD a piedi.
- `scripts/landing_pads.gd` — dove stanno le piazzole (pure, dal piano della sezione).
- `game_mode.gd` — i modi a piedi e il tasto K.

## Scendere e risalire

- **Eagle** (posata sulla luna): K. Il pedone esce 6 m oltre il fianco destro dello scafo (13,5 m dal centro);
  se la nave è su un pad, fuori dal pad (45 m dal centro del pad), come il rover (`RoverRules.spawn_spots` con
  distanze sue). Se lì c'è un ostacolo prova sinistra, dietro, davanti. Rivolto verso fuori.
- **Moon Buggy** (sotto 1 m/s): K. Il pedone esce 2,5 m a sinistra del rover. Il rover resta lì, parcheggiato
  (fermo, nessun comando, niente toppa della luna).
- **Internal cruiser:** solo su una piazzola (sotto).
- **Risalire:** a piedi, entro **8 m dallo scafo** del mezzo (distanza dal suo box di collisione) l'HUD mostra
  `K BOARD`; K rimette a bordo con la vista di bordo. Due mezzi vicini: il più vicino. Eagle su un pad: basta
  essere entro 60 m dal centro del pad (il pad è alto 2 m e a piedi non ci si sale).
- **Rover:** se si risale sull'Eagle (con V o con K) il rover torna nella stiva (sparisce), come oggi con V.
- Ogni passaggio con la dissolvenza di 0,4 s.

## Camminare (`on_foot.gd`)

- Occhi a 1,7 m sopra i piedi, nessun corpo visibile. Capsula di collisione raggio 0,3 m, alta 1,8 m.
- Camminata **1,5 m/s**, corsa (J) **4 m/s**; in diagonale non più veloce.
- Mouse: girarsi (illimitato) e guardare su/giù entro **±70°**.
- Salto: **2 m/s** in su sulla luna (≈2,5 s in aria), **3,1 m/s** dentro (≈0,5 m d'altezza). In aria la
  velocità orizzontale resta quella dello stacco.
- **Luna:** gravità 1,62. I piedi seguono il suolo lunare vero. Non si sale dove il suolo davanti sale più di
  35° (si resta fermi). Si urtano edifici di Selene, pad, Eagle e rover.
- **Interno:** gravità 9,81 m/s² verso la parete del cilindro; terreno, alberi ed edifici hanno collisioni; non
  si entra negli edifici. Si sale su gradini fino a ~0,1 m (la piazzola sporge 5 cm).
- **HUD a piedi:** in alto a sinistra `ON FOOT` e la velocità; marcatori sui mezzi (`SHIP`, `ROVER`, `CRUISER`)
  con la distanza; in alto al centro `K BOARD` quando vale.

## Piazzole nei paesi e nelle città (`landing_pads.gd`)

- **Dove:** una per ogni gruppo di lotti TOWN/CITY che si toccano (anche attraverso il bordo che si richiude
  intorno), nel lotto del gruppo più vicino al centro del gruppo. Gli edifici di quel lotto si tolgono (come per
  i moli).
- **Com'è:** quadrata, 30 × 30 m, sporge 5 cm dal terreno (lastra spessa 0,6 m, quasi tutta sotto), con una "H"
  e un anello luminosi e quattro lampade agli angoli; materiale delle strutture interne. Collisione.
- **Trovarla:** nell'HUD del cruiser un marcatore `PAD` sulla piazzola più vicina entro 3 km.
- **Posa assistita:** sopra una piazzola (entro 20 m dal centro sul piano, sotto 30 m d'altezza, sotto 2 m/s)
  l'HUD del cruiser mostra `K LAND`. K: il cruiser scende da solo sul centro in 2 s (alto del cruiser verso
  l'asse, muso com'era sul piano), si posa e il pedone scende 4 m alla sua sinistra. K vicino al cruiser: si
  risale e si riparte da fermi.
- Mentre si è a piedi dentro, il caricamento delle sezioni e lo spostamento dell'origine seguono il pedone; il
  cruiser posato si sposta con lui.

## Test

TDD; solo i test nuovi o toccati.

- `tests/test_on_foot.gd`: velocità di camminata/corsa e in diagonale; sguardo limitato a ±70°; salto (tempo in
  aria con le due gravità); distanza dal box di un mezzo.
- `tests/test_moon_walker.gd` (luna vera, scena piccola): il pedone sta sul suolo mentre la luna si muove;
  cammina 1,5 m/s; si ferma contro un modulo della base; salta e ricade; non sale oltre 35°.
- `tests/test_landing_pads.gd`: una piazzola per gruppo TOWN/CITY; sul lotto del gruppo più vicino al centro;
  quel lotto senza edifici.
- `tests/test_interior_walker.gd` (mondo interno): il pedone sta sul terreno con la gravità verso la parete,
  cammina, urta un edificio, sale sulla piazzola.
- `tests/test_game_mode.gd` (toccato): K dall'Eagle posata → a piedi; K lontano → nulla; K vicino → a bordo; K
  dal rover → a piedi con il rover parcheggiato; K vicino al rover → sul rover; dentro: `K LAND` solo sopra una
  piazzola, posa, a piedi, risalita.
- **Prova GPU:** a piedi davanti all'Eagle, al buggy, al cruiser posato in un paese.

## Fuori da questo lavoro

- Corpo visibile, animazioni, suoni dei passi.
- Entrare negli edifici o nelle stazioni del treno.
- Scendere dal cruiser fuori dalle piazzole; scendere dall'Eagle nello spazio o agli attracchi.

## Cambiato durante l'esecuzione

- **Internal cruiser visibile da fuori:** non aveva un modello (solo la vista di bordo). Ora da fuori è uno degli
  incrociatori sci-fi del traffico interno (`AirTraffic.cruiser_mesh`, girato e ridotto nello scafo 4 × 2 × 8 m),
  sul livello esterno: la sua camera di bordo non lo vede.
- **Piazzole sui lotti piatti:** la collisione del terreno piatto è un anello di 128 strisce piatte (fino a 0,6 m
  dentro il cerchio); la piazzola sta al centro della striscia più vicina al centro del lotto (spostata al massimo
  di 49 m in un lotto di 261 m), alla sua quota e in squadra con essa. Sui lotti con rilievo resta sulla quota
  `height_at`.
- **Piazzole:** evitano i lotti già presi da moli e stazioni del treno.
- **HUD del cruiser:** il test che ne fissava i pezzi ora conta anche `LandPanel` e `PadMarker`.
- **Salita oltre 35° sulla luna:** nel codice (legge il suolo 0,5 m avanti), non coperta da un test automatico.
- **Prova GPU:** a piedi davanti all'Eagle sul pad (`K BOARD` a 48 m dal centro del pad), accanto al buggy
  parcheggiato, accanto al cruiser posato in un paese.
- **Dopo la revisione finale:**
  - **Terreno di collisione = terreno disegnato:** la collisione dei lotti piatti era a strisce di 98 m, il terreno
    disegnato a corde di 52 m: a piedi si galleggiava fino a 0,6 m sopra il suolo visibile. Ora la collisione piatta
    ha le stesse corde (15 strisce per pezzo di terreno), e la piazzola sta sulla corda del suo lotto, sia piatto sia
    con rilievo (sul rilievo il 36% delle piazzole era 12 cm sotto il suolo). Non serve più spostarla.
  - **Posa e spostamento dell'origine:** se l'origine del mondo si sposta durante i 2 s della posa, la posa prosegue
    verso la stessa piazzola (prima il mondo "saltava" a ogni tick).
  - **Cruiser fermo appena posato:** si parcheggia nell'istante in cui tocca, così i tasti tenuti premuti durante la
    dissolvenza non lo spostano più.
