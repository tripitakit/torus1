# Collisioni navicella ↔ stazione

## Contesto

Il void-cruiser (`scripts/void_cruiser.gd`) è oggi un `Node3D` che aggiorna
`position` a mano ogni tick fisico (`position += velocity * delta`), senza
alcuna interazione con il motore fisico di Godot. Le sezioni e i ponti della
stazione (`scripts/torus_station.gd`) sono `MeshInstance3D` nude, senza forme
di collisione. La navicella attraversa la geometria della stazione senza
alcun impedimento.

Questo era esplicitamente fuori scope nel design originale del void-cruiser
("Collisione/evitamento con la geometria della stazione" tra i "pezzi
successivi", vedi `2026-09-22-void-cruiser-design.md`). Questo pezzo lo porta
dentro.

## Scope

Dentro:
- La navicella non attraversa più sezioni e ponti: alla collisione rimbalza
  (riflessione della velocità sulla normale d'impatto, con perdita di
  energia).
- Le sezioni continuano a ruotare per la gravità artificiale anche con la
  forma di collisione attiva.

Fuori (pezzi successivi):
- Danni, effetti sonori/particellari all'impatto.
- Risposta di rollio/beccheggio dall'urto (il rimbalzo tocca solo la
  velocità lineare, non quella angolare).
- Collisione con il pianeta (non pertinente: la navicella opera in orbita,
  lontana dalla superficie).

## Architettura

### Navicella: `Node3D` → `CharacterBody3D`

`void_cruiser.gd` estende `CharacterBody3D` invece di `Node3D`. Aggiunge un
`CollisionShape3D` figlio con un `BoxShape3D` di dimensioni `(15, 7.5, 30)`,
la bounding box dello scafo già nota dal modello.

Il calcolo di velocità/rotazione (`VoidCruiserPhysics.compute_new_velocity`,
`compute_new_angular_velocity`) resta identico, non tocca questo pezzo.
Cambia solo come lo spostamento viene applicato al nodo:

- **In gioco reale** (`_physics_process`, nodo dentro l'albero con uno
  spazio fisico attivo): `move_and_collide(velocity * delta)`. Fa una
  scansione continua lungo il movimento (non un controllo a posizione fissa
  dopo il fatto), quindi rileva la collisione anche a velocità alta — fino a
  ~2160 m/s con la rampa di spinta al 10x, che in un tick a 60Hz sono ~36m,
  comparabili alla lunghezza della navicella stessa.
- Se `move_and_collide` riporta una collisione, la velocità diventa
  `VoidCruiserPhysics.compute_bounce_velocity(velocity, normal, collision_restitution)`.

### Rimbalzo: nuova funzione pura in `void_cruiser_physics.gd`

```gdscript
static func compute_bounce_velocity(velocity: Vector3, normal: Vector3, restitution: float) -> Vector3:
	return velocity.bounce(normal) * restitution
```

`Vector3.bounce(normal)` è la riflessione geometrica esatta
(`v - 2*(v·n)*n`), nessuna reinvenzione. `restitution` scala l'energia
residua dopo l'urto — non è un fatto fisico ricavabile, è una scelta di
"sensazione" di gioco come `thrust_power`/`linear_damping`, quindi un
`@export`:

```gdscript
@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4
```

0.4 è un punto di partenza (rimbalzo percettibile ma non un respingente da
flipper), da tarare provandolo come gli altri parametri di volo.

### Precisazione post-review: `move_and_collide` NON è testabile in modo sincrono, ma LO È con un frame reale

Verifica iniziale (script di prova headless, sincrono): chiamare
`move_and_collide` su un `CharacterBody3D` creato con `.new()` e mai
aggiunto a un albero — il pattern usato da **tutti** i test esistenti in
questo progetto prima di questo pezzo (`extends SceneTree`, `_init()`
sincrono, nodi mai aggiunti alla scena reale) — fallisce silenziosamente:
Godot stampa `ERROR: Parameter "body->get_space()" is null.` e la chiamata
ritorna `null` senza spostare il nodo. Aggiungere il nodo a `root` dentro lo
stesso `_init()` non basta: `is_inside_tree()` risulta comunque `false`
finché non viene processato un vero frame.

