# Bridge fermi e assistenza semplificata

## Contesto

Finora sezioni e bridge ruotavano insieme attorno al proprio asse, a circa
0,0586 rad/s: un giro ogni 107 s circa. I pad sui bridge si muovevano quindi a
circa 35 m/s.

L'assistenza all'attracco (`2026-09-27-docking-assist-design.md`) doveva quindi:
- pianificare un punto d'incontro con il pad;
- ricalcolare il piano;
- far girare la frenata insieme al bridge.

Per l'utente, in gioco, così è troppo difficile, e il percorso cambia troppo
spesso.

## Decisione dell'utente

I bridge non ruotano più: le sezioni sì, per la gravità all'interno.
L'assistenza si semplifica di conseguenza.

## Stazione (`scripts/torus_station.gd`)

- **Rotazione:** `_rotate_sections` ruota solo le sezioni. I bridge, con pad,
  port e luci, restano fermi.
- **Funzioni tolte:** `get_bridge_point_velocity`, `get_docking_port_velocity`
  e `get_spin_rate`. Pad e bridge sono fermi nel sistema della stazione.
- **Interno:** non cambia, perché non simula rotazioni.

## Modalità di gioco (`scripts/game_mode.gd`)

- **Attracco:** la regola usa la velocità della navetta, perché il pad è fermo.
- **Uscita dall'interno:** la navetta esce da ferma. B e C restano spenti, come
  già oggi.

## Assistenza (`scripts/docking_assist.gd`, `scripts/void_cruiser.gd`)

- **Velocità consigliata:** `advised_speed(length) = √(2 · 1 m/s² · length)`,
  la velocità da cui ci si ferma sul pad frenando in modo costante:

  | Distanza lungo il percorso | Velocità consigliata |
  |---|---|
  | 20 km | 200 m/s |
  | 1 km | 45 m/s |
  | 150 m | 17 m/s |

  Non c'è più nessun piano d'arrivo.
- **Funzioni tolte:** `arrival_time`, `plan_arrival`, `keeps_plan`,
  `future_pad`, `brake_target` e le costanti di ripianificazione.
- **Pannello:**
  - `readout(length, speed, closing, distance)`, senza più il tempo rimasto;
  - entro 150 m sopra 20 m/s la velocità relativa resta rossa;
  - il limite a 20 m/s della velocità consigliata non serve più: entro 150 m è
    già sotto 17,3 m/s.
- **Frenata B:** ferma sempre la navetta nello spazio, cioè rispetto alla
  stazione, alla potenza di prima (10 × spinta × fattore di precisione).
- **Percorso:** finisce sul pad vero. Resta l'isteresi della forma "sopra il
  bordo".
- **Navetta:** la velocità relativa al dock è la velocità della navetta. Si
  tolgono orologio, piano e lunghezza del percorso memorizzata.

## Fuori scope

- Nessun cambiamento alla spinta di precisione, al mirino, ai quadrati, alla
  navball.

## Testing

- **Stazione:**
  - i bridge non cambiano orientamento con `_rotate_sections`, le sezioni sì;
  - anche con i tick fisici;
  - il port resta fermo.
- **Modalità di gioco:**
  - prompt di attracco con la velocità della navetta;
  - uscita da fermi.
- **Funzioni pure:**
  - velocità consigliata a 20 km, 1 km e 0;
  - righe del pannello con i nuovi argomenti;
  - "troppo veloce per attraccare" resta rosso.
- **Scena vera:**
  - B ferma la navetta nello spazio anche a 500 m dal pad;
  - l'ultimo quadrato è sul pad, a meno di 100 m;
  - i test di guida, mirino e pannello partono da fermi.
