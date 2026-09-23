# Cockpit in prima persona

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
- `compute_side_camera_yaw_degrees(horizontal_fov_degrees, side) -> float`:
  ritorna `-side * horizontal_fov_degrees`. La camera laterale è ruotata di
  un campo visivo intero rispetto a quella frontale, così i bordi delle
  immagini combaciano.

Nota: l'inclinazione fisica del pannello (30°) e la rotazione della camera
(60°) sono due cose separate. La prima decide dove sta lo schermo
nell'abitacolo. La seconda decide cosa mostra.

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
  │     └── Camera (Camera3D)  fov orizzontale 60, near 2, far 69496000, cull_mask esterna
  ├── HudViewport (SubViewport)
  │     ├── Background (ColorRect)
  │     └── Lines (VBoxContainer) → SpeedLabel, BowLabel, SternLabel,
  │                                PortLabel, StarboardLabel, DorsalLabel, VentralLabel
  └── FrontCameraMount / LeftCameraMount / RightCameraMount (RemoteTransform3D)
        ruotati di 0 / +60 / -60 gradi, spingono la loro trasformata sulla Camera
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
| Camere esterne | fov orizzontale 60° (`keep_aspect = KEEP_WIDTH`), stesso rapporto 16:9 per tutte |

Tutte le camere esterne hanno lo stesso rapporto d'aspetto e lo stesso
campo visivo. Così il panorama è continuo negli angoli, anche se gli schermi
laterali sono fisicamente più piccoli.

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
