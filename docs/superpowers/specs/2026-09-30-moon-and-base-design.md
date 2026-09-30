# Luna orbitante con base lunare e allunaggio

## Contesto

Fuori dalla stazione oggi ci sono il pianeta (raggio 1737,4 km, GM lunare
4,9048e12) e l'anello, in orbita circolare a 6949,6 km dal centro. Il
void-cruiser vola nel riferimento dell'anello, che ruota: sente la gravità
del pianeta, la centrifuga e la Coriolis (`orbital_frame.gd`); nel vuoto non
ha attrito e accelera fino a circa 15 km/s². Toccare il pianeta è uno
schianto (`void_cruiser.gd`, `game_mode.gd`).

L'utente vuole dare vita allo spazio fuori dalla stazione: una luna che
orbita attorno al pianeta, con una base lunare in stile anni '70 (tipo la base
di Spazio 1999) su cui il void-cruiser può allunare.

## Decisioni prese con l'utente

- **Orbita vera:** la luna è su un'orbita circolare fisica. Vista dall'anello
  si muove a circa 1,8 km/s: per allunare bisogna raggiungerla e pareggiarne
  la velocità.
- **Luna piccola craterizzata:** raggio 250 km, gravità circa 0,1 g, a
  20.000 km dal centro del pianeta.
- **Posa fisica** sulle piazzole (e anche sul suolo nudo), senza interni.
- **Riferimento che segue la luna** (approccio A): sotto i 30 km di quota il
  cruiser vola nel riferimento della luna; base e piazzole sono ferme per la
  sua fisica.
- **Regola di posa:** scafo in piano (asse "su" della nave entro circa 25°
  dalla verticale locale; muso in qualsiasi direzione), velocità verticale
  sotto 5 m/s, orizzontale sotto 2 m/s. Oltre: schianto.
- **Nome:** "Base Selene" (per non usare il nome della base della serie).

## Scope

Dentro:
- Luna: orbita, rotazione sincrona, mesh e texture di crateri, gravità.
- Riferimento lunare: aggancio e sgancio sotto/sopra i 30 km di quota,
  velocità continua nel cambio.
- Suolo analitico della luna: posa e schianto.
- HUD lunare: quota, velocità verticale e orizzontale, stato.
- Base Selene: torre, moduli, tubi, hangar, sei piazzole con luci, collisioni.
- Guida di allunaggio verso la piazzola libera più vicina.
- Ripartenza dopo uno schianto sulla luna: posati sulla piazzola 1.

Fuori:
- Interni della base, personaggi, veicoli lunari, altre navi.
- Collisione con i crateri (sono solo nella texture: il suolo è la sfera).
- Orbita inclinata o ellittica, maree, effetti della luna sull'anello.
- Luna attorno a cui orbita il pianeta "vero" (resta tutto nel sistema del
  pianeta attuale).

## Fisica

### Il riferimento della luna

La luna è in rotazione sincrona: mostra sempre la stessa faccia al pianeta.
Nel riferimento inerziale ruota attorno al centro del pianeta, insieme alla
sua orbita, con `ω_luna = sqrt(GM_pianeta / r³)` (r = 20.000 km: circa
2,48e-5 rad/s, periodo circa 70 h). L'anello ruota con
`ω_anello` (circa 1,2e-4 rad/s).