**Questa prima verifica era incompleta, corretta durante la review finale
di questo piano.** Uno script `SceneTree` che usa `_initialize()` invece di
`_init()`, e fa `await process_frame` / `await physics_frame` prima di
`quit()`, fa processare un vero frame: il nodo entra davvero nell'albero,
lo spazio fisico si aggancia, e `move_and_collide` funziona normalmente.
Verificato in modo indipendente (non solo fidandosi della review): vedi
`tests/test_torus_station_physics.gd`, che con questa tecnica ha scoperto
due bug reali introdotti da questo stesso pezzo (vedi sezione successiva).
La tecnica ha le sue insidie — va disattivato il `_process()` automatico
del nodo sotto test se si vogliono contare a mano le chiamate (altrimenti
il ciclo reale del motore le duplica), e va confrontata la *basis* prima/dopo
invece dell'angolo di Eulero grezzo se il nodo parte da un orientamento non
identità (l'estrazione di Eulero è ambigua per rotazioni composte).

Nonostante questo, per lo spostamento della navicella si mantiene la
struttura descritta sotto, perché resta la scelta più semplice e non
comporta nessun costo aggiuntivo:

- La logica di `_apply_physics_step` (calcolo di velocità/rotazione) resta
  invariata e testabile esattamente come prima: i test esistenti (sincroni,
  off-tree) continuano a passare senza modifiche.
- Lo spostamento vero e proprio si divide in un nuovo metodo `_move(delta)`
  che sceglie il percorso in base a `is_inside_tree()`: `move_and_collide` +
  rimbalzo quando il nodo è davvero in scena (gioco reale — `is_inside_tree()`
  è sempre vero lì, perché `_physics_process` gira solo su nodi
  effettivamente nell'albero), altrimenti il vecchio
  `position += velocity * delta` (usato dai test sincroni esistenti, che non
  mettono mai il cruiser in un albero). Non è un ramo "solo per i test": è
  la stessa guardia che Godot stesso usa internamente (vedi l'errore sopra).
- `compute_bounce_velocity` è testata direttamente (funzione pura,
  deterministica) **e** il comportamento reale di collisione è ora testato
  con un frame reale in `tests/test_torus_station_physics.gd` — non era vero
  che questo aspetto restasse strutturalmente non verificabile.

### Sezioni e ponti: forme di collisione condivise

Le sezioni ruotano di continuo (`_rotate_sections`, ogni frame, per la
gravità artificiale) — Godot sconsiglia di muovere un `StaticBody3D` ogni
frame (segnala al motore fisico "non mi muoverò mai", perdendo
un'ottimizzazione se lo si fa comunque); il tipo pensato apposta per corpi
cinematici animati ma non simulati è `AnimatableBody3D`. I ponti invece non
ruotano mai (confermato da `_test_rotate_sections_does_not_rotate_bridges`
già esistente) e restano `StaticBody3D`.

Oggi `Section%d` e `Bridge%d` SONO la `MeshInstance3D` (la mesh è
direttamente sul nodo). Diventano body con due figli:

```
Section%d (AnimatableBody3D)
  ├── Mesh (MeshInstance3D)       — mesh/material_override, come oggi
  ├── Collision (CollisionShape3D) — CylinderShape3D condivisa
  └── Stripe (MeshInstance3D)     — invariato, resta figlio diretto del body

Bridge%d (StaticBody3D)
  ├── Mesh (MeshInstance3D)
  └── Collision (CollisionShape3D) — CylinderShape3D condivisa
```

Le forme di collisione sono **condivise** fra tutte le istanze (una
`CylinderShape3D` per tutte le ~2000 sezioni, una per tutti i ~2000 ponti),
stesso schema già usato per mesh e materiali — nessun impatto di memoria
aggiuntivo. Dimensioni: sezione `radius = section_radius`,
`height = section_length` (stesse della mesh visiva); ponte
`radius = section_radius * 0.3`, `height = bridge_length` (calcolata
dinamicamente, come già avviene per `bridge_mesh`).

Questo è un cambio di struttura: i test esistenti che leggono
`station.get_node("Section0")` aspettandosi direttamente una
`MeshInstance3D` (`.mesh`, `.material_override`) vanno aggiornati per
scendere a `.get_node("Mesh")`. I test su trasformata/rotazione
(`.transform`, `.transform.basis`) restano validi as-is: il body ha la sua
stessa transform di prima, non cambia nulla lì.

## Testing

- `compute_bounce_velocity`: riflessione pura, testata con normali/velocità
  note (perpendicolare, radente, con vari `restitution` incluso 0 e 1).
- Struttura: `Section0`/`Bridge0` hanno un `CollisionShape3D` con la shape
  giusta (tipo, `radius`, `height`); la shape è la stessa risorsa condivisa
  fra istanze diverse (stesso pattern di `_test_sections_share_one_mesh_resource`).
- Struttura: `VoidCruiser` ha un `CollisionShape3D` con un `BoxShape3D`
  delle dimensioni attese.
- Tutti i test di `_apply_physics_step` esistenti restano invariati (nessuna
  modifica al loro comportamento off-tree).
- **Non testato in automatico**: che una collisione reale in gioco venga
  effettivamente rilevata e produca un rimbalzo visibile — richiede un
  frame fisico reale che questo harness di test non processa. Verifica
  manuale in gioco, a cura dell'utente.

## Verifica

Via Godot MCP: `run_project` + `get_debug_output`, nessun errore nuovo
all'avvio. La verifica del comportamento di collisione vero e proprio
(la navicella rimbalza toccando una sezione/ponte) richiede pilotare la
navicella — non disponibile via MCP, a carico dell'utente.
