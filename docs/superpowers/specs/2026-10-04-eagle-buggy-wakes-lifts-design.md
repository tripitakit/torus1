# Eagle, Moon Buggy, scie delle barche, cabine degli ascensori — progetto

Quattro ritocchi grafici indipendenti, ognuno un task a sé con il suo test e il suo commit. Tutti i modelli sono
fatti a codice, low poly, come gli altri del gioco (il server Blender non è disponibile). Il renderer è
`gl_compatibility`: la faccia davanti di un triangolo è quella in senso orario; la profondità è a 24 bit e
perde precisione lontano dalla camera.

## Parte 1 — Il void-cruiser in stile Eagle (Spazio 1999)

Oggi la nave non ha un modello: è solo il box di collisione (15 × 7,5 × 30 m) con la vista dalla cabina. Quando
si scende col rover si vede solo il marcatore SHIP.

- **Misure:** il modello sta dentro il box di collisione, muso verso −Z, centro nell'origine della nave.
  Atterraggio, attracco e urti non cambiano. Le gambe arrivano al fondo del box (y = −3,75): la nave posata
  poggia sui piedi.
- **Pezzi:**
  - davanti, il modulo di comando: muso a cono sfaccettato (8 lati) con una fascia di finestrini scuri;
  - la spina dorsale: due travi longitudinali con traversi, a traliccio aperto;
  - al centro, sotto la spina, il modulo passeggeri: un box lungo con spigoli smussati, portelli laterali e
    una striscia rossa per lato;
  - due travi laterali in alto con le quattro gambe a molla e i piedi a disco;
  - dietro, la sezione motori: quattro ugelli conici e i serbatoi sferici fra la spina e i motori.
- **Colori** (parti scelte da UV.x, come in `road_traffic.gd`): bianco/grigio chiaro per lo scafo, grigio
  medio per le travi, rosso-arancio per le strisce, grigio scuro per i finestrini e l'interno degli ugelli.
  Gli ugelli si illuminano (arancio) quando la spinta è accesa; spenti a nave posata.
- **Chi lo vede:** il modello sta sul livello di render 2. La camera del pilota (`Cockpit/PilotCamera`) non
  vede il livello 2: la vista dalla cabina resta com'è. La camera del rover vede tutto.
- **Dove:** `scripts/ship_model.gd` (mesh e materiale), aggiunto come figlio `Model` da `void_cruiser.gd` in
  `_ready()`. Luci di navigazione e fari restano dove sono.

## Parte 2 — Il rover in stile Moon Buggy (Spazio 1999)

Cambia solo `scripts/rover_model.gd`: guida, misure di collisione, occhi del pilota (0, 1,3, −0,2), fari e
ruote restano gli stessi (nomi dei nodi `WheelFL/FR/RL/RR` con figlio `Spin`, `HeadlightL/R`).

- **Telaio:** piattaforma bassa e piatta, bianca, con i bordi smussati e una striscia rosso-arancio su ogni
  fianco; il muso si alza un po' verso l'alto davanti.
- **Ruote:** quattro ruote grandi (raggio 0,4 m come oggi) con battistrada a coste e un mozzo, ognuna sotto
  un parafango bianco.
- **Posto di guida:** due sedili, una console bassa davanti al pilota con luci di stato (piccoli quadrati
  luminosi verdi/ambra), e una cupola trasparente sopra (vetro leggermente azzurro). Dalla cabina della cupola
  si vede solo un anello sottile alla base e il riflesso del vetro: non deve coprire la vista.
- **Davanti:** due fari tondi incassati nel muso (le luci `HeadlightL/R` restano nelle stesse posizioni).
- **Dietro:** un modulo bagagli con un'antenna a frusta.
- Dalla cabina le ruote anteriori e i parafanghi si vedono negli angoli in basso, come oggi.

## Parte 3 — Scie e onde delle barche

Oggi la barca non ha scia (una scia piatta sull'acqua sfarfallava: la profondità a 24 bit non distingueva le
due superfici da lontano).

- **Come:** un nuovo MultiMesh `BoatWakes` per sezione, con gli stessi dati di percorso (`instance_buffer`)
  delle barche. Ogni vertice della mesh della scia porta un **ritardo** (secondi) e un **lato**/scostamento.
  Lo shader lo mette dove la barca era quel ritardo fa (lo stesso calcolo di `pose_s` con `t − ritardo`), con
  il suo verso e la sua normale: così la scia segue le curve del percorso.
- **Forma** (in metri, barca lunga ~11 m, poppa a z = −5, prua a z = +5,6):
  - due bracci di schiuma dietro la poppa, ritardo 0–6 s, che si aprono a V: scostamento laterale
    ±(1,2 + 1,5 × ritardo) m, larghezza del braccio 0,8 → 3 m;
  - una fascia centrale più tenue, ritardo 0–4 s, larga 2,5 → 6 m;
  - due baffi di prua: dalla prua indietro e di lato, ritardo 0–1 s, scostamento ±(0,6 + 3 × ritardo) m.
