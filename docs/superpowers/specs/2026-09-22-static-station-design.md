# Torus1 — pianeta e stazione statici (primo pezzo)

## Contesto

Torus1 è un progetto Godot che esplora la meccanica di navigazione orbitale
attorno a una base toroidale in orbita geostazionaria equatoriale (vedi
`rationale.md`). Il progetto viene costruito un pezzo alla volta. Questo è il
primo pezzo: pianeta e stazione come geometria statica, per verificare forma
e proporzioni prima di aggiungere rotazione, gravità artificiale o volo.

## Scope

Dentro:
- Sfera per il pianeta
- Anello di sezioni cilindriche + ponti longitudinali per Torus1, generato
  proceduralmente
- Verifica visiva in editor (screenshot dall'alto e ravvicinato)

Fuori (pezzi successivi):
- Rotazione delle sezioni / gravità artificiale
- Void-cruiser e shuttle interni
- Qualunque logica di gioco o fisica orbitale simulata

## Parametri geometrici

Pianeta piccolo inventato, numeri comodi da maneggiare in editor Godot
(1 unità = 1 metro):

| Parametro | Valore |
|---|---|
| Raggio pianeta | 500 m |
| Altitudine orbita geostazionaria | 1500 m |
| Raggio del toro (dal centro pianeta) | 2000 m |
| Circonferenza anello | ~12566 m |
| Raggio sezione cilindrica | 30 m |
| Lunghezza sezione cilindrica | 80 m |
| N. sezioni | ~100 |

Il numero di sezioni e la lunghezza dei ponti sono derivati dalla
circonferenza dell'anello, non hardcoded, così restano coerenti se i
parametri cambiano.

## Architettura

Scena `torus1_system.tscn`:
- `Planet` (MeshInstance3D con SphereMesh, raggio = `planet_radius`)
- `TorusStation` (Node3D) con script `torus_station.gd`

`torus_station.gd` è uno script `@tool` con export var per tutti i
parametri della tabella sopra. In editor, un pulsante ("rigenera" via
`@export_tool_button` o simile) richiama `build_station()`, che:
1. Rimuove i figli generati in precedenza (se presenti)
2. Calcola le posizioni delle N sezioni lungo il cerchio all'altitudine
   geostazionaria, orientando ogni CylinderMesh tangenzialmente
3. Genera un ponte (mesh sottile) tra ogni coppia di sezioni contigue

Essendo `@tool`, i parametri sono modificabili e il risultato visibile in
editor senza dover avviare la simulazione.

## Verifica

Via Godot MCP:
1. Aprire/creare la scena in editor
2. Generare la geometria con i parametri di default
3. Screenshot dall'alto per controllare che l'anello sia chiuso attorno al
   pianeta e le proporzioni siano sensate
4. Screenshot ravvicinato su una sezione per controllare orientamento e
   forma cilindrica

## Note

Il server MCP Godot (`~/.claude/settings.json`) è configurato per puntare a
Godot 4.6.1 (`/home/patrick/Godot_v4.6.1-stable_linux.x86_64`) invece del
default di sistema (4.5.1 via `/usr/local/bin/godot`). Va verificato che il
server risulti connesso prima di iniziare l'implementazione.
