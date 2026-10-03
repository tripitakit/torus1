# Piano: barche sui laghi e attracco animato

Spec: `docs/superpowers/specs/2026-10-03-interior-lakes-and-dock-design.md`. In sessione, TDD, solo i test toccati.

1. `test_loop_traffic` → `loop_traffic.gd` (percorso, dati, shader).
2. `test_lake_boats` → `lake_boats.gd` (laghi, rettangoli, rotte, modello della barca).
3. `test_dock_crowd` → `dock_crowd.gd` (persone, carrelli, droni, modelli).
4. Montaggio in `interior_world.gd` (barche nel worker e nella sezione, folla nel `Dock` di ogni ponte); test in
   `test_interior_world`.
5. Prova GPU; note; commit sul branch (merge quando lo chiede l'utente).
