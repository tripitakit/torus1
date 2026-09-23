# Cockpit in prima persona

## Revisione: vista unica con HUD 2D (vale più del resto del documento)

Dopo l'implementazione l'utente ha rinunciato ai tre schermi. Il progetto in
vigore è questo:

- **Una sola camera** (`PilotCamera`, figlia diretta di `Cockpit`) all'occhio
  del pilota, `(0, 0.5, -8)` nel sistema della navetta. Vede il mondo a tutto
  schermo.
  - Campo visivo orizzontale 90° (`keep_aspect = KEEP_WIDTH`). Su 16:9 fa
    circa 59° in verticale.
  - `near = 2`, `far = 69496000`.
  - `cull_mask` = tutti i livelli tranne `SHIP_EXTERIOR_LAYER` (4), così non
    vede le sferette delle luci di navigazione.
- **Perché 90° e non 120°:** con una proiezione prospettica piatta, a 120° un
  oggetto sul bordo appare 4 volte più largo che al centro; a 90°, 2 volte.
  Le linee restano dritte. Una correzione Panini in post-processing
  permetterebbe 120° con bordi naturali: è un possibile pezzo successivo.
- **HUD 2D sovrapposto:** un `CanvasLayer` (`Hud`) con un `PanelContainer`
  (`Panel`) in alto a sinistra, a 24 px dai bordi, sfondo scuro
  semitrasparente, 7 righe di testo ciano (`Lines`). Stessi testi e stessa
  `update_hud(speed, distances)` di prima.
- **Schermo intero:** `display/window/size/mode = 3` in `project.godot`.
- **Tolti:** schermi laterali e centrale, `SubViewport`, camere esterne,
  `RemoteTransform3D`, cornici, plancia, luce interna, pannello HUD 3D,
  `scripts/cockpit_layout.gd` e il livello `COCKPIT_LAYER` (con le maschere
  delle luci che servivano a proteggerlo).
- **Restano:** i sei sensori di distanza, `cockpit_hud_format.gd`, la
  rimozione del modello e della `ChaseCamera`.

Le sezioni sotto su livelli, geometria degli schermi, nodo `Cockpit` e
dimensioni descrivono il primo progetto e restano solo come storia.

## Contesto

Oggi il giocatore vede il void-cruiser da fuori: una `ChaseCamera` figlia di
`VoidCruiser` (in `scenes/torus1_system.tscn`) inquadra il modello
`assets/models/void_cruiser.glb`, caricato da `build_ship_mesh()` in
`scripts/void_cruiser.gd`.

Questo pezzo cambia il punto di vista: il modello sparisce, il giocatore sta
dentro la navetta e vede il mondo attraverso gli schermi di un abitacolo.
Fisica, controlli, collisioni, fari e luci di navigazione non cambiano.

## Decisioni prese con l'utente

- **Cockpit 3D vero**, non un layout 2D: un abitacolo 3D intorno alla camera
  del pilota, con pannelli 3D che mostrano le immagini delle camere esterne.
- **Tre schermi:** uno grande al centro (vista frontale) e due laterali,
  inclinati fisicamente di 30° verso il pilota.
- **Panorama continuo:** le tre camere esterne si toccano ai bordi. Nessun
  angolo cieco davanti; non si vede dritto di lato.
- **HUD su un pannello del cockpit** (un quarto schermo sulla plancia), non
  sovrapposto in 2D.
- **Abitacolo generato nel codice** (approccio A), come la stazione. Un
  abitacolo modellato in Blender può sostituirlo più avanti senza toccare
  schermi, camere, sensori e HUD, perché sono nodi separati.

## Scope

Dentro:
- Rimozione del modello navetta (`build_ship_mesh`, `SHIP_MODEL_PATH`, i due
  test relativi, i file `void_cruiser.glb` e `.glb.import`) e della
  `ChaseCamera` dalla scena.
- Abitacolo procedurale: tre schermi con cornice, plancia, pannello HUD, luce
  interna.
