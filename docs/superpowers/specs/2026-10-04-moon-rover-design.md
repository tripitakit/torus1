# MoonRover — progetto

Pezzo 1 di 2. Qui: un rover da guidare sulla luna, che esce dalla nave atterrata. Pezzo 2 (dopo, con una spec
sua): un'auto da guidare sulle strade interne delle sezioni, presa a noleggio vicino a un edificio con
l'insegna CarRental, con l'internal cruiser che resta parcheggiato. Il rover è costruito perché l'auto ne
riusi il nucleo di guida.

## Scelte dell'utente

- Guida arcade semplice, fatta a mano (niente `VehicleBody3D`).
- Scambio con un tasto, rover accanto alla nave; risalita vicino alla nave.
- Vista solo dalla cabina.
- Circa 20 m/s, su tutta la luna.
- HUD: velocità e rotta, pendenza e quota, marcatore sulla nave, marcatore sulla base.

## Struttura (approccio A: nucleo di guida + fornitore di suolo)

- **`scripts/ground_vehicle.gd`** — il nucleo. Solo funzioni statiche, nessun nodo, nessuna scena: dati lo
  stato (velocità lungo il muso, velocità verticale, rotta, in aria o no), i comandi e il suolo sotto le
  ruote, restituisce lo stato nuovo. Non sa su cosa corre.
- **Fornitore di suolo** — un oggetto con due funzioni:
  - `ground_altitude(point: Vector3) -> float`: quanto `point` (mondo) sta sopra il suolo sotto di lui;
  - `up_at(point: Vector3) -> Vector3`: la direzione "alto" in `point`.
  Sulla luna è il nodo della luna stesso (`moon.altitude`, `moon.up_at`, già esistenti; `ground_altitude`
  può essere un alias). Nel pezzo 2 sarà un raggio verso il pavimento del cilindro.
- **`scripts/moon_rover.gd`** — il nodo: `CharacterBody3D` con modello, camera, fari, HUD. Chiama il nucleo
  ogni tick di fisica, si appoggia al suolo, gira con la luna, urta gli edifici.
- **`scripts/rover_hud.gd`** — l'HUD del rover (pannello e marcatori).
- **`scripts/game_mode.gd`** — un modo nuovo `Mode.ROVER` accanto a `VOID` e `INTERIOR`.

## Scambio nave ↔ rover (`game_mode.gd`)

- Tasto nuovo **V**, azione `vehicle` (physical keycode 86).
- **Scendere:** in `Mode.VOID`, nave atterrata (`is_landed`) e nel riferimento della luna, non in crash, non
  in transizione. V → dissolvenza (`_transition`, 0,4 s) → il rover appare:
  - 15 m a destra della nave (asse x della nave proiettato sul piano orizzontale locale), muso nella stessa
    direzione della nave (asse −z proiettato). Se la nave è su un pad (quadrato di 60 m, alto 2 m), il rover
    esce invece a 52 m dal centro del pad (fuori anche dagli angoli) dallo stesso lato;
  - se lì c'è un edificio o un tubo (prova di collisione col box del rover), si prova a sinistra, poi
    dietro, poi davanti;
  - posato sul suolo (ruote a quota del suolo in quel punto), fermo;
  - figlio dello stesso genitore della nave, nel riferimento della luna.
  La camera del rover diventa quella corrente. Mouse catturato.
- **Durante il rover:** la nave resta dov'è, atterrata e visibile. I suoi comandi sono spenti (nessun input
  arriva al volo; il modo più semplice: `set_process_unhandled_input(false)` e un flag che il suo
  `_physics_process` legge per ignorare i tasti). Continua a girare con la luna come oggi.
- **Risalire:** rover entro **30 m** dalla nave (centro a centro), oppure, se la nave è su un pad, entro
  **60 m** dal centro del pad (il rover non sale sul pad); velocità sotto **1 m/s**. V →
  dissolvenza → rover tolto e liberato, camera del pilota della nave corrente, comandi della nave riaccesi,
  `Mode.VOID`.
- V in qualsiasi altro caso: non fa nulla.
- **R** (ripartenza) sul rover: non fa nulla. Un crash della nave sul rover non può succedere (è ferma).
- Il pannello d'allunaggio della nave, quando atterrata, mostra il suggerimento `V ROVER`.

## Guida (`ground_vehicle.gd`)

Comandi:

- **W**: gas. **S**: freno; da fermo, retromarcia (massimo **5 m/s**).
- **A/D**: sterzo.
- **B**: freno a mano (frena forte, anche in discesa resta fermo).
- **Mouse**: guardarsi attorno dalla cabina, ±120° di lato, ±60° in alto/basso. Senza mouse per 1,5 s lo
  sguardo torna dritto in 0,5 s.
