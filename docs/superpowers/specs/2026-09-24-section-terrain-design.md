# Terreno procedurale delle sezioni (pezzo B)

## Contesto

Il pezzo A (`2026-09-24-station-interior-access-design.md`) ha costruito il
mondo interno: il tubo del bridge e le due sezioni che collega, ciascuna
divisa in 16 × 20 blocchi di terreno (1 km × circa 785 m), con 20 soli
sull'asse. Il terreno è nudo: una mesh verde uguale per tutti i blocchi.

Questo pezzo riempie le sezioni: campi di colture diverse, strade, laghi,
paesi e un centro città con torri. Il pezzo C (viaggio verso le sezioni
successive) riuserà lo stesso generatore.

## Decisioni prese con l'utente

- **Territorio:** zone miste a macchie. Il terreno "srotolato" è una griglia
  di lotti separati da strade; un rumore procedurale raggruppa i lotti in
  laghi, paesi e campagna.
- **Stile:** low-poly a colori, tutto generato nel codice, nessun asset
  esterno.
- **Edifici:** paesi di case e palazzine basse, più un centro città per
  sezione con palazzi e torri fino a 300 m.
- **Architettura:** generatore puro che produce solo dati, poi costruzione
  della geometria blocco per blocco (approccio 1).

## Scope

Dentro:
- Generatore deterministico per numero di sezione: zone, colture, strade,
  centro città, edifici.
- Geometria per blocco: terreno colorato con filari, strade, acqua, edifici
  con finestre e loro collisioni.
- Le sezioni interne prendono il numero giusto dal bridge d'attracco.
- Test del limite di luci per oggetto con la regola vera del motore.

Fuori:
- Alberi, veicoli, persone, interni degli edifici, rilievi (i laghi sono
  piatti), ponti sui laghi, ciclo giorno/notte.
- Le sezioni oltre le due collegate dal bridge (pezzo C).

## Coordinate

Superficie "srotolata" di una sezione: `x` = lunghezza d'arco attorno
(0 … 2π·2000 ≈ 12 566 m), `z` = distanza lungo la sezione dal suo inizio
(0 … 20 000 m). L'inizio (`z = 0`) è l'estremità con `z` minore nel mondo
interno. L'angolo di un punto è `x / raggio`.

## Architettura

### Dati: `scripts/section_plan.gd`

Dati puri di una sezione e funzioni di lettura:

- Griglia di **48 × 80 lotti** (circa 261,8 × 250 m). Ogni blocco di
  terreno contiene 3 × 4 lotti.
- Per lotto: `zones` (campo, paese, città, lago), `crops` (grano, mais,
  girasoli, lavanda, riso, pascolo), `rows_along` (filari lungo `z` o
  attorno), `road_west` e `road_south` (nessuna, via, principale) per i suoi
  bordi inferiori. Il bordo est di un lotto è il bordo ovest del vicino; il
  bordo nord è il bordo sud del vicino.
- `city_center` (x, z).
- Edifici come array paralleli: centro della base (`x`, `z`), misure
  (larghezza attorno, altezza, profondità lungo `z`, in metri interi),
  colore di facciata, lotto.
- `surface_distance(a, b)`: distanza sulla superficie, tenendo conto che
  attorno il giro si chiude.
- `group_buildings_by_chunk()`: edifici divisi per blocco.

### Generatore: `scripts/section_generator.gd`

`generate(section_index, radius, length)`, statico e deterministico:

- **Zone:** rumore (`FastNoiseLite`, seme = numero della sezione, scala
  circa 2,5 km) campionato nella posizione 3D del centro del lotto, così le
  zone si raccordano quando il giro si chiude. Le soglie sono i quantili:
  esattamente il 10% dei lotti più bassi è lago, il 15% più alto è paese, il
  resto campagna.