- Tre camere esterne che disegnano in texture mostrate sugli schermi.
- Camera del pilota fissa dentro l'abitacolo.
- Sei sensori di distanza sulle facce dello scafo.
- HUD con velocità e le sei distanze.

Fuori (pezzi successivi):
- Abitacolo modellato in Blender.
- Guardarsi intorno con la testa (il mouse continua a ruotare la navetta).
- Altri strumenti sull'HUD (orientamento, gravità, carburante, ecc.).
- Il bug aperto "collisioni inattese / teletrasporto dopo l'urto": indagine
  separata, già avviata con log di debug. Questo pezzo non lo tocca.

## Architettura

### Livelli di visibilità

Godot decide cosa vede ogni camera tramite i "livelli" (bit) di ogni mesh e
la `cull_mask` di ogni camera. Tre gruppi:

| Livello | Valore bit | Contenuto | Chi lo vede |
|---|---|---|---|
| 1 | `1` | mondo (stazione, pianeta) | camere esterne |
| 2 | `2` | abitacolo (`COCKPIT_LAYER`) | solo camera pilota |
| 3 | `4` | esterno navetta: sfere delle luci di navigazione (`SHIP_EXTERIOR_LAYER`) | nessuna camera di bordo |

- Camere esterne: `cull_mask = 0xFFFFF & ~(COCKPIT_LAYER | SHIP_EXTERIOR_LAYER)`.
- Camera pilota: `cull_mask = COCKPIT_LAYER`. Vede solo l'abitacolo; il mondo
  le arriva dagli schermi.

Le costanti dei livelli stanno in `scripts/cockpit.gd`. `void_cruiser.gd` le
legge da lì per le sfere delle luci di navigazione.

### Geometria dell'abitacolo (pura, testabile)

Nuovo file `scripts/cockpit_layout.gd` (`RefCounted`, solo funzioni
statiche):

- `compute_side_screen_transform(center_width, side_width, screen_distance, tilt_degrees, side) -> Transform3D`
  (`side = -1` sinistra, `+1` destra). Lo schermo laterale è "incernierato"
  al bordo dello schermo centrale: il suo bordo interno coincide con il bordo
  esterno dello schermo centrale. È ruotato di `tilt_degrees` verso il
  pilota.
- `compute_side_camera_hfov_degrees(center_width, side_width, center_hfov_degrees) -> float`:
  il campo visivo orizzontale della camera laterale. Alla giuntura un punto
  compare alla stessa altezza sui due schermi solo se
  `larghezza / sin(campo visivo / 2)` è uguale per entrambi. Lo schermo
  laterale è più stretto, quindi la sua camera ha un campo visivo più
  stretto: `2 * asin(sin(30°) * 0.9 / 1.6) ≈ 32,7°`.
- `compute_side_camera_yaw_degrees(center_hfov_degrees, side_hfov_degrees, side) -> float`:
  ritorna `-side * (center_hfov + side_hfov) / 2`, cioè ≈ ±46,3°. L'immagine
  laterale comincia esattamente dove finisce quella frontale.

Nota: l'inclinazione fisica del pannello (30°) e la rotazione della camera
(46,3°) sono due cose separate. La prima decide dove sta lo schermo
nell'abitacolo. La seconda decide cosa mostra.

Correzione dopo la review finale: la prima versione dava a tutte e tre le
camere 60° di campo visivo e ruotava le laterali di ±60°. Le immagini si
toccavano in orizzontale, ma alla giuntura l'immagine "saltava" in altezza
(lo stesso punto finiva a 0,34 m sullo schermo centrale e a 0,19 m su quello
laterale). Con i valori sopra il panorama è continuo anche in altezza. Costo:
la vista copre ±62,7° invece di ±90°. Per una vista più larga servirebbero
schermi laterali grandi quanto quello centrale.

### Formattazione HUD (pura, testabile)

Nuovo file `scripts/cockpit_hud_format.gd` (`RefCounted`, solo funzioni
statiche):