- **L**: fari accesi/spenti (azione `lights`, physical keycode 76).

Valori:

- Velocità massima **20 m/s**. Accelerazione **3 m/s²**. Freno **6 m/s²**. Freno a mano **8 m/s²**.
- Senza gas il rover rallenta da solo di **0,6 m/s²** (attrito).
- Sterzo: raggio minimo **6 m** da fermo, che cresce in linea retta fino a **40 m** a 20 m/s. L'angolo delle
  ruote del modello si ricava dal raggio e dal passo (distanza fra gli assi, 2,5 m): circa 23° da fermo. Lo sterzo arriva al
  massimo in 0,3 s e torna dritto in 0,2 s.
- **Gravità lunare 1,62 m/s²** lungo `-up_at`.
- **Pendenza** (angolo fra l'alto del suolo e l'alto locale, misurato lungo il muso): oltre **25°** in salita
  il gas spinge sempre meno, a zero a 35°. Oltre **35°** il rover scivola verso valle (accelerazione
  gravità × seno della pendenza, meno l'attrito). In discesa nessun limite oltre la velocità massima.
- **A terra / in aria:** a ogni tick si guarda la quota del suolo sotto il centro. Se il rover sta sopra il
  suolo di più di **0,15 m** è in aria: niente gas, niente sterzo, solo gravità; la velocità resta quella
  che aveva (così sui dossi fa piccoli salti). Se il suolo sale sopra le ruote il rover viene riportato su e
  la velocità verticale verso il basso azzerata. Ogni ricaduta è morbida: nessun crash.
- **Appoggio sulle ruote:** quattro punti di contatto (ruote a ±0,9 m di lato, ±1,25 m lungo il muso). A
  terra il rover prende l'orientamento del piano che passa per i quattro punti del suolo (due diagonali,
  normale del loro prodotto vettoriale), con il muso che resta sulla rotta. L'orientamento si avvicina a
  quello del suolo in circa 0,1 s, così i sassi piccoli non lo fanno tremare. Non si ribalta mai: il nucleo
  non ha rollio proprio.

## Movimento nel mondo (`moon_rover.gd`)

Ogni tick di fisica, in quest'ordine:

1. **Gira con la luna** del suo ultimo passo (`MoonOrbit.spin(moon.axis(), moon.last_step,
   moon.planet_centre())`), posizione e base, come la nave in `_follow_moon`.
2. Legge i comandi, chiama il nucleo, ottiene la velocità nuova.
3. **Si muove** con `move_and_collide(velocity * delta)` contro la base Selene e la nave. In un urto: la
   componente verso il muro va a zero, il resto perde il 50%, nessun danno.
4. **Si appoggia** al suolo: quota dal fornitore (`moon.altitude`) sotto il centro e sotto le quattro ruote.
5. **Toppa della luna:** `moon.follow_patch(rover.global_position, true, rover.velocity)` ogni tick. La nave,
   mentre il rover esiste, non la chiama (altrimenti le due si contendono la toppa). Al ritorno la nave
   riprende.

Il suolo che il rover legge (`MoonTerrain.height`) è lo stesso che disegna la toppa vicino a lui, quindi le
ruote non restano sospese né affondano dove il terreno è dettagliato.

Sulla base Selene il suolo intorno ai moduli è piano (`moon_base.ground`); sui pad e sui tetti il rover non
sale (sono alti più di un salto: li urta).

## Aspetto e cabina

- Modello a codice, forme semplici, stile rover Apollo: telaio grigio chiaro, pannelli oro, ruote nere a
  maglia (cilindri), roll-bar, antenna a ombrello dietro. Circa 3,1 × 1,8 × 1,4 m.
- Dalla cabina si vedono: cruscotto con due schermi spenti, cofano, le due ruote anteriori (girano con la
  velocità, sterzano con l'angolo), i montanti del roll-bar.
- Camera all'altezza degli occhi del pilota (circa 1,3 m sopra il suolo, 0,3 m dietro l'asse anteriore).
  `fov` orizzontale 90° come la nave, `near` **0,05 m**, `far` come la camera del pilota della nave.
- Due fari davanti (`SpotLight3D`, portata 80 m), accesi all'uscita, **L** li spegne.
- Collisione: un box 3,1 × 1,4 × 1,8 m (lungo, alto, largo) un po' sopra le ruote, così i sassi del suolo
  (che non hanno collisione) non lo fermano.

## HUD (`rover_hud.gd`)

Stile dell'HUD della nave (testo ciano su fondo scuro, `hud_layout.gd` se i suoi helper si riusano).

