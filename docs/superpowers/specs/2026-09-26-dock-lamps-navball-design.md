# Luci del dock e navball

## Contesto

L'HUD di attracco (`2026-09-26-docking-hud-design.md`) ha messo un faro su
ogni pad: un quadrato a grandezza fissa sullo schermo (circa 12 pixel), 20 m
sopra il pad, disegnato sopra tutto. In gioco è risultato troppo grande da
lontano e non abbastanza "del dock".

Inoltre dopo un rollio di 180° i propulsori sembrano ribaltati. Non lo sono:
sono fissi sulla navetta, e Z spinge sempre verso il suo dorso. Manca però
un modo di vedere com'è orientata la navetta nello spazio.

## Decisioni prese con l'utente

- **Luci:** quattro luci verdi sugli angoli del pad (dove la texture ha i
  punti verdi), rotonde, di 8 m reali, che rimpiccioliscono con la distanza
  ma non scendono mai sotto 2 pixel.
- **Il bridge le copre** quando il pad guarda dall'altra parte.
- **Indicatore d'assetto:** una navball.
- **Riferimento:** il piano dell'anello. Su = asse dell'anello; nord = verso
  in cui l'anello si muove in quel punto (prograde); est = lontano dal
  pianeta.

## Luci del dock (`scripts/torus_station.gd`)

- Il faro (`Beacon`, a grandezza fissa) sparisce, con il lampeggio fatto
  dalla stazione a ogni frame.
- Ogni bridge ha quattro nodi `DockLamp_0..3` sugli angoli del pad, a (0,5 −
  0,13) del lato dal centro in ciascuna direzione del pad, 1/600 del raggio
  del bridge sopra la superficie (1 m su un bridge di 600 m).
- Mesh `QuadMesh` di 1 × 1, condivisa; materiale shader condiviso; visibili
  fino a 50 km; margine di culling ampio (la mesh è piccola ma la luce da
  lontano è grande).
- Shader (`skip_vertex_transform`, senza luce, senza culling delle facce):
  - posizione del centro nello spazio della camera, e profondità;
  - larghezza di un pixel a quella profondità:
    `2 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x)` per metro;
  - dimensione = max(8 m, 2 pixel);
  - avvicinamento alla camera della propria dimensione (fattore minimo 0,1),
    così la faccia del bridge su cui poggia non la taglia; il bridge la copre
    ancora quando sta dall'altra parte (1200 m di diametro);
  - quadrato sempre rivolto alla camera, ritagliato a cerchio;
  - lampeggio: accesa 0,5 s ogni 1,5 s (`TIME`).
- Verificato con un render: a 500 m circa 10 pixel, a 4 km 2 pixel. Scrivere
  `MODELVIEW_MATRIX` in questa build non ha effetto; `skip_vertex_transform`
  sì.

## Navball

### Riferimento e assetto (`scripts/attitude.gd`, funzioni pure)

- `ring_reference(position, planet_center, axis) -> Basis`: colonne
  (est, su, −nord).
  - Su = asse dell'anello.
  - Est = direzione dal centro del pianeta alla navetta, proiettata sul
    piano dell'anello.
  - Nord = su × est (il verso di rotazione dell'anello).
  - Sull'asse, dove l'est non è definito, si usa un est qualsiasi
    perpendicolare all'asse.
- `navball_matrix(ship_basis, reference) -> Basis`:
  `reference⁻¹ · ship_basis · diag(1, 1, −1)`. Porta un punto della sfera
  vista dalla camera (+z verso la camera, +x a destra, +y in alto) nella
  direzione di riferimento che rappresenta: il centro è dove punta il muso,
  la destra è la destra della navetta, l'alto è il suo dorso.

### Disegno (`scripts/navball.gd`)

- Un `Control` nell'HUD, in basso al centro, 200 × 200 pixel, che non cattura
  il mouse.
- Dentro:
  - una `SubViewport` 180 × 180 con mondo 3D proprio e sfondo trasparente,
    che contiene una sfera di raggio 1 e una camera ortogonale che la
    inquadra;
  - un `TextureRect` con l'immagine della `SubViewport`;
  - il simbolo della navetta (ali gialle) disegnato al centro.
- La sfera non ruota. Lo shader riceve `attitude` (la matrice d'assetto) e
  colora ogni punto con la direzione che rappresenta:
  - cielo azzurro sopra l'orizzonte, suolo marrone sotto, orizzonte bianco;
  - linee ogni 30° di beccheggio e di direzione, più scure;
  - marcatori rotondi di 7°: prograde giallo, retrograde giallo scuro,
    lontano dal pianeta ciano, verso il pianeta ciano scuro.
- `set_attitude(matrix)` aggiorna lo shader; `cockpit.update_attitude(matrix)`
  lo chiama.
- La navetta calcola la matrice a ogni frame, con il pianeta e l'asse che già
  legge. Senza pianeta usa il riferimento identità.

## Fuori scope

Gradi scritti sulla navball, marcatori del dock o del vettore velocità sulla
navball, suoni.

## Testing

- **Riferimento:** assi ortonormali; est lontano dal pianeta nel piano
  dell'anello; nord coerente con il verso di rotazione; caso sull'asse.
- **Matrice d'assetto:**
  - livellata verso nord: centro → nord, destra → est, alto → su;
  - virata a est: centro → est;
  - rollio di 180°: alto → giù;
  - muso verso l'alto: centro → su.
- **Luci:**
  - quattro per bridge, sugli angoli giusti, 1/600 del raggio sopra il pad;
  - mesh e materiale condivisi; visibili fino a 50 km; nessun `Beacon`;
  - lo shader contiene dimensione minima, lampeggio, avvicinamento alla
    camera e `skip_vertex_transform`.
- **Navball:**
  - nodi nell'HUD, in basso al centro;
  - `SubViewport` con mondo proprio e sfondo trasparente;
  - `set_attitude` arriva allo shader;
  - la navetta passa la matrice.
- **Render offscreen (xvfb):**
  - luci a 500 m, 3 km e 30 km;
  - navball livellata e dopo un rollio di 180°.