- `format_speed(speed) -> String`: `"%d m/s"` con arrotondamento.
- `format_distance(distance) -> String`: `"—"` se `distance < 0` (nessuna
  superficie entro portata); `"%d m"` sotto i 1000 m; `"%.1f km"` da 1000 m
  in su.

### Sensori di distanza (sulla navetta)

In `scripts/void_cruiser.gd`:

- `HULL_SIZE := Vector3(15.0, 7.5, 30.0)`, usata anche da
  `build_collision_shape()` (oggi il valore è scritto a mano lì).
- `SENSOR_RANGE := 20000.0` (20 km).
- `SENSOR_DIRECTIONS`: `bow` (prua, -Z), `stern` (poppa, +Z), `port`
  (sinistra, -X), `starboard` (destra, +X), `dorsal` (dorso, +Y), `ventral`
  (ventre, -Y).
- `build_proximity_sensors()`: un `RayCast3D` per direzione, chiamato
  `Sensor<Nome>` (es. `SensorBow`), posizionato al centro della faccia
  corrispondente del box di collisione, con
  `target_position = direzione * SENSOR_RANGE`. Il raggio ignora la navetta
  stessa (`exclude_parent`, attivo di default).
- `read_proximity_distances() -> Dictionary`: per ogni direzione, la distanza
  fra la faccia dello scafo e il punto colpito, oppure `-1.0` se il raggio
  non colpisce niente.

La distanza si misura quindi dallo scafo, non dal centro della navetta.
Verificato con una prova: un box a 100 m dalla prua dà esattamente `100.0`.

### Nodo `Cockpit`

