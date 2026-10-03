# Piano: giorno/notte a fusi orari e traffico all'interno

Spec: `docs/superpowers/specs/2026-10-03-interior-day-night-and-traffic-design.md`.
Esecuzione in sessione, TDD (test prima, fallimento visto), Godot double
(`~/Godot_v4.6.1-stable-double_linux.x86_64`).

## Task 0 — Misura di partenza

- Prova GPU (`tests/zz_interior_fps.gd`, non in commit): interno agganciato, volo fermo e in moto,
  FPS medi su 10 s con `Time.get_ticks_msec()`. Annotare il numero.

## Task 1 — Orologio (`scripts/interior_clock.gd`)

1. `tests/test_interior_clock.gd`: `base_hour` (10 all'avvio, +1 ogni 60 s, modulo 24), `ring_position`
   (centro della sezione di slot s = suo indice d'anello), `hour_at` (+12 h a metà anello, continuo al
   giro), `daylight` (1 alle 12, 0.15 alle 0, monotona nelle rampe), `night`, `sun_color` (più rosso alle
   18:30 che alle 12), `format`.
2. Vederlo fallire, implementare, verde.

## Task 2 — Luce dell'interno

1. `project.godot`: `[shader_globals]` `interior_hour_origin`, `interior_hour_slope` (float).
2. Test in `test_interior_world.gd`: con l'ora forzata (variabile `clock_seconds` sovrascrivibile) a
   mezzanotte i soli hanno energia `SUN_ENERGY * 0.15`, a mezzogiorno `SUN_ENERGY`; la luce ambientale
   scende e torna com'era all'uscita; la funzione che dà origine/pendenza dell'ora riproduce `hour_at`.
3. Implementare in `interior_world.gd` (`_update_daylight` in `_process`), globo con shader.
4. Shader edifici: `use_hour`, `DAY_GLOW` / `NIGHT_GLOW` / `EVENING_LIT`; `TerrainDressing` lo accende,
   la base lunare no. Test: parametro acceso solo nel materiale dell'interno.
5. HUD: `TimeLabel` sotto l'ID della sezione (test in `test_interior_world` o `test_internal_cruiser`).

## Task 3 — Corsie e posti (`scripts/road_traffic.gd`, solo dati)

1. `tests/test_road_traffic.gd` su un piano generato (`SectionGenerator.generate`):
   - `runs(plan)`: tratti continui, tipo costante, chiusi solo se l'anello è completo;
   - `loops(plan)`: lunghezze (C o 2L), N intero, d = C/N vicino al passo voluto, q intero (`v = C q/3600`);
   - `chunk_instances(plan, loops)`: dizionario pezzo → PackedFloat32Array (20 float per istanza);
   - copia GDScript della formula dello shader `car_at(instance, time)` → (visibile, punto, avanti, n);
   - ogni auto in un solo pezzo nello stesso istante; posizione continua passando di pezzo; stessa
     posizione a `time` e `time + 3600`; punti sulle corsie (a destra, quota 0); densità città > strade.
2. Vederlo fallire, implementare, verde.

## Task 4 — Shader, mesh e montaggio

1. In `road_traffic.gd`: `CAR_SHADER`, `DOT_SHADER`, `car_mesh()`, `dot_mesh()`, `section_far_buffer`.
2. `interior_world.gd`: calcolo del traffico nel worker (`SectionLoad.generate`), MultiMesh vicino per
   pezzo in `_build_chunk` (custom_aabb, visibility_range_end `NEAR_END`), MultiMesh lontano per sezione in
   `_finish_plan`.
3. Test in `test_interior_world.gd`: nodi `Traffic` nei pezzi con strade, `TrafficFar` nella sezione.

## Task 5 — Prova GPU e messa a punto

- Immagini a mezzogiorno, al tramonto e a mezzanotte, da bassa quota vicino a una strada e da alto.
- FPS rispetto al Task 0. Ritocchi (penombra, fari, dimensione dei punti).

## Task 6 — Suite e note

- Suite completa verde; note "Cambiato durante l'esecuzione" nella spec; commit sul branch
  `interior-life`.
