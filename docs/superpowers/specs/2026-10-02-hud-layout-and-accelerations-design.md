# HUD a zone e vettori di accelerazione

Data: 2026-10-02. Stato: approvato in chat. Pezzi 3 e 4 del riordino della navigazione.

## Disposizione

- In alto a sinistra, NAVE: SPEED, LIMIT, CRUISE, BRAKE, THRUST; le distanze dei sensori solo entro 2 km;
  DOCK [F].
- In alto a destra, COMPUTER: il pannello NAV, sempre visibile; senza bersaglio solo `T  TARGET`.
- In alto al centro, CONTESTO: uno solo fra attracco, gate e allunaggio (i tre pannelli di oggi, nello stesso
  posto). Priorità (`hud_layout.gd`): allunaggio se nel riferimento lunare e sotto 5 km dal suolo; poi gate
  (entro 5 km da un portale); poi attracco (entro 20 km da un dock); poi il pannello lunare se c'è.
- In basso: croce delle velocità, croce delle accelerazioni (nuova), navball.
- Sulla scena: i marcatori di oggi più quello dell'accelerazione.

## Accelerazioni

La nave registra a ogni passo, nel mondo:
- esterne: gravità e forze del riferimento (sempre quelle fisiche, anche con freno o cruise);
- risultante: la variazione reale della velocità nel passo / delta;
- spinta: risultante − esterne (motori, freno, computer, limite di velocità).
Da posata: risultante e spinta zero, esterne quelle fisiche.

Croce ACCEL (`accel_cross.gd`): sugli assi della nave come la croce delle velocità; tre frecce nel piano
traverso/verticale e tre barre avanti/indietro, colori: spinta azzurro, esterne arancio, risultante bianco.
Scala logaritmica da 0,01 a 20.000 m/s². Valori: `THR`, `EXT`, `NET` in m/s² e g.
Marcatore: triangolo arancio dove punta la risultante (dietro la vista: rovesciato, al punto opposto), nascosto
sotto 0,05 m/s².

## Test

- `test_hud_layout`: priorità del contesto, filtro dei sensori.
- `test_accel_cross`: scala, valori, nodo.
- `test_flight_markers`: posizione del marcatore dell'accelerazione.
- `test_cockpit`: posizioni dei pannelli, NAV sempre visibile, sensori nascosti oltre 2 km.
- Fisica: frenando la risultante è opposta alla velocità; posata sulla luna risultante zero ed esterne ~0,1 g.
- GPU: partenza, gate, allunaggio.
