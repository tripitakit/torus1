# Accesso all'interno della stazione (pezzo A)

## Contesto

Oggi il giocatore vola fuori dalla stazione con il void-cruiser (vista in
prima persona, HUD 2D). Sezioni e bridge sono solidi: per la fisica sono
prismi convessi pieni (`scripts/torus_station.gd`), scelta fatta per
correggere il bug del "teletrasporto" (vedi
`tests/test_torus_station_physics.gd`).

L'utente vuole poter entrare nelle sezioni, volarci dentro e attraversare i
bridge, con terreno, edifici, campi, strade e acqua. Il lavoro è diviso in tre
pezzi, ognuno con spec e piano propri:

- **A (questo documento):** attracco, cambio di navetta, interno di un bridge e
  delle due sezioni che collega, terreno nudo, luci sull'asse.
- **B:** terreno procedurale (campi, strade, acqua, edifici).
- **C:** viaggio continuo verso le sezioni successive.

## Decisioni prese con l'utente

- **Attracco:** ti avvicini alla docking station; quando sei abbastanza vicino
  e lento, l'HUD mostra `DOCK  [F]`; premi F.
- **Internal-cruiser:** stessi comandi del void-cruiser, più lento, senza
  rampa di spinta, **senza gravità**, **senza HUD**.
- **Luci:** un "sole" artificiale circa ogni km lungo l'asse di ogni sezione,
  sempre acceso.
- **Architettura:** l'interno è un **mondo separato** (approccio 1), non le
  sezioni vere rese cave.
- **Docking station:** un **anello che non ruota** attorno al centro di ogni
  bridge, con la porta d'attracco.

## Scope

Dentro:
- Anello d'attracco fermo su ognuno dei bridge, con porta luminosa.
- Condizione di attracco, riga `DOCK  [F]` sull'HUD, tasto F.
- Cambio di mondo con dissolvenza, in entrata e in uscita, conservando lo
  stato del mondo esterno.
- Mondo interno: tubo del bridge, due sezioni, pareti di fondo, terreno nudo
  diviso in blocchi, soli sull'asse, luci nel bridge, dock interno con
  cartello.
- Internal-cruiser.

Fuori (pezzi successivi):
- Contenuto del terreno (pezzo B).
- Sezioni oltre le due collegate dal bridge; il portellone nella parete di
  fondo lontana resta chiuso (pezzo C).
- Suoni, ciclo giorno/notte, gravità sulla navetta, animazione di attracco.
- La piega di 0,18° fra sezioni consecutive: l'interno è costruito dritto.

## Architettura

### Regole di attracco (pure)

`scripts/docking_rules.gd`:

- `DOCK_RANGE := 150.0` m, `DOCK_MAX_SPEED := 20.0` m/s.
- `can_dock(distance, speed) -> bool`: vero se `distance <= 150` e
  `speed <= 20`. La stessa regola vale per entrare (distanza dalla porta
  esterna) e per uscire (distanza dalla piattaforma interna).

`scripts/torus_geometry.gd`:

- `compute_nearest_bridge_index(station_local_position, num_sections) -> int`:
  dall'angolo attorno all'anello (`atan2(z, x)`) ricava il bridge più vicino.
  Il bridge `i` sta all'angolo `i * step + step / 2`. Serve a trovare la porta
  giusta senza scorrere tutti i 2000 anelli a ogni frame.

### Anelli d'attracco (sulla stazione)

In `scripts/torus_station.gd`, per ogni bridge un `StaticBody3D` chiamato
`DockingCollar%d`, figlio della stazione, con la stessa trasformata del bridge.