- **Svanire:** opacità = (1 − ritardo / durata del pezzo) × velocità relativa. La velocità relativa è la
  distanza percorsa dalla barca fra `t − ritardo − 0,5` e `t − ritardo`, divisa per 0,5 s e per la velocità
  di crociera, limitata a 1. Una barca ferma al molo non lascia scia, e quella vecchia sparisce mentre
  frena.
- **Contro lo sfarfallio:** la scia è trasparente, non scrive la profondità e si alza sull'acqua di
  max(0,15 m, 0,0006 × distanza dalla camera). Oltre 1,5 km dalla camera non si disegna.
- **Aspetto:** bianco-azzurro, più forte al centro dei bracci e sfumato ai bordi (lato → alfa); di notte un
  po' più scura.
- **Dove:** `scripts/boat_wake.gd` (mesh, shader e la copia in GDScript del calcolo per i test), istanze
  create dove si creano le barche.

## Parte 4 — Cabine degli ascensori

Oggi la cabina è un box con un vetro finto davanti (`SpineTrain.lift_mesh`).

- **Misure e movimento:** gli stessi (6 × 8 × 6 m, `LIFT_SIZE`, `lift_height`).
- **Struttura** (materiale delle strutture, `STRUCTURE_SHADER`): pavimento e tetto spessi 0,4 m, quattro
  montanti agli angoli (0,3 m), una fascia luminosa (accento) attorno al tetto, il binario della porta
  scorrevole sul lato verso la piattaforma.
- **Pareti:** vetro su tutti e quattro i lati, una mesh a parte con un materiale trasparente leggermente
  azzurro (alfa ~0,25), senza scrittura di profondità. Di notte (stessa ora dell'interno,
  `interior_hour.gdshaderinc`) il vetro si schiarisce un po', come se dentro fosse acceso.
- **Dentro:** da 1 a 4 persone in piedi (la figurina di `dock_crowd.gd`), numero, posizioni e colori fissi per
  cabina, scelti da un hash dell'indice della cabina (sezione, pilone, lato). Girate a caso. Muovono con la
  cabina perché ne sono figlie.
- **Dove:** `SpineTrain.lift_mesh()` cambia (struttura), nuove `SpineTrain.lift_glass_mesh()` e
  `SpineTrain.lift_riders(seed)`; `interior_world.gd` aggiunge vetro e persone come figli della cabina.

## Test

Solo i test nuovi o toccati. TDD.

- `tests/test_ship_model.gd`: il modello sta dentro il box di collisione (con 0,05 m di margine), i piedi
  toccano il fondo (y minima −3,75 ± 0,05), il muso è verso −Z (il punto più avanti ha z < −13), il modello è
  sul livello 2 e la camera del pilota non vede il livello 2; con la spinta accesa il parametro degli ugelli è
  1, a nave posata 0.
- `tests/test_rover_model.gd`: i nodi che la guida usa ci sono (`WheelFL/FR/RL/RR` con `Spin`, `HeadlightL/R`);
  il modello sta dentro 3,4 × 2,4 × 2,2 m; nessun pezzo fra l'occhio del pilota e il cono di vista davanti
  (raggio dall'occhio in avanti libero per 3 m).
- `tests/test_boat_wake.gd`: la copia in GDScript del calcolo della scia: a barca in moto i punti a ritardo
  2 s stanno sul percorso dove la barca era 2 s fa; l'opacità cala con il ritardo; a barca ferma al molo
  l'opacità è 0; l'altezza sull'acqua cresce con la distanza dalla camera.
- `tests/test_spine_train.gd` (toccato): la struttura della cabina sta nelle misure di prima; il vetro copre i
  quattro lati; `lift_riders` dà da 1 a 4 persone, sempre le stesse per lo stesso indice, tutte dentro la
  cabina.
- **Prova GPU:** screenshot dell'Eagle posata su un pad visto dal rover; del Moon Buggy dalla cabina; di una
  barca con scia vista dall'alto (internal cruiser a ~150 m); di una cabina d'ascensore da vicino, di giorno e
  di notte.

## Fuori da questo lavoro

- Interni dell'Eagle e del Moon Buggy oltre a quello visibile.
- Persone che salgono e scendono dalle cabine.
- Schiuma che resta sull'acqua anche dopo il passaggio (oltre i 6 s).

## Cambiato durante l'esecuzione

- **Moon Buggy:** con la base della cupola a 0,95 m il suo anello attraversava la vista bassa come una sbarra;
  cupola e anello ora poggiano sulla piattaforma (0,8 m) e l'anello è più sottile. Fari tondi arretrati nel muso
  e parafanghi lunghi 0,85 m per stare nei 3,4 m di lunghezza.
- **Ascensori:** `interior_world.gd` aveva già `_person_mesh` (per i moli): riusata.
- **Prova GPU:** Eagle vista dal rover a 45 m, cabina del buggy, barca con scia dall'alto, cabina d'ascensore
  con il vetro e quattro persone. Non fatto: la cabina di notte (l'ora dell'interno segue l'orologio vero).