Nuovo file `scripts/cockpit.gd` (`extends Node3D`). `void_cruiser.gd` lo crea
in `_ready()` come figlio `Cockpit`, in posizione `(0, 0.5, -8)` nel sistema
della navetta (l'occhio del pilota). `build()` crea:

```
Cockpit (Node3D, origine = occhio del pilota)
  ├── PilotCamera (Camera3D)          current, fov 80, near 0.05, far 10, cull_mask = COCKPIT_LAYER
  ├── CockpitLight (OmniLight3D)       luce debole che illumina solo COCKPIT_LAYER
  ├── FrontScreen / LeftScreen / RightScreen (MeshInstance3D, QuadMesh)
  │     materiale unshaded con la texture della rispettiva SubViewport
  │     └── Bezel (MeshInstance3D, BoxMesh scuro dietro lo schermo)
  ├── HudScreen (MeshInstance3D, QuadMesh)   sulla plancia, inclinato verso il pilota
  ├── Dashboard (MeshInstance3D, BoxMesh)
  ├── FrontViewport / LeftViewport / RightViewport (SubViewport)
  │     └── Camera (Camera3D)  fov orizzontale 60 (frontale) / ≈32,7 (laterali), near 2, far 69496000, cull_mask esterna
  ├── HudViewport (SubViewport)
  │     ├── Background (ColorRect)
  │     └── Lines (VBoxContainer) → SpeedLabel, BowLabel, SternLabel,
  │                                PortLabel, StarboardLabel, DorsalLabel, VentralLabel
  └── FrontCameraMount / LeftCameraMount / RightCameraMount (RemoteTransform3D)
        ruotati di 0 / ≈+46,3 / ≈-46,3 gradi, spingono la loro trasformata sulla Camera
```

Perché i `RemoteTransform3D`: una `SubViewport` interrompe la catena delle
trasformate 3D. Una camera figlia di una `SubViewport` non segue la navetta da
sola. Il `RemoteTransform3D` è figlio della navetta (tramite `Cockpit`) e
copia la propria posizione e rotazione sulla camera. Verificato con una
prova: spostando la navetta, la camera dentro la `SubViewport` la segue.

Tutte le mesh dell'abitacolo sono su `COCKPIT_LAYER` e non proiettano ombre.
Gli schermi sono "unshaded": mostrano l'immagine così com'è, senza essere
influenzati dalle luci.

`update_hud(speed: float, distances: Dictionary)` scrive i testi delle
etichette. `void_cruiser.gd` la chiama in `_process` con
`velocity.length()` e `read_proximity_distances()`. Testi:

```
VEL  1240 m/s
PRUA  820 m
POPPA  —
SX  3.1 km
DX  —
DORSO  410 m
VENTRE  —
```

### Dimensioni (punto di partenza, da tarare a vista)

| Cosa | Valore |
|---|---|
| Distanza occhio → schermo centrale | 1.6 m |
| Schermo centrale | 1.6 × 0.9 m (16:9), viewport 1280 × 720 |
| Schermi laterali | 0.9 × 0.50625 m (16:9), viewport 960 × 540, inclinati 30° |
| Pannello HUD | 0.8 × 0.5 m, viewport 512 × 320, in `(0, -0.72, -1.3)`, inclinato -30° sull'asse X |
| Camera pilota | fov verticale 80° (con finestra 16:9, ±56° orizzontali: ci stanno tutti gli schermi) |
| Camere esterne | fov orizzontale 60° la frontale, ≈32,7° le laterali (`keep_aspect = KEEP_WIDTH`), rapporto 16:9 per tutte |

Il campo visivo delle camere laterali dipende dalla larghezza degli schermi
(vedi `compute_side_camera_hfov_degrees`). Così il panorama è continuo alle
giunture anche se gli schermi laterali sono fisicamente più piccoli.

`near = 2` per le camere esterne (la vecchia `ChaseCamera` usava 10).
L'occhio è a 7 m dalla faccia di prua: con 10 m, una superficie a contatto
con la prua sparirebbe.

### Scena

- Si toglie il nodo `ChaseCamera` da `scenes/torus1_system.tscn`.
- La camera attiva diventa `PilotCamera`, creata dal codice.
- `TopDownCamera` resta com'è (non attiva).

## Testing

- `cockpit_layout.gd`: il bordo interno di ogni schermo laterale coincide con
  il bordo dello schermo centrale; gli schermi guardano verso il pilota;
  segni corretti a sinistra e a destra; rotazione delle camere laterali pari
  al campo visivo.
- `cockpit_hud_format.gd`: stringhe esatte per velocità, distanza assente,
  metri, chilometri, soglia dei 1000 m.
- Sensori (fuori scena): sei `RayCast3D` con nome, posizione e
  `target_position` attesi.
- Sensori (in scena, con frame fisici reali, come
  `tests/test_torus_station_physics.gd`): un ostacolo a distanza nota davanti
  alla prua dà quella distanza; dietro, dove non c'è niente, dà `-1`.
- `Cockpit` (fuori scena): struttura dei nodi, livelli, `cull_mask`,
  impostazioni delle camere, ogni schermo usa la texture della sua viewport,
  ogni `RemoteTransform3D` punta alla sua camera, `update_hud` scrive i testi
  attesi.
- `Cockpit` (in scena): spostando e ruotando la navetta, le camere esterne
  seguono l'occhio del pilota e la camera sinistra guarda a sinistra.
- Scena: `VoidCruiser` non ha più `ChaseCamera`.
- Navetta: nessun metodo `build_ship_mesh`, nessun file `void_cruiser.glb`.

## Verifica

Via Godot MCP: `run_project` + `get_debug_output`, nessun errore nuovo.
Il risultato visivo (schermi leggibili, panorama continuo, colori corretti,
HUD leggibile) va controllato dall'utente in gioco: il MCP di Godot non fa
screenshot.

## Rischi noti

- **Colori degli schermi:** una texture di viewport mostrata su una mesh 3D
  può apparire slavata o troppo scura, a seconda di come il renderer gestisce
  lo spazio colore. Se succede, si attiva `albedo_texture_force_srgb` sul
  materiale degli schermi (una riga).
- **Costo di rendering:** da 1 a 4 rendering del mondo per frame, ognuno con
  le ombre del sole. Se il frame rate cala, si abbassa la risoluzione delle
  viewport laterali.
- **Navetta a contatto:** se lo scafo compenetra appena una superficie, il
  raggio parte da dentro la forma e non la colpisce: il sensore mostra "—".
  Accettabile per ora.