- **In alto a sinistra**, pannello `ROVER`:
  - `SPD  54 km/h  15.0 m/s`
  - `HDG  273°` — rotta rispetto al nord lunare (asse del polo della luna proiettato sul piano locale).
  - `SLOPE  12°` — angolo fra l'alto del rover e l'alto locale.
  - `ALT  -1240 m` — quota del suolo sotto il rover rispetto a `MoonOrbit.RADIUS`.
  - `LIGHTS ON/OFF`.
- **Marcatori** (`beacon_marker.gd`): `SHIP` sulla nave parcheggiata, `SELENE` sul faro della base
  (`moon.beacon_position()`), con distanza. Fuori schermo la freccia sul bordo, come oggi.
- **In alto al centro**, solo quando vale: `V BOARD` (le stesse condizioni della risalita).

## Test

Solo quelli nuovi o toccati (regola dell'utente). TDD: ogni test visto fallire prima.

- `tests/test_ground_vehicle.gd` (nucleo, suolo finto: piano, rampa, gradino):
  - con W arriva a 20 m/s e non oltre; senza gas rallenta;
  - S frena e poi va in retromarcia fino a 5 m/s;
  - raggio di sterzata ~6 m da fermo e ~40 m a 20 m/s;
  - rampa di 30°: sale più piano; rampa di 40°: scivola indietro;
  - gradino in discesa a 20 m/s: va in aria, poi ricade e torna a terra;
  - B tiene fermo il rover su una rampa di 20°.
- `tests/test_moon_rover.gd` (luna vera):
  - rover posato vicino a Selene, nessun comando: dopo 10 s la quota sul suolo resta entro 0,05 m e la
    posizione rispetto alla base entro 0,1 m (la luna si muove);
  - rover che va contro un modulo della base: si ferma, non lo attraversa;
  - la toppa segue il rover.
- `tests/test_game_mode.gd`, parte nuova:
  - V da atterrati → `Mode.ROVER`, rover a 15 m dalla nave, camera del rover corrente;
  - V in volo → nulla;
  - V con il rover lontano 100 m → nulla;
  - V con il rover a 10 m, fermo → `Mode.VOID`, rover liberato, camera del pilota corrente.
- **Prova GPU** (finestra visibile, PNG): dalla cabina accanto alla base, e a 5 km in mezzo ai crateri, di
  giorno e in ombra con i fari.

## Fuori da questo pezzo

- L'auto a noleggio nelle sezioni interne (pezzo 2).
- Suoni, polvere sotto le ruote, tracce degli pneumatici.
- Danni e ribaltamento.

## Cambiato durante l'esecuzione

- **Pad e sterzo** (prima del piano): rover a 52 m dal centro del pad, risalita entro 60 m; raggio di sterzata
  fissato (6 → 40 m), angolo delle ruote ricavato.
- **Cabina** (dopo la prova GPU): con l'occhio sopra l'asse anteriore il cruscotto copriva un quarto dello
  schermo e le ruote non si vedevano. Ora l'occhio sta fra gli assi (0,2 m davanti al centro), il cruscotto è
  largo 0,7 m, il telaio 1,25 m (più stretto della carreggiata) e il roll-bar sta accanto al pilota: le ruote
  anteriori si vedono negli angoli in basso.
- **Fari**: 18 di energia come quelli della nave, portata 120 m, inclinati di 7° verso il basso; con 4 di
  energia non si vedevano.
- **Test della nave parcheggiata**: controlla che sia `parked`, senza input e senza HUD; non chiama
  `_unhandled_input` direttamente (salterebbe il blocco e non proverebbe nulla).
- **Rimasto**: fuori schermo, se nave e base stanno nella stessa direzione, le frecce SHIP e SELENE e le
  loro etichette si sovrappongono (stesso problema già noto per GATE e NAV).
- **Dopo la revisione finale:**
  - **Salti:** sul terreno vero il rover saltava a ~10 m/s in su e volava per 12–15 s fino a 59 m (15–20% del
    tempo in aria). Ora lo stacco verso l'alto è al massimo **2 m/s** e in aria cade **3 volte** più in fretta
    della gravità lunare (`AIR_GRAVITY`, regolabile); a terra la gravità resta 1,62. Misurato: 3–16% del
    tempo in aria, voli di 0,5–1,8 s in media; i più lunghi scendendo a 20 m/s dai bordi ripidi dei crateri.
  - **Uscita:** dietro e davanti il rover esce a 25 m (lo scafo arriva a 15 m dal centro); se non c'è posto
    da nessuna parte il pilota resta a bordo.
  - **Guida della nave:** con la nave parcheggiata le linee della guida d'atterraggio sopra i pad non si
    vedono più.
