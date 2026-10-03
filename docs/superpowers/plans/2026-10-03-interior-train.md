# Piano: treno sulla spina dell'asse

Spec: `docs/superpowers/specs/2026-10-03-interior-train-design.md`. In sessione, TDD (fallimento visto),
solo i test toccati (niente suite completa).

1. **Orario e stazioni** (`scripts/spine_train.gd`, solo calcoli). Test `tests/test_spine_train.gd`:
   `station_lots`, `station_z`, `period_time`, `progress`, `train_z` (posizione nel nodo della sezione per i
   due sensi), continuità fra periodi. Vederlo fallire, implementare.
2. **Mesh e shader**: spina, pilone, piattaforma, atrio, cabina, treno; shader `unshaded` illuminato
   dall'ora. Funzioni `spine_piece(length)`, `station(...)`, `train_body()`.
3. **Montaggio in `interior_world.gd`**: edifici del lotto tolti nel worker; spina, stazioni e treni nella
   sezione; spina nel ponte; treni in `_physics_process`, cabine in `_process`. Test in
   `test_interior_world.gd` (prima falliti). Il test delle 8 luci salta i materiali `unshaded`.
4. **Prova GPU**: immagini dal suolo, dall'attracco e da vicino; FPS rispetto a prima.
5. **Note** nella spec; commit sul branch `interior-train`.