Nella scena (riferimento dell'anello) la luna è quindi un corpo rigido che
ruota attorno all'asse del pianeta con `ω_rel = ω_luna − ω_anello` (circa
−9,6e-5 rad/s: un giro in circa 18,2 h, in senso opposto all'anello; a
20.000 km dall'asse circa 1,9 km/s). Un
punto della luna a distanza `d` dall'asse si muove a `ω_rel × d`.

Il riferimento della luna è dunque un riferimento che ruota attorno al centro
del pianeta con velocità angolare `ω_luna`: la stessa matematica di
`OrbitalFrame.frame_acceleration`, con `ω_luna` al posto di `ω_anello`, più
la gravità della luna.

### Aggancio e sgancio

- **Aggancio** quando la distanza dal centro della luna scende sotto
  `R_luna + 30 km`; **sgancio** sopra `R_luna + 32 km` (2 km di isteresi,
  per non oscillare al confine).
- Da agganciato, a ogni tick di fisica la nave viene trascinata con la luna:
  posizione e orientamento ruotati attorno all'asse del pianeta, per il
  centro del pianeta, di `ω_rel × dt`. La sua `velocity` è quella rispetto
  alla luna.
- Nel cambio la velocità vera non salta: `v_anello = v_luna + ω_rel × (p −
  centro_pianeta)` (vettori: `ω_rel` sull'asse del pianeta).
- Freno (B) e blocco di crociera (C) lavorano sulla `velocity` del
  riferimento corrente: vicino alla luna fermano rispetto al suolo.

### Forze

- Sempre: gravità del pianeta e gravità della luna, `GM_luna = 6,1e10`
  (0,098 × 9,8 × 250.000² ≈ 0,1 g al suolo). Lontano dalla luna il suo
  contributo è minimo ma continuo.
- Nel riferimento dell'anello: centrifuga e Coriolis con `ω_anello` (come
  oggi). Nel riferimento della luna: con `ω_luna`.
- Freno o crociera attivi: nessuna forza (come oggi).

### Suolo, posa e schianto

- Il suolo è la sfera di raggio 250 km. Il movimento della nave è
  controllato contro la sfera di raggio `R_luna + 3,75 m` (metà altezza
  dello scafo), come oggi contro il pianeta.
- Al contatto, nel riferimento della luna:
  - velocità verticale (verso il centro) sotto 5 m/s, orizzontale sotto
    2 m/s, asse "su" della nave entro 25° dalla verticale locale →
    **posata**: velocità e rotazione a zero, la nave resta ferma sul suolo
    (trascinata con la luna);
  - altrimenti → **schianto** (stesso flusso del pianeta).
- Da posata: la spinta verso l'alto della nave (tasto Z, lungo il suo asse
  Y) la stacca; ogni altro comando è ignorato finché non riparte.
- Lo stesso vale sulle piazzole e sulle superfici orizzontali della base
  (normale del contatto entro 25° dalla verticale locale). Contro le pareti
  degli edifici: rimbalzo, come oggi contro la stazione.

## La luna