- **Centro città:** un lotto scelto dal seme nella parte centrale della
  sezione (dal 20% all'80% della lunghezza). Tutti i lotti con il centro
  entro 700 m diventano città, anche se erano lago o campo.
- **Colture a chiazze:** un "seme" per ogni gruppo di 3 × 4 lotti, spostato a
  caso dentro il gruppo, con una coltura casuale; ogni lotto prende la
  coltura del seme più vicino (le distanze tengono conto del giro). Ne
  escono chiazze irregolari di circa una dozzina di lotti; un generatore
  casuale per lotto sceglie la direzione dei filari.
  - Correzione dopo la review finale: la prima versione usava un secondo
    rumore (circa 800 m) tagliato in 6 fasce, ma la coltura cambiava quasi a
    ogni lotto (17% dei campi vicini uguali, come a caso). Né fasce per
    quantili (24%) né rumore cellulare (al massimo 47%) bastavano; con i semi
    circa il 72% dei campi vicini ha la stessa coltura.
- **Strade:** su un bordo fra due lotti non c'è strada se uno dei due è
  lago; altrimenti c'è una **strada principale** (12 m) se il bordo è sul
  confine di un blocco, una **via** (8 m) se uno dei due lotti è paese o
  città. Nessuna strada sulle due estremità della sezione.
- **Edifici:**
  - Paese: 5 × 5 posti per lotto, l'80% costruito; base 12–25 m, altezza
    8–40 m.
  - Città: 3 × 3 posti per lotto, tutti costruiti; base 30–60 m, altezza
    40–120 m.
  - Torri: nei lotti di città con il centro entro 250 m dal centro città;
    base 25–45 m, altezza 150–300 m.
  - L'altezza è sbilanciata verso il basso (molte basse, poche alte).
  - Ogni edificio sta dentro il suo posto, e i posti stanno dentro il lotto
    a 10 m dai bordi: mai sulle strade, mai in acqua.
- **Determinismo:** ogni scelta casuale viene da un generatore con seme
  ricavato da (numero della sezione, lotto).

### Geometria: `scripts/terrain_dressing.gd`

Trasforma il piano in geometria, un blocco alla volta, nel sistema locale del
blocco. Il blocco resta un corpo fisso con la sua collisione del terreno di
prima; la mesh verde uniforme non si disegna più.

- **Terreno a livello 0, come mosaico senza sovrapposizioni.** Ogni lotto è
  diviso in 3 × 3 celle: il centro è campo o selciato, le 4 fasce ai bordi
  sono strada dove quel bordo ha una strada (metà larghezza per lato), i 4
  angoli sono strada dove i due bordi vicini l'hanno. Le celle di larghezza
  zero si saltano. I laghi coprono tutto il lotto.
  - Perché niente strati sollevati: con la camera interna (near 0,2 m, far
    60 km) il buffer di profondità a 2 km non distingue superfici a meno di
    un metro, e gli strati sovrapposti sfarfallerebbero.
  - Ogni cella segue la curvatura: spicchi di al massimo 90 m d'arco.
  - Normali verso l'asse, stesso verso dei triangoli del terreno del
    pezzo A.
- **Superficie** (`Surface`): una mesh per blocco con due parti:
  - campi, con una texture a strisce generata nel codice (un filare ogni
    5 m) tinta con il colore della coltura;
  - selciato di paesi e città e strade, a tinta unita (principali più scure
    delle vie).
- **Acqua** (`Water`): mesh separata blu, liscia e un po' metallica, solo
  nei blocchi con laghi.
- **Edifici** (`Buildings`): un `MultiMeshInstance3D` per blocco con un
  cubo unitario deformato per edificio, base sul terreno e "su" verso
  l'asse, colore di facciata per istanza.
  - Finestre: un piccolo shader proietta una texture a griglia generata nel
    codice nel sistema dell'edificio stesso, in metri (una finestra ogni 4 m
    su qualsiasi edificio, griglia dritta su ogni facciata); la luce calda
    tenue è colore × maschera dei vetri, quindi si accendono solo i vetri.
    Nessuna luce vera in più.
  - Correzione dopo la review finale: la proiezione in coordinate del mondo
    ruotava la griglia con l'angolo dell'edificio attorno al cilindro
    (finestre a rombo a 45°); e l'operatore di emissione predefinito
    (somma) faceva brillare tutta la facciata, rendendo gli edifici tutti
    dello stesso crema.
  - Oltre 12 km gli edifici non si disegnano.
  - Il riquadro d'ingombro (`custom_aabb`) è impostato a mano: copre il
    blocco fino all'edificio più alto.
