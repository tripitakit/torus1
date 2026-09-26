# HUD di attracco e velocità scomposte

## Contesto

Fuori dalla stazione il void-cruiser attracca a un pad su ogni bridge. Il pad
è sottile (0,3 m sopra la faccia del bridge) e si disegna solo entro 3 km:
più lontano sfarfallerebbe. Così "appare all'improvviso" e da lontano non si
trova. L'HUD mostra la velocità solo come numero (SPEED).

Questo lavoro aggiunge:
- una guida di avvicinamento (quadrati in prospettiva verso il dock);
- un faro su ogni pad, visibile da lontano;
- una croce che scompone la velocità sugli assi della navetta.

## Decisioni prese con l'utente

- **Percorso:** quadrati sulla linea retta dalla navetta alla porta del
  dock, ricalcolati a ogni frame.
- **Quando:** per il dock più vicino, entro 10 km.
- **Dock da lontano:** un faro sul pad, sempre della stessa grandezza a
  schermo, fino a 50 km.
- **Velocità:** sempre rispetto all'anello (come SPEED), scomposta sugli
  assi della navetta, mostrata come croce grafica.
- **Quadrati 3D veri nel mondo**, non disegnati sull'HUD 2D.

## Guida di avvicinamento (`scripts/approach_guide.gd`, funzioni pure)

- `gate_distances(distance)`: distanze dei quadrati dalla navetta.
  - Nessun quadrato oltre 10 km (`MAX_RANGE`).
  - Al massimo 20 quadrati; il primo a 100 m, poi a passo costante di
    distanza / 20, fra 50 e 500 m. Mai alla distanza del dock o oltre.
  - Esempi: a 10 km, 20 quadrati ogni 500 m; a 1 km, 18 quadrati ogni 50 m.
- `gate_segments(ship, port, up_hint)`: i segmenti (coppie di punti,
  relativi alla navetta) dei quadrati. Ogni quadrato è 30 × 30 m,
  perpendicolare alla linea, centrato su di essa; il "su" dei quadrati segue
  quello della navetta.
- Nella navetta: nodo `ApproachGuide` (`MeshInstance3D`, posizione
  indipendente, `ArrayMesh` a segmenti, verde semitrasparente senza luce,
  nessuna ombra). A ogni frame prende il dock più vicino
  (`nearest_bridge_index`, `get_docking_port`) dalla stazione
  (`station_path`, di base `../PlanetSystem/TorusStation`), ricostruisce la
  mesh e si mette sulla navetta. Senza stazione, o oltre 10 km, è nascosto.
- Il bridge copre i quadrati quando ci passa davanti.

## Faro (`scripts/torus_station.gd`)

- Ogni bridge ha un nodo `Beacon` sopra il centro del pad, a 20 m lungo la
  normale della faccia (in proporzione al raggio del bridge).
- `QuadMesh` di 0,02 unità, materiale condiviso senza luce, sempre rivolto
  alla camera, `fixed_size`: circa 13 pixel su uno schermo da 1280 con la
  vista a 90°, a qualsiasi distanza. Verde come il cartello del dock.
- Visibile fino a 50 km (`visibility_range_end`).
- Lampeggia: acceso 0,5 s ogni 1,5 s (`beacon_lit(time)`, pura). La stazione
  aggiorna la trasparenza del materiale condiviso a ogni frame.

## Croce delle velocità (`scripts/velocity_cross.gd`)

- `Control` nell'HUD, in basso a sinistra, 260 × 200 pixel, che non cattura
  il mouse.
- `ship_components(basis, velocity)`, pura: velocità negli assi della
  navetta come (tribordo, dorsale, avanti).
- `bar_fraction(speed)`, pura: 0 sotto 0,5 m/s, altrimenti
  log(1 + |v|) / log(1 + 100 000), al massimo 1.
- Disegno:
  - croce: asse orizzontale babordo/tribordo, verticale dorsale/ventrale;
  - a destra una barra verticale avanti/indietro;
  - assi sottili e attenuati; barre spesse dal centro verso la direzione del
    moto, con il valore (`format_speed`) in punta;
  - etichette PORT, STBD, DOR, VEN, FWD, AFT alle estremità;
  - la barra avanti/indietro è gialla quando il blocco C è attivo.
- `cockpit.update_velocity(components, cruise)` la aggiorna; la navetta la
  chiama a ogni frame.

## Fuori scope

Corridoio fisso sull'asse del dock, pilota automatico, mirino HUD sul dock,
velocità relativa al dock, suoni.

## Testing

- **`approach_guide.gd`:**
  - numero e passo dei quadrati a 10 km, 1 km e 150 m;
  - nessun quadrato oltre 10 km o sotto i 100 m;
  - i quadrati sono 30 × 30 m, perpendicolari alla linea e centrati su di
    essa.
- **Faro:**
  - ogni bridge ha il `Beacon` con mesh e materiale condivisi, sempre
    rivolto alla camera, a grandezza fissa, visibile fino a 50 km, sopra il
    centro del pad;
  - `beacon_lit` vale acceso per 0,5 s ogni 1,5 s.
- **Croce:**
  - scomposizione corretta anche con la navetta ruotata;
  - lunghezze logaritmiche (0 sotto 0,5 m/s, 1 a 100 km/s e oltre);
  - il nodo sta nell'HUD, in basso a sinistra, e riceve valori e blocco C.
- **Navetta fuori dall'albero:** la guida esiste ed è nascosta; la croce
  riceve le componenti.
- **Scena vera:**
  - a 5 km da un dock la guida è visibile, con 8 punti per quadrato, e il
    primo quadrato è centrato sulla linea verso la porta;
  - a 15 km è nascosta;
  - la guida segue la navetta dopo lo spostamento dell'origine.
- **Verifica visiva:** render offscreen (xvfb) a 3 km (quadrati e faro) e a
  30 km (solo il faro), da guardare prima di passarli all'utente.