- Non si chiama `Section…` né `Bridge…`, quindi `_rotate_sections` non lo fa
  girare. È un `StaticBody3D` e segue gli spostamenti del genitore
  (rebase dell'origine): verificato con una prova.
- `Mesh`: un `TorusMesh` condiviso. Raggio interno `1,05 ×` il raggio del
  bridge, esterno `1,25 ×` (630 e 750 m a piena scala). L'asse del toro è la
  Y locale, come quella del bridge.
- `Collision`: forma triangolare ricavata dalla stessa mesh
  (`create_trimesh_shape()`), condivisa. Niente forme "matematiche" come il
  cilindro che causava il teletrasporto; un test lo verifica.
- `Port`: un `Node3D` sulla faccia esterna dell'anello, nella direzione X
  locale (che per la stazione è il "su"), con una piattaforma `Platform` verde
  luminosa. Solo materiale emissivo, **nessuna luce vera**: 2000 luci in più
  costerebbero troppo.
- Le dimensioni della porta sono proporzionali al raggio del bridge, così i
  test con la stazione piccola restano sensati.
- `build_station()` cancella e ricostruisce anche gli anelli.
- Nuovi metodi: `get_bridge_radius()`, `get_bridge_length()`,
  `nearest_bridge_index(world_position)`, `get_docking_port(index)`.

### Disposizione del mondo interno (pura)

`scripts/interior_layout.gd`. Il bridge sta al centro dell'origine con l'asse
lungo Z. La sezione "davanti" (`side = -1`) è verso -Z, quella "dietro"
(`side = +1`) verso +Z.

- `section_center_z(bridge_length, section_length, side)`.
- `sun_positions(center_z, section_length, spacing)`: 20 soli per sezione, a
  metà di ogni km.
- `cylinder_point(radius, angle, z)`: un punto sulla parete del cilindro.
- `count_lights_reaching_band(radius, z0, z1, lights)`: quante luci sull'asse
  (posizione z, portata) raggiungono una fascia della parete. Serve a
  garantire il limite del renderer: **al massimo 8 luci per oggetto**.

### Mondo interno

`scripts/interior_world.gd` (`Node3D`), costruito da codice con
`build()`. Parametri presi dalla stazione: raggio e lunghezza delle sezioni,
raggio e lunghezza del bridge.

```
InteriorWorld
  ├── SectionAhead / SectionBehind (Node3D)
  │     ├── Chunk_AA_LL (StaticBody3D) × 16 attorno × 20 lungo
  │     │     ├── Mesh       blocco di terreno, mesh condivisa
  │     │     └── Collision  forma triangolare condivisa
  │     ├── NearCap (StaticBody3D)  anello da r_bridge a r_sezione, verso il bridge
  │     ├── FarCap  (StaticBody3D)  disco pieno (portellone chiuso)
  │     └── Sun_00 … Sun_19 (Node3D) → Globe (sfera emissiva 30 m) + Light (OmniLight3D)
  ├── BridgeTube (Node3D) → Segment_0 … Segment_3 (StaticBody3D, Mesh + Collision)
  ├── BridgeLight_0 … BridgeLight_2 (OmniLight3D)
  └── Dock (Node3D) → Platform (StaticBody3D), Light (OmniLight3D verde), Sign (Label3D)
```

- **Terreno:** la parete interna del cilindro a 2000 m dall'asse, livello 0.
  Un blocco copre 1/16 di giro per 1 km. Tutti i blocchi sono uguali, quindi
  una sola mesh e una sola forma di collisione, ruotate e spostate. Le normali
  guardano verso l'asse. Materiale: colore terra/erba, niente texture (arriva
  con il pezzo B).
- **Pareti di fondo:** quella verso il bridge ha il foro di 600 m, quella
  lontana è piena. Guardano dentro la sezione.
- **Soli:** `OmniLight3D` calda, portata 2600 m (arriva al terreno a 2000 m),
  **niente ombre**, più una sfera emissiva visibile. Energia e colore da
  tarare a vista.
- **Bridge:** tubo da 600 m di raggio diviso in 4 tratti (per il limite di
  luci), con 3 luci più piccole (portata 900 m) sull'asse.
- **Limite di luci:** con queste portate ogni blocco di terreno riceve al
  massimo 5 soli e ogni tratto di tubo al massimo 7 luci sull'asse. Resta un
  posto per la luce del dock. Un test lo verifica.
- **Dock interno:** piattaforma sul fondo del tubo (angolo -90°), luce verde,
  cartello `UNDOCK  [F]` (`Label3D`, sempre rivolto alla camera). Il cartello è
  grigio, e diventa verde quando `can_dock` è vero. È l'unica indicazione:
  dentro non c'è HUD.
- **Punto di partenza:** 24 m sopra la piattaforma, prua verso -Z (la sezione
  davanti), "su" verso l'asse.

### Base comune delle navette

La logica di volo del void-cruiser (lettura comandi, fisica, movimento con
rimbalzo) passa in `scripts/flying_craft.gd` (`CharacterBody3D`). Il
void-cruiser la estende e aggiunge rampa, luci, sensori e cockpit. È un puro
spostamento di codice: i test esistenti del void-cruiser devono restare verdi.