- **Collisioni degli edifici:** una scatola per edificio, aggiunta
  direttamente al corpo del blocco (niente nodi per edificio); scatole con
  le stesse misure condividono la forma.

### Collegamento

- `interior_world.gd`: nuovi campi `behind_section_index` e
  `ahead_section_index`; ogni sezione si genera dal suo numero e si veste
  blocco per blocco. `get_section_plan(side)` restituisce il piano.
- Il bridge `i` collega la sezione `i` ("dietro", +Z) e la sezione `i+1`
  ("davanti", -Z), con il giro che si chiude dopo l'ultima.
- `game_mode.gd` passa i due numeri al mondo interno all'attracco.

## Luci

Nessuna luce nuova. Il motore abbina una luce a un oggetto quando i loro
riquadri d'ingombro si toccano; il riquadro di una luce puntiforme è un cubo
di lato ± portata. Il nuovo test conta così, per ogni oggetto disegnato del
mondo interno (esclusi sfere dei soli e cartello, che non sono illuminati),
e verifica al massimo 8 luci.

## Tempo di costruzione

Tutto si genera all'attracco, dietro la dissolvenza. Obiettivo: le due
sezioni complete in meno di 1,5 s; un test fallisce oltre 3 s.

## Testing

- **Generatore:** stesso numero stessi dati; numeri diversi dati diversi;
  quote di laghi, paesi e città; un solo centro città nella parte centrale;
  città esattamente entro 700 m; torri solo vicino al centro; edifici dentro
  il lotto e lontani dalle strade, solo in paesi e città, altezze nei limiti
  della zona, misure intere; nessuna strada sui laghi né alle estremità;
  strade principali sui confini dei blocchi, vie nei paesi; zone raccordate
  alla chiusura del giro; tutte le colture presenti; distanza sulla
  superficie che tiene conto del giro.
- **Geometria:** trasformata dell'edificio (base sul terreno, "su" verso
  l'asse, misure); ogni blocco ha superficie, acqua (se ci sono laghi),
  edifici e collisioni in numero giusto; vertici a livello 0 con normali
  verso l'asse; l'area della superficie è quella del blocco (nessun buco,
  nessuna sovrapposizione); colori delle strade presenti dove servono;
  collisioni uguali agli edifici disegnati; riquadro d'ingombro che copre
  l'edificio più alto.
- **Mondo interno:** sezioni generate dai numeri giusti; 320 blocchi per
  sezione con la collisione del terreno condivisa; limite di 8 luci con la
  regola del cubo; tempo di costruzione.
- **Fisica, con frame reali:** navetta ferma che ruota su un campo, nessuna
  spinta; l'internal-cruiser urta un edificio e rimbalza; vola sopra un lago
  senza urtare nulla.
- **Modalità di gioco:** attraccando al bridge `i` le sezioni sono `i` e
  `i+1`, anche all'ultimo bridge (dove il giro si chiude).

## Verifica

Avvio headless della scena senza errori, più un render offscreen (xvfb) di
due viste interne da controllare a occhio prima di passarlo all'utente.

## Rischi noti

- **Numero di oggetti disegnati:** circa 1300 oggetti in più (superficie ed
  edifici per blocco). Se il frame rate cala, si accorciano le distanze di
  visibilità.
- **Finestre sui tetti:** la proiezione mette la griglia anche sui tetti.
  Accettato nello stile low-poly.
- **Terreno visivo e collisione:** differiscono di meno di un metro
  (spicchi diversi della curvatura).
