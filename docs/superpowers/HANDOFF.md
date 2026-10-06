# Handoff — Torus1 (aggiornato al 2026-10-02, sera)

Punto di partenza per la prossima sessione. Leggi questo, poi `git log --oneline -40`.

## Stato

- `master` a `451383b`, uguale a `origin/master`. Albero pulito, a parte questo file (non in commit, per scelta
  dell'utente).
- Suite: 62 file su 62 `ALL TESTS PASSED`.
- Resta il vecchio worktree `.claude/worktrees/static-station`, già tutto in master: toglierlo solo dopo
  averlo chiesto.

## Fatto in questa sessione (tutto in master e su origin)

1. **Blocco all'uscita dai portali** (`39f6344`): i corpi della stazione erano cinematici e lo spostamento
   dell'origine di 20.000 km li faceva "volare"; ora sono `StaticBody3D`.
2. **Pianeta con le mappe NASA della Terra** (`tools/earth_maps.py`): Blue Marble luglio, luci delle città
   Black Marble sul lato notte, nuvole reali, rilievo e mare lucido da GEBCO; Europa e Africa verso la
   partenza (`LONGITUDE_OFFSET`).
3. **Limite di velocità per zona** (`speed_limit.gd`): 500 m/s entro 20 km da Torus1 o da un gate, 800 nel
   riferimento lunare, 3 km/s altrove; entrando in una zona più lenta la nave frena da sola; riga LIMIT.
4. **Computer di bordo** (`flight_computer.gd`, `nav_targets.gd`): T sceglie DOCK / GATE TERRA / GATE LUNA /
   SELENE, rotta a tappe attraverso i gate; pannello NAV (distanza, avvicinamento, ETA, STOP, BRAKE IN /
   BRAKE NOW); G = arrivo automatico al punto d'ingresso (1 km dal pad, 500 m davanti al gate, 500 m sopra la
   piazzola), fermo, freno inserito; un tasto di movimento, C o B lo spengono.
5. **HUD a zone** (`hud_layout.gd`): nave in alto a sinistra (sensori solo entro 2 km), computer in alto a
   destra (sempre, `T TARGET` senza bersaglio), un solo pannello di contesto in alto al centro (allunaggio
   sotto 5 km > gate entro 5 km > attracco entro 20 km); in basso croce velocità, **croce ACCEL**
   (`accel_cross.gd`: spinta, esterne, risultante, scala logaritmica) e navball; triangolo arancio della
   risultante; etichette dei marcatori agli angoli con linea diagonale (GATE alto-sinistra, NAV
   basso-destra, SELENE alto-destra), separate anche fuori schermo.
6. **Toppa della luna senza "ridisegno"** (`moon_patch.gd`): reticolo fisso sul piano della faccia del cubo,
   anelli che scorrono di 8 celle; ogni vertice porta la quota dell'anello più grossolano (CUSTOM0/CUSTOM1) e
   lo shader della luna mescola con la distanza dalla telecamera (45–75% della mezza larghezza); quote in
   cache; anelli in anticipo di 0,3 s sulla velocità. Misurato in volo radente: spariti i salti dopo le
   ricostruzioni.

Spec e note "Cambiato durante l'esecuzione" per ogni pezzo in `docs/superpowers/specs/2026-10-02-*`.

## Quale Godot usare

Sempre `~/Godot_v4.6.1-stable-double_linux.x86_64` (doppia precisione). Il `godot` nel PATH rende nero.

- **Un test:** `<build> --headless --path . -s tests/<file>.gd` (fallito se c'è `FAIL`, `SCRIPT ERROR`,
  `Parse Error`).
- **Suite:** ogni `tests/*.gd` uno per uno, timeout 180 s; ~20 minuti, in background. Gli script di comodo
  `rt.sh` e `suite.sh` stanno nello scratchpad, che si svuota fra le sessioni: ricrearli.
- **Prove sulla GPU:** `<build> --path . -s tests/zz_probe.gd` senza `--headless`; salvare PNG dalla
  viewport; cancellare lo script dopo. Il gioco si avvia solo se l'utente lo chiede.

