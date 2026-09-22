# Void-cruiser — volo libero (primo pezzo)

## Contesto

Torus1 ha già un pianeta e una stazione toroidale statica, con le sezioni
cilindriche che ruotano per gravità artificiale (vedi
`2026-09-22-static-station-design.md`). Questo pezzo introduce il
void-cruiser descritto nel rationale: una piccola navicella che vola
liberamente nello spazio attorno alla stazione, usata per navigare tra
sezioni distanti tra loro.

## Scope

Dentro:
- Fisica di volo newtoniana smorzata: spinta su 3 assi + rotazione
  (beccheggio/imbardata/rollio), con smorzamento configurabile
- Controllo da tastiera (WASD + spazio/shift per spinta) e mouse (per
  beccheggio/imbardata) + Q/E per rollio
- Camera in terza persona, fissa dietro/sopra il cruiser
- Un cruiser posizionato nella scena, vicino alla stazione

Fuori (pezzi successivi):
- Collisione/evitamento con la geometria della stazione
- Shuttle interni lungo i ponti
- HUD, indicatori di velocità/orientamento
- Più cruiser, multiplayer, AI

## Architettura

**`scripts/void_cruiser_physics.gd`** — funzioni statiche pure, nessuna
dipendenza da Node, stesso pattern di `torus_geometry.gd`:

- `compute_new_velocity(velocity: Vector3, local_thrust_input: Vector3, orientation: Basis, thrust_power: float, linear_damping: float, delta: float) -> Vector3`
  Applica prima lo smorzamento esponenziale alla velocità attuale
  (`velocity * pow(1.0 - linear_damping, delta)`), poi aggiunge
  l'accelerazione di spinta (`orientation * local_thrust_input *
  thrust_power * delta`), in coordinate mondo.
- `compute_new_angular_velocity(angular_velocity: Vector3, local_torque_input: Vector3, torque_power: float, angular_damping: float, delta: float) -> Vector3`
  Stesso schema per le velocità angolari attorno agli assi locali
  (x=beccheggio, y=imbardata, z=rollio).

`linear_damping` e `angular_damping` sono frazioni in [0, 1): quanta
velocità viene *rimossa* per secondo (0 = nessuno smorzamento, newtoniana
pura; valori vicino a 1 = si ferma quasi subito). La formula
`pow(1.0 - damping, delta)` è indipendente dal framerate.

**`scripts/void_cruiser.gd`** — `@tool`-free `Node3D`, il nodo pilotabile:

- Export: `thrust_power: float`, `linear_damping: float`,
  `torque_power: float`, `angular_damping: float`,
  `mouse_sensitivity: float`
- Stato interno: `velocity: Vector3`, `angular_velocity: Vector3`
  (entrambe iniziano a zero)
- `_unhandled_input(event)`: accumula il movimento del mouse
  (`InputEventMouseMotion.relative`) in un buffer per-frame usato dal
  beccheggio/imbardata, consumato e azzerato a ogni
  `_physics_process`
- `_physics_process(delta)`:
  1. Legge `local_thrust_input` da `Input.get_axis` (WASD +
     spazio/shift) e `local_torque_input` da mouse buffer + Q/E
  2. `velocity = VoidCruiserPhysics.compute_new_velocity(...)`
  3. `angular_velocity = VoidCruiserPhysics.compute_new_angular_velocity(...)`
  4. `global_position += velocity * delta`
  5. Applica `angular_velocity` con tre `rotate_object_local` in
     sequenza (X, Y, Z) scalati per `delta`

Questi parametri di gameplay (potenza di spinta, smorzamento, sensibilità)
sono scelte di sensazione di gioco, non costanti fisiche derivate come lo
era la velocità di rotazione delle sezioni — non c'è un valore "corretto"
da calcolare, solo un punto di partenza ragionevole da tarare dopo averlo
provato.

**Camera**: un `Camera3D` figlio diretto di `VoidCruiser`, offset fisso
dietro/sopra (es. posizione locale `(0, 5, 15)`, leggermente inclinata
verso il basso), `current = true`. Nessuno smoothing/spring-arm in questo
primo giro.

## Scena

`VoidCruiser` aggiunto a `torus1_system.tscn`, posizionato vicino
all'anello ma fuori dalla struttura (es. qualche centinaio di metri sopra
o di lato rispetto al toro, non dentro le sezioni). La sua camera diventa
quella attiva di default quando il progetto gira — sostituisce
`TopDownCamera` come vista principale, dato che ora c'è qualcosa da
pilotare. `TopDownCamera` resta nella scena per riferimento/debug ma non
più `current`.

## Testing

`void_cruiser_physics.gd` testato headless con casi numerici concreti:
- Spinta pura (damping=0): la velocità aumenta esattamente di
  `thrust_power * delta` nella direzione attesa
- Smorzamento puro (thrust=0): la velocità si riduce esattamente del
  fattore atteso
- `damping=0`: nessun errore, comportamento newtoniano puro
- `damping` vicino a 1: velocità tende a zero, nessun overshoot negativo
- `delta` grande: nessun NaN/inf

## Verifica

Pilotare il cruiser è un controllo interattivo, fatto insieme all'utente
dopo l'implementazione. La verifica automatica copre: i test numerici
sopra, e che il progetto giri senza errori via
`mcp__godot__run_project` + `get_debug_output`.
