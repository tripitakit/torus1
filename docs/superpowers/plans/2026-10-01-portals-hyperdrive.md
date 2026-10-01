# Piano: portali e iperguida

Spec: `docs/superpowers/specs/2026-10-01-portals-hyperdrive-design.md`. Esecuzione in sessione, test prima
del codice, un commit per compito. Test con il binario a doppia precisione.

1. **portal_rules.gd** — test `test_portal_rules` (attraversamento, soglia, uscita, posizioni, righe), poi le
   funzioni pure.
2. **portal.gd** — test di costruzione (nodi Frame/Horizon/Lamps/Beacon, collisori del bordo con apertura
   libera di 150 m, trasformazione attiva); poi il nodo. Portale Terra nella scena, portale Luna da
   `moon.build()`, corpo aggiornato in `moon._place`. Test in `test_scene_wiring` e `test_moon`.
3. **Salto in void_cruiser** — `test_portal_physics`: Terra → Luna, Luna → Terra, troppo veloce, bordo, da
   dietro. Poi stato di transito, entrata in `_move`, uscita, schianto sul bordo, `crashed_on_moon`.
4. **HUD** — `beacon_marker` parametrico, pannello GATE, marcatore GATE; test in `test_cockpit` e
   `test_beacon_marker`.
5. **Tunnel sub-spazio** — `subspace_tunnel.gd`, collegato a start/stop del transito; test che parta e si
   spenga.
6. **Prova GPU** — screenshot del portale Terra dalla partenza e da vicino, del tunnel, dell'uscita sopra la
   base. Correzioni d'aspetto.
7. **Suite completa**, revisione, aggiornamento della spec con quanto cambiato.
