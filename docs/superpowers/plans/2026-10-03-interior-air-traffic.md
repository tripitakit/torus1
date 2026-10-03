# Piano: traffico aereo dei cruiser interni

Spec: `docs/superpowers/specs/2026-10-03-interior-air-traffic-design.md`. In sessione, TDD, solo i test toccati.

1. `tests/test_air_traffic.gd` → `scripts/air_traffic.gd` (rotte, `pose(lane, s)`, `buffer(lanes, t)`).
2. Mesh del cruiser, shader e luci in `air_traffic.gd`.
3. Montaggio in `interior_world.gd`: rotte nel worker, MultiMesh `AirTraffic` e `AirLights` nella sezione,
   `update_air(t)` in `_process`; test in `test_interior_world.gd`.
4. Prova GPU; note nella spec; commit; merge in master (richiesto dall'utente).