## Trappole delle prove

- Contare i frame non misura il tempo: per le prestazioni usare `Time.get_ticks_msec()`.
- Nave vicino alla luna nelle prove: `in_moon_frame = true` e velocità zero (anche in `_physics_process`),
  altrimenti il suolo arriva a ~1.900 m/s.
- `physics_frame` arriva prima del tick dei nodi: usare `_attached()` nei test lunari.
- L'auto-livello sotto 300 m raddrizza la nave: nei test inclinati `_hold_tilt()`.
- Una finestra di prova visibile riceve input veri (mouse/tastiera): può spegnere l'arrivo automatico.
- Per scovare salti visivi: differenza fra frame consecutivi su un'immagine ridotta, picchi rispetto alla
  mediana, confrontati con i frame delle ricostruzioni (così è stato trovato il problema della toppa).
- Uno script con un errore in `_initialize()` resta vivo: ucciderlo. Mai `pkill -f` con un pattern presente
  nella stessa riga di comando.
- Classi interne: leggono costanti esterne, non chiamano funzioni statiche esterne.
- `WorkerThreadPool.add_task`: passare `true` per la priorità alta; aspettare il task in `_exit_tree`.

## Come lavora l'utente

- Italiano, risposte semplici e brevi (CLAUDE.md globale).
- **Funzioni nuove:** brainstorming con AskUserQuestion, progetto in chat a sezioni, poi spec e piano in
  `docs/superpowers/`, implementazione in sessione con TDD (vuole vedere il test fallire prima), prova GPU,
  suite completa, riepilogo.
- **"/goal implementa inline" o "implementa nativo"** = esegui tu in questa sessione, senza sub-agenti. Non
  vuol dire C++.
- Merge e push solo quando li chiede ("merge in master", "push"); a volte chiede il merge senza suite.
- Bugfix piccoli: commit diretto su master, oppure un branch se il lavoro cresce.
- Prima di "fatto": solo i test nuovi o toccati dalla funzione (non la suite completa: troppo lunga). Test di altre aree solo se in gioco emerge un errore fuori dalla funzione nuova.

## Il gioco in breve

- Pianeta raggio 1.737 km (mappe della Terra), Torus1 anello a 6.949.600 m dal centro (2000 sezioni statiche
  che ruotano, 2000 ponti), luna raggio 250 km a 20.000 km con mappe NASA e rilievo, Base Selene (stile Base
  Alpha) nel cratere Platone, portali Terra (≈120 km dalla partenza) e Luna (20 km sopra la base).
- Tasti: W/S avanti/indietro (rampa 1→10→100x), A/D, Z/X su/giù, Q/E rollio, C cruise, B freno, F attracco,
  R ripartenza, **T bersaglio**, **G arrivo automatico**.

## Problemi noti e rimandati

- **HUD:** le etichette dei marcatori possono passare sopra i pannelli; le due frecce fuori schermo di GATE e
  NAV restano nello stesso punto (solo colori diversi); CRUISE e BRAKE sono righe separate.
- **Gate:** il limite di zona vicino ai gate è 500 m/s, l'ingresso chiede meno di 300 (lo dice il pannello).
- **Toppa:** passando da una faccia del cubo all'altra la griglia cambia una volta; volando alti i crateri
  piccoli si attenuano (voluto).
- **Luna:** crateri in ombra neri pieni; rilievo lontano dalla base grossolano (triangoli fino a 3 km);
  ~38 FPS sopra la base, ALT ignora tetti e torre.
- **Pianeta:** lato notte un po' azzurrino (luce ambientale); terre sotto il livello del mare lucide come mare.
- **Portali:** durante il transito i sensori leggono il bordo d'entrata; scatto di ~0,2 s all'uscita.

## Idee aperte

- Suoni.
- Arrivo automatico "fino in fondo" (attracco, gate, allunaggio), che l'utente per ora ha escluso.
- Marcatori del bersaglio sulla navball.
