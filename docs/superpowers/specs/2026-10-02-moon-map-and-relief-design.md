# Luna: mappa NASA e rilievo dei crateri

Data: 2026-10-02. Stato: approvato a voce, parte per parte.

## Scopo

1. Da lontano la luna sembra una palla grigia uniforme: la mappa generata ha poco contrasto, niente mari, niente
   crateri giovani chiari. → Usare le mappe vere della NASA.
2. Da vicino il suolo è una sfera perfetta: i crateri sono solo dipinti. → Rilievo vero (crateri recenti e
   antichi, da 20 m a decine di km) con collisione, ovunque sulla luna.

## Decisioni dell'utente

- Mappe NASA (CGI Moon Kit, SVS 4720, pubblico dominio): colore LRO e quote LOLA.
- Rilievo ovunque, con una toppa di terreno fitto che segue la nave.
- Crateri di profondità realistica.
- Base Selene nel cratere Platone (51,6° N, 9,4° O), come la Base Alpha.
- Regola di posa invariata (verticale vera, non pendenza del terreno).

## Dati

Script `tools/moon_maps.py` (eseguito una volta; i TIF NASA restano fuori dal repository):

- `lroc_color_poles_8k.tif` → `assets/textures/moon/color.jpg`, 8192×4096.
- `ldem_16.tif` (km rispetto a 1737,4 km) → `assets/moon/heights.bin`, 4096×2048, int16 little endian, metri
  già scalati per la nostra luna (× 250000 / 1737400).
- normal map dalle quote → `assets/textures/moon/normal.png`, 4096×2048 (tangente: x est, y nord).
- Le mappe generate di oggi e `tools/moon_textures.gd` vengono tolte.

Coordinate (negli assi della luna): −X verso il pianeta = latitudine 0, longitudine 0 (centro della faccia
visibile); +Y nord; +Z est. Longitudine = atan2(z, −x), latitudine = asin(y). Pixel: u = (lon + 180°) / 360°,
v = (90° − lat) / 180°.

## Base in Platone

`moon.base_direction()` diventa la direzione di 51,6° N, 9,4° O; l'est della base è la tangente verso est in
quel punto. Base, piazzole, portale Luna e guida seguono. `MoonOrbit.START_ANGLE` si riaggiusta se il test
"base in luce all'avvio" lo chiede.

## Altezza del terreno

`scripts/moon_terrain.gd`: `height(direction) -> float` (metri sopra `MoonOrbit.RADIUS`), negli assi della
luna. Somma di:

1. **Quote NASA**, bilineari.
2. **Crateri piccoli**, da 20 m a 400 m di diametro, su una griglia per ogni faccia del cubo proiettato sulla
   sfera, in 4 ottave di grandezza; per cella un numero pseudo-casuale fisso decide se c'è un cratere, dove,
   quanto è grande e se è giovane o vecchio. Densità crescente al calare del diametro.
   - Giovane: profondità 0,2 × diametro, bordo alto 0,04 × diametro, declivio esterno fino a 1,5 raggi.
   - Vecchio: metà profondità, bordo arrotondato.
   - Un fattore `detail` (0..1) li attenua (bordo della toppa, luna intera).
3. **Spianata della base**: entro 1,2 km dal centro della base la quota è quella del fondo di Platone sotto la
   base, senza crateri; tra 1,2 e 2,5 km si raccorda.

## Disegno

- **Luna intera** (`moon.gd`): la mesh di oggi, i vertici spostati alla quota NASA (crateri piccoli esclusi).
  Lo shader legge le mappe nuove con le coordinate sopra. Nasconde (discard) i frammenti entro il raggio della
  toppa dal suo centro, quando la toppa c'è.
- **Toppa** (`scripts/moon_patch.gd`, figlia della luna): attiva sotto `ATTACH_ALTITUDE`. Tre anelli quadrati
  nel piano tangente sotto la nave: punti ogni 8 m (~512 m), 32 m (~2 km), 128 m (~8 km); quota piena della
  funzione, `detail` che scende a 0 verso il bordo esterno. Ricostruita su un thread di lavoro quando la nave
  si sposta di un quarto dell'anello interno; le mesh nuove sostituiscono le vecchie tutte insieme. Vertici
  relativi al centro della toppa. Normali dalle differenze di quota.
- La sfera semplice oltre 1.500 km resta liscia.

## Collisione e HUD

- `moon.altitude(point)` = distanza dal centro − `RADIUS` − `height(direction)`.
- In `void_cruiser._move` il contatto col suolo si prova sugli 8 angoli dello scafo contro `height` invece che
  contro la sfera; la regola di posa resta quella di oggi (verticale vera).
- HUD ALT, assistenza sotto 300 m e auto-livello usano la nuova altitudine.
- Aggancio/sgancio al riferimento lunare restano misurati dalla sfera (30/32 km).

## Test

- Mappe: dimensioni, mari più scuri degli altopiani, quota di Platone (fondo più basso del bordo).
- `height`: piatta sulla base; un cratere giovane con bordo più alto del fondo e profondità ~0,2 D; stessa
  risposta a parità di punto; continuità (nessun salto tra punti vicini oltre la pendenza massima).
- Toppa: vertici alla quota della funzione; copertura degli anelli; ricostruzione dopo uno spostamento.
- Fisica: posa lontano dalla base all'altezza vera; schianto veloce sul fianco di un cratere; posa sulle
  piazzole ancora valida; i test di allunaggio esistenti verdi.
- GPU: luna da 5.000 km, da 20 km (uscita dal portale), da 300 m sui crateri. Il gioco non si avvia.