### Internal-cruiser

`scripts/internal_cruiser.gd` estende `flying_craft.gd`:

- Scafo 4 × 2 × 8 m.
- Spinta 70: con lo smorzamento 0,5 la velocità massima è
  `70 / ln 2 ≈ 101 m/s`.
- Niente rampa; stessa sensibilità del mouse del void-cruiser.
- Camera `Camera` in prima persona, 90° orizzontali, attiva. Nessun HUD.

### Modalità di gioco

`scripts/game_mode.gd`, nodo `GameMode` nella scena principale.

- **Fuori:** a ogni frame trova la porta del bridge più vicino e chiede a
  `can_dock`. Il risultato accende o spegne la riga `DOCK  [F]` del cockpit
  (`set_dock_prompt`).
- **Dentro:** a ogni frame aggiorna il cartello del dock interno
  (`set_undock_ready`).
- **Tasto F** (nuova azione `dock`): se la regola lo permette, avvia la
  transizione.
- **Transizione:** dissolvenza al nero (0,4 s), cambio, dissolvenza di ritorno
  (0,4 s). Durante la transizione F è ignorato.
- **Entrata:** toglie dall'albero tutti i fratelli tranne `WorldEnvironment`
  (stazione, pianeta, sole, void-cruiser, rebase), senza distruggerli.
  Costruisce il mondo interno con l'internal-cruiser al punto di partenza.
- **Uscita:** distrugge il mondo interno e rimette i fratelli nello stesso
  ordine. Il void-cruiser riappare fermo a 60 m dalla porta, prua verso
  l'esterno.
- Mentre sei dentro, il mondo esterno è fermo (stazione ferma, niente
  rebase); riparte da dove era.

## Testing

- `docking_rules.gd`: casi dentro, fuori e sul limite di distanza e velocità.
- `compute_nearest_bridge_index`: angoli dei bridge, poco prima e poco dopo
  una sezione, giro completo.
- Stazione: un anello per bridge, stessa trasformata, raggi, forma
  triangolare, risorse condivise, porta nella posizione giusta; gli anelli non
  girano con `_rotate_sections`; nessuna perdita alla ricostruzione; metodi
  nuovi.
- Con frame reali: navetta ferma che ruota appoggiata all'anello (nessuna
  spinta oltre 2 m per tick).
- `interior_layout.gd`: posizioni, soli, punti sul cilindro, limite di luci su
  tutti i blocchi e tratti di tubo.
- Mondo interno: struttura, 320 blocchi per sezione con risorse condivise,
  vertici a 2000 m e normali verso l'asse, pareti di fondo aperta e chiusa
  con il verso giusto, soli, tubo, dock, cartello.
- Con frame reali: navetta ferma che ruota appoggiata al terreno (nessuna
  spinta); l'internal-cruiser rimbalza sul terreno; non attraversa la parete
  di fondo.
- Void-cruiser: la classe base è `flying_craft.gd`, e tutti i test di volo
  restano verdi.
- Internal-cruiser: camera, nessun HUD, scafo, velocità massima ≈ 101 m/s.
- Cockpit: riga `DOCK  [F]` nascosta di default, mostrata da
  `set_dock_prompt(true)`.
- Scena: `GameMode` presente e collegato; azione `dock` sul tasto F.
- Con la scena vera: prompt acceso e spento con distanza e velocità; F lontano
  non fa nulla; F vicino fa entrare; F al dock interno fa uscire, con il
  void-cruiser a 60 m dalla porta, fermo, prua verso l'esterno.

## Verifica

Avvio del gioco senza errori. L'aspetto (luci, sensazione di volo, cartello)
lo giudica l'utente in gioco.

## Rischi noti

- **Luci:** se in gioco un blocco risulta illuminato "a macchie", il limite di
  8 luci è stato superato da qualche parte. Il test sul conteggio copre solo
  le luci sull'asse.
- **Costo degli anelli:** 2000 corpi statici in più con forma triangolare. Se
  l'avvio o il frame rate peggiorano, gli anelli si possono costruire solo
  vicino alla navetta.
- **Precisione della forma triangolare contro la navetta che ruota:** coperta
  dai test "nessuna spinta", sull'anello e sul terreno.
