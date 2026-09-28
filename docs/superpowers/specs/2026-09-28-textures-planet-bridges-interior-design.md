# Texture nuove: pianeta tipo Terra, bridge, interno

## Contesto

- **Pianeta:** ha una texture da luna, una sola sfera, senza atmosfera.
- **Bridge:** usano la stessa texture a esagoni delle sezioni.
- **Interno:** tubo del bridge e pareti di fondo delle sezioni hanno un colore
  grigio uniforme, senza texture e senza coordinate UV.

## Decisioni prese con l'utente

- Le texture si generano in **Blender tramite MCP**.
- **Pianeta:**
  - tipo Terra: oceani, continenti con deserti, calotte polari;
  - nuvole su uno strato separato che ruota lentamente;
  - un uragano su un oceano;
  - alone di atmosfera sul contorno.
- **Bridge:** pannelli metallici rettangolari di due misure, giunture scure,
  griglie e piccole luci di posizione.
- **Interno, stile industriale:**
  - **tubo:** pannelli grandi, nervature ad anello, striscia luminosa lungo il
    tubo;
  - **pareti di fondo:** anelli di pannelli, fasce gialle e nere al foro e al
    bordo, piccole luci lungo le fasce.

## Come si generano (`tools/blender/`)

- **`bake_lib.py`:** costruisce nodi procedurali su un piano con UV 0..1, poi
  calcola ("bake") ogni canale in un PNG:
  - colore e dati (rugosità, luci, copertura nuvole) passano da un nodo
    Emission, con bake di tipo EMIT;
  - il rilievo passa da un nodo Bump sull'altezza, con bake di tipo NORMAL in
    tangent space.

  Per le texture che si ripetono, il rumore è in 4 dimensioni, avvolto su un
  toro: i bordi opposti combaciano.
- **`panel_textures.py`:** gruppi `bridge/`, `interior_tube/` e `interior_cap/`,
  ognuno con `color`, `roughness`, `normal` ed `emission`, a 2048×2048:
  - `bridge` e `interior_tube` si ripetono in tutte e due le direzioni;
  - `interior_cap` si ripete lungo il giro (u) e copre una volta la parete in
    direzione radiale: v = 0 al foro del bridge, v = 1 al bordo della sezione.
- **`planet_textures.py`:**
  - `planet/` con `color`, `roughness` e `normal`, a 4096×2048;
  - `clouds/clouds.png`, bianco con la copertura come trasparenza, 4096×2048.
  - Mappa equirettangolare con la stessa formula della sfera di Godot: un
    pixel (u, v) corrisponde alla direzione
    (sin 2πu · sin πv, cos πv, cos 2πu · sin πv), con v = 0 al polo nord.
  - **Uragano:** spirale logaritmica a due bracci, con occhio libero e 430 km
    di raggio, centrata a 20° di latitudine nord. Lo script cerca la longitudine
    con più oceano intorno, leggendo la rugosità appena generata.
- Gli script si lanciano in Blender con
  `TOOLS = '<repo>/tools/blender'; exec(open(TOOLS + '/<script>.py').read()); run('<repo>/assets/textures')`.
  I PNG generati entrano nel repository insieme ai file `.import` di Godot.

## Godot

- **Bridge (`torus_station.gd`):** i bridge hanno un materiale proprio, con le
  texture `bridge/`.
  - Un pannello (una ripetizione della texture) misura circa 100 m. Il numero di
    ripetizioni lungo il giro e lungo il bridge è arrotondato all'intero, così
    non c'è giuntura dove il giro si chiude.
  - Le luci hanno la stessa intensità di quelle delle sezioni.
  - Le sezioni tengono la texture a esagoni. Il pad non cambia.
- **Interno (`interior_world.gd`):**
  - **Tubo:** la superficie del cilindro ottiene coordinate UV. Lungo il giro
    si ripete un numero intero di volte, con un pannello di circa 60 m. Lungo
    il tubo si ripete un numero intero di volte per ogni pezzo di tubo, così i
    pezzi si uniscono senza salti.
  - **Pareti di fondo (anelli piatti):** u = angolo / 2π × 64 ripetizioni;
    v = (raggio − raggio del foro) / (raggio della sezione − raggio del foro).
  - Materiali nuovi per tubo e pareti, con le texture e le luci. La collisione
    non cambia.
- **Pianeta (`planet.gd`):**
  - **Superficie:** `planet/color.png`, `roughness.png`, `normal.png`. La vecchia
    `albedo.png` da luna si elimina.
  - **`Clouds`:** sfera figlia, raggio + 10 km, materiale trasparente e
    illuminato, così è scura sul lato notte. Ruota attorno all'asse Y di un
    giro ogni 3600 s, e solo mentre il gioco gira, non nell'editor.
  - **`Atmosphere`:** sfera figlia, raggio + 40 km, shader additivo non
    illuminato:
    - alone = (1 − N·V)^4, più forte dove la normale guarda il sole;
    - colore azzurro;
    - la direzione del sole si legge da `sun_path`, di default
      `../../SunLight`: la +Z del nodo luce punta verso il sole.

## Fuori scope

- Luci delle città sul lato notte.
- Nuvole animate che cambiano forma.
- Atmosfera vista dall'interno.
- Nuove texture per le sezioni.

## Testing

- **Texture:**
  - dimensioni;
  - canale alfa delle nuvole, con valori sia pieni sia vuoti;
  - nelle texture che si ripetono, prima e ultima colonna e prima e ultima riga
    si somigliano quanto due colonne vicine.
- **Bridge:** materiale diverso da quello delle sezioni, con le texture
  `bridge/`, ripetizioni intere, luci accese.
- **Interno:**
  - tubo e pareti hanno UV;
  - u delle pareti fra 0 e 64, v fra 0 e 1;
  - v del tubo su un numero intero di ripetizioni;
  - materiali con le texture.
- **Pianeta:**
  - `Clouds` e `Atmosphere` con i raggi giusti;
  - le nuvole ruotano con `_process`;
  - l'atmosfera ha la direzione del sole;
  - la superficie usa le texture nuove.
- **Render (xvfb):**
  - pianeta visto dalla stazione;
  - un bridge da vicino;
  - dall'interno, il tubo e una parete di fondo.

## Revisione durante l'esecuzione (2026-09-28)

- **Nuvole nello shader della superficie.** La sfera `Clouds` separata, 10 km
  sopra la superficie, nel render mostrava macchie triangolari dove si vedeva la
  superficie al posto delle nuvole.
  - **Causa:** "z-fighting". Il renderer `gl_compatibility` usa un depth buffer
    normale, e con la camera del pilota (da 2 m a 69.500 km) a 5000 km di
    distanza non riesce a distinguere due superfici lontane 10 km.
  - **Soluzione:** ora la superficie ha uno shader che sovrappone la mappa delle
    nuvole spostata in longitudine (`cloud_offset`, un giro ogni 3600 s). Il
    lato notte resta scuro, perché lo shader è illuminato.
  - L'atmosfera resta una sfera a parte, additiva e senza scrittura di
    profondità.
- **Strisce di pericolo sulle pareti di fondo:** 24 per ripetizione davano un
  effetto moiré. Ora sono larghe circa 10 m, a 45° vicino al foro.
- **Uragano:** il nucleo è più largo e pieno, così al centro è opaco.
