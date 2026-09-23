# Floating origin — correzione jitter di rendering a scala Luna

## Contesto

Dopo aver portato pianeta, stazione e navicella a scala Luna (vedi
`2026-09-22-static-station-design.md` e le modifiche successive), la
navicella renderizzata mostra un fastidioso tremolio fine sui bordi della
mesh, presente anche da ferma. Investigazione (vedi processo di debug in
sessione): causa confermata dalla documentazione ufficiale Godot — anche
con build a doppia precisione, la GPU renderizza sempre in float32 (limite
hardware). A distanze dell'ordine dei milioni di metri dall'origine della
scena, il float32 non rappresenta con continuità le posizioni: ogni frame
la geometria scatta sul valore rappresentabile più vicino.

Fonti:
- https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- https://godotengine.org/article/emulating-double-precision-gpu-render-large-worlds/

La stazione è un anello di raggio ~6.95 milioni di metri: non esiste un
singolo punto "vicino all'origine" che copra l'intero anello, quindi la
correzione richiede ricentrare periodicamente lo spazio locale su dove si
trova la navicella (floating origin / origin shifting), non solo uno
spostamento una tantum.

## Scope

Dentro:
- Riorganizzazione della scena per raggruppare pianeta+stazione (+camera
  di riferimento dall'alto) in un unico nodo spostabile
- Riposizionamento iniziale: la navicella parte all'origine locale, il
  gruppo pianeta/stazione assorbe l'offset grande
- Meccanismo di rebase periodico a runtime basato su una soglia di
  distanza dall'origine locale

Fuori:
- Tracciamento di una "posizione vera" assoluta in doppia precisione per
  telemetria/HUD (non esiste ancora nessuna UI che ne abbia bisogno;
  banale da aggiungere in futuro se serve, vedi Note)
- Streaming/caricamento dinamico delle sezioni (tutte le 2000 sezioni
  esistono già come nodi statici nella scena, generati una volta sola)

## Perché funziona senza tracciare una posizione assoluta

Tutta la logica esistente lavora già in coordinate locali/relative:
- `torus_station.gd` genera le sezioni come trasformate locali rispetto a
  se stesso (`build_station`), e le ruota localmente
  (`rotate_object_local`) — indipendente da dove il nodo stesson si trovi
  nell'albero
- `void_cruiser.gd` integra la velocità come `position += velocity * delta`
  — puramente relativo, non dipende dal valore assoluto della posizione

Uno spostamento rigido uguale e contemporaneo di navicella e gruppo
pianeta/stazione preserva esattamente ogni posizione *relativa*
(nave-stazione, sezioni fra loro): cambia solo la loro rappresentazione in
coordinate locali. Non serve quindi nessun sistema di doppia
rappresentazione (locale + assoluta) per la logica di gioco attuale.

## Architettura

**Riorganizzazione scena** (`torus1_system.tscn`):
- Nuovo nodo `PlanetSystem` (Node3D), figlio della radice
- `Planet`, `TorusStation`, `TopDownCamera` diventano figli di
  `PlanetSystem` (le loro trasformate locali restano quelle attuali:
  entrambe centrate sull'origine di `PlanetSystem`)
- `VoidCruiser` resta figlio diretto della radice — è il nodo "tracciato"
  che l'origine locale insegue
- `SunLight` resta figlio diretto della radice, non tocca (la posizione di
  una `DirectionalLight3D` non ha effetto sull'illuminazione, solo la
  rotazione)

**Posizionamento iniziale**: la relazione relativa nave-pianeta approvata
in precedenza (nave a `(0, 4000, 6959600)` rispetto al centro pianeta)
resta identica, ma si inverte quale nodo porta il numero grande:
- `VoidCruiser.position = (0, 0, 0)`
- `PlanetSystem.position = (0, -4000, -6959600)`

**Rebase a runtime** — due nuovi file, stesso pattern
(funzioni-pure-più-nodo-sottile) già usato da `torus_geometry.gd` /
`torus_station.gd`:

`scripts/world_rebase.gd` (`RefCounted`, funzioni statiche pure):
- `should_rebase(tracked_position: Vector3, threshold: float) -> bool`
- `compute_rebase_offset(tracked_position: Vector3) -> Vector3` (identità:
  restituisce `tracked_position` — la funzione esiste per dare un punto di
  test/estensione esplicito, non per calcolo non banale)

`scripts/world_origin_rebase.gd` (`Node`, nodo sottile):
- Export: `tracked_node: NodePath` (punterà a `VoidCruiser`),
  `rebasing_node: NodePath` (punterà a `PlanetSystem`),
  `rebase_threshold: float = 5000.0`
- `_physics_process(delta)` chiama `_check_and_rebase()`
- `_check_and_rebase()`: risolve i due nodi, se
  `WorldRebase.should_rebase(tracked.position, rebase_threshold)` è vero,
  calcola `offset = WorldRebase.compute_rebase_offset(tracked.position)` e
  sottrae `offset` sia da `tracked.position` che da `rebasing.position`

Aggiunto alla scena come nodo `WorldOriginRebase` (`Node`), figlio della
radice, con `tracked_node = "../VoidCruiser"` e
`rebasing_node = "../PlanetSystem"`.

**Soglia**: 5000m. Alla velocità di crociera (~216 m/s, vedi tuning
precedente) scatta un rebase ogni ~23 secondi — operazione a costo
trascurabile (sposta due `Node3D.position`, non tocca le migliaia di figli
di `TorusStation`, che si spostano automaticamente con il parent).

## Cosa non cambia

Generazione delle sezioni, rotazione per gravità artificiale (0.7G),
fisica di volo, camere — nessuna di queste logiche dipende dalla
posizione assoluta nell'albero, quindi il rebase è invisibile a tutte.

## Testing

`world_rebase.gd` testato headless come le altre funzioni pure:
- `should_rebase` falso sotto soglia, vero sopra
- `compute_rebase_offset` restituisce esattamente la posizione passata

`world_origin_rebase.gd` testato come nodo, stesso pattern di
`test_torus_station.gd`: creare nodo + due `Node3D` figli fittizi
(tracked/rebasing) con NodePath relativi, chiamare `_check_and_rebase()`
direttamente e verificare le posizioni risultanti sopra/sotto soglia.

## Verifica

Via Godot MCP: `run_project` + `get_debug_output`, verificare nessun
errore nuovo. La verifica visiva del tremolio risolto richiede l'occhio
dell'utente in editor (questo server MCP non ha un tool di screenshot).

## Note

Se in futuro servisse una posizione assoluta (telemetria, HUD, salvataggio)
si può aggiungere un accumulatore `Vector3` in doppia precisione che somma
ogni `offset` di rebase — non implementato ora perché nulla lo consuma
(YAGNI).