- `scripts/moon.gd` (Node3D figlio di `PlanetSystem`, accanto al pianeta:
  così lo spostamento dell'origine del mondo la muove con il resto). Ogni
  tick di fisica avanza l'angolo di `ω_rel × dt` e rimette posizione e
  rotazione.
- **Posizione iniziale:** angolo scelto perché all'avvio sia visibile
  dall'anello, circa 60° davanti alla nave lungo l'orbita.
- **Mesh:** costruita nel codice in coordinate polari centrate sulla base:
  anelli fitti vicino alla base (circa 20 m fra un anello e l'altro nei primi
  2 km), sempre più radi lontano, 1024 spicchi. Così vicino alla base la
  superficie è liscia (freccia sotto il centimetro) e lontano la freccia resta
  sotto circa 1 m. Una sola mesh, niente giunture fra parti.
- **Texture:** colore e normal map di crateri, prodotte una volta da uno
  script `tools/moon_textures.gd` (eseguito con la build doppia in headless)
  e salvate in `assets/textures/moon/`. Lo shader le legge per direzione
  (equirettangolare), senza UV sulla mesh. Grigia, senza atmosfera.
- Illuminata dal sole della scena (luce direzionale).

## Base Selene

- **Posizione:** sulla faccia verso il pianeta, a 30° dal punto sotto il
  pianeta: il pianeta sta alto nel cielo della base, sempre nello stesso
  punto.
- **Pianta** (circa 2,5 km di diametro), su un piano tangente locale (x,
  z), ogni pezzo poi posato sulla sfera con la sua verticale:
  - **torre di comando** al centro: esagonale, 60 m di altezza, anello di
    osservazione vetrato in cima;
  - **quattro bracci radiali** (N, E, S, O) di moduli 20 × 40 × 10 m (5 per
    braccio, a 90 m l'uno dall'altro), uniti da tubi (sezione 6 m);
  - **sei piazzole** 60 × 60 m, rialzate di 2 m: tre in fondo al braccio E e
    tre in fondo al braccio O, a 100 m l'una dall'altra; ognuna con la grafica
    e le quattro luci verdi del pad della stazione, un numero (1–6) e un
    hangar 30 × 40 × 12 m accanto, collegato da un tubo.
- **Aspetto:** moduli, torre e hangar con lo shader delle facciate degli
  edifici interni (finestre a fasce, pannelli chiari); tubi grigio chiaro.
- **Collisioni:** scatole convesse per ogni pezzo, in un corpo animato figlio
  della luna.
- **Luci:** le piazzole hanno le lampade lampeggianti del dock; nessuna
  altra luce dinamica (la luna è illuminata dal sole).

## Guida di allunaggio

- Attiva nel riferimento della luna entro 20 km dal centro della base.
- **Piazzola bersaglio:** la più vicina fra quelle libere (tutte, finché non
  ci sono altre navi).
- **Riquadri di avvicinamento** (come per il dock): una colonna verticale di
  riquadri sopra la piazzola, a 50, 100, 200, 400 m di quota, e una linea
  dalla nave alla colonna.
- **Pannello** (al posto di quello di avvicinamento al dock):
  - `PAD 3`;
  - `ALT` quota sopra la piazzola;
  - `V/S` velocità verticale (verde sotto 5 m/s in discesa);
  - `DRIFT` velocità orizzontale (verde sotto 2 m/s);
  - `LEVEL` inclinazione (verde entro 25°);
  - stato `LANDED`, `TOO FAST` o vuoto.
- Fuori dalla portata della guida ma nel riferimento della luna: pannello
  con quota sul suolo, `V/S` e `DRIFT`.

## Ripartenza

- Schianto sulla luna → dopo R la nave riparte **posata sulla piazzola 1**.
- Schianto sul pianeta → come oggi (accanto al dock più vicino).

## Test (TDD, ogni test visto rosso prima)

- `tests/test_moon_orbit.gd` (puro): `ω_luna`, `ω_rel`, periodo; rotazione
  rigida attorno all'asse del pianeta; conversione di velocità fra i due
  riferimenti e ritorno; accelerazione nel riferimento lunare (gravità della
  luna 0,1 g al suolo, zero forze da ferma sulla luna tranne gravità e
  termini dovuti al pianeta).
- `tests/test_moon.gd`: la luna avanza con `ω_rel`, sta a 20.000 km dal
  pianeta, mostra sempre la stessa faccia (la base guarda il pianeta); mesh:
  vertici sulla sfera, anelli fitti vicino alla base.
- `tests/test_moon_landing_physics.gd` (in scena, fisica vera):
  - aggancio e sgancio con velocità vera continua;
  - posa lenta e in piano → posata, poi ferma sul suolo per molti tick;
  - troppo veloce, troppo di lato o inclinata → schianto;
  - spinta verso l'alto → riparte;
  - posa su una piazzola; urto contro un modulo → rimbalzo.
- `tests/test_moon_base.gd`: sei piazzole numerate, distanze fra i pezzi,
  niente sovrapposizioni, tutto sulla sfera con la verticale giusta, la base
  guarda il pianeta.
- `tests/test_landing_guide.gd`: piazzola bersaglio, valori del pannello e
  colori delle soglie, riquadri sopra la piazzola.
- `tests/test_game_mode.gd`: dopo uno schianto sulla luna si riparte posati
  sulla piazzola 1.
- Verifica dal vivo con la build a precisione doppia: raggiungere la luna,
  agganciarsi, allunare su una piazzola e ripartire.
