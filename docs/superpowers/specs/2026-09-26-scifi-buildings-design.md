# Edifici sci-fi nelle sezioni

## Contesto

Il pezzo B (`2026-09-24-section-terrain-design.md`) riempie le sezioni di
paesi e città. Ogni edificio oggi è un parallelepipedo (`BoxMesh` in una
`MultiMesh` per blocco) con la stessa griglia di finestre, una ogni 4 m, su
tutte le facce, tetto compreso. Le collisioni sono scatole.

Questo lavoro dà agli edifici forme sci-fi e facciate diverse fra loro.

## Decisioni prese con l'utente

- **Stile misto per zona:** paesi con forme basse e arrotondate, città con
  torri slanciate.
- **Quattro tipi di facciata:** fasce luminose, finestre rade, vetrata
  scura, pannelli ciechi. Mai finestre sui tetti.
- **Luci di colori diversi per edificio:** bianco caldo, bianco freddo,
  ciano, ambra, magenta (raro).
- **Collisioni:** una forma convessa per tipo di edificio.
- **Approccio A:** un catalogo di forme costruite nel codice, una
  `MultiMesh` per forma presente nel blocco, uno shader con i dati del
  singolo edificio.

## Forme (`scripts/building_shapes.gd`)

- Ogni forma è una mesh low-poly costruita una volta sola, con al massimo
  256 triangoli, dentro il cubo unitario centrato sull'origine (x, z da
  -0,5 a 0,5; y da -0,5 a 0,5, base a y = -0,5). `building_transform`
  resta com'è e la deforma alle misure dell'edificio.
- Quasi tutte sono "anelli sovrapposti": un profilo di pianta (quadrato,
  ottagono, cerchio a 12 lati) ripetuto a varie altezze e scale. Un anello
  alla stessa altezza del precedente ma più stretto forma un gradino: è un
  tetto.
- Normali piatte (look low-poly), avvolgimento dei triangoli secondo Godot:
  la normale è opposta a (b−a)×(c−a) (verificato).

| Nome | Zona | Forma |
|---|---|---|
| `Dome` | paese | tamburo basso e cupola a 12 lati |
| `Vault` | paese | modulo sdraiato con tetto a volta e testate piatte |
| `Block` | paese | blocco ottagonale (spigoli smussati) con attico |
| `RingHouse` | paese | cilindro con un anello sporgente a metà |
| `Stepped` | città, torri | torre quadrata con due rientri |
| `Tapered` | città | torre ottagonale affusolata con coronamento |
| `RingTower` | città, torri | torre cilindrica con due anelli sporgenti |
| `FinSlab` | città | lastra stretta con quattro alette verticali |
| `Spire` | torri | guglia ottagonale affusolata con antenna in cima |

La "capsula" discussa a voce diventa `Vault`, un modulo a volta: si
costruisce e si deforma meglio di una pillola sdraiata.

## Scelta nel generatore

`section_plan.gd` riceve:
- `enum Style` (le nove forme);
- `enum Facade { BANDS, SPARSE, GLASS, PANELS }`;
- `ACCENT_COUNT = 5`;
- per edificio: `building_style`, `building_facade`, `building_accent` e
  `building_lit` (quota di finestre accese, fra 0,2 e 0,6).

`section_generator.gd` sceglie con un generatore casuale a parte per
edificio, con seme da (sezione, lotto, posto, "look"). Così posizioni e
misure degli edifici restano quelle di oggi.
- Paese: `Dome`, `Vault`, `Block` o `RingHouse` se l'edificio è basso e
  largo (altezza non oltre il 70% del lato minore), altrimenti `Block` o
  `RingHouse`.
- Città: `Stepped`, `Tapered`, `RingTower` o `FinSlab`.
- Torri: `Spire` (metà dei casi), `Stepped` o `RingTower`.
- Facciata: una delle quattro, con la stessa probabilità.
- Luce: bianco caldo 30%, bianco freddo 25%, ciano 20%, ambra 18%,
  magenta 7%.
- Colori di facciata, tavolozza sci-fi:
  - paesi: bianco, grigio chiaro, sabbia, grigio-azzurro, verde acqua
    pallido;
  - città: grafite, grigio, bianco, grigio-azzurro, bronzo scuro.

## Geometria (`scripts/terrain_dressing.gd`)

- `Buildings` diventa un nodo con una `MultiMeshInstance3D` per ogni forma
  presente nel blocco (nome = nome della forma).
- Ogni istanza porta il colore di facciata e 4 dati personalizzati:
  facciata, colore della luce, quota accesa, seme. Una funzione pura,
  `building_custom(plan, b)`, fornisce i dati sia alla `MultiMesh` sia ai
  test: in headless la `MultiMesh` non si può rileggere.
- Ogni `MultiMeshInstance3D` ha il suo riquadro d'ingombro fino al suo
  edificio più alto, e resta visibile fino a 12 km.
- Collisioni: l'involucro convesso di ogni forma, scalato alle misure
  dell'edificio. Una forma con le stesse misure è condivisa. Le rientranze
  (gradoni, spazio fra le alette) diventano piene: lì si urta a qualche
  metro dalla parete.

## Shader

Uno shader per tutti gli edifici.
- **Pareti:** superfici con |n.y| < 0,5 dopo la deformazione. Tutto il
  resto (tetti, gradoni, parte alta delle cupole) è tetto: tinta piena un
  po' più scura, niente finestre.
- **Coordinate sulla parete, in metri:** attorno = angolo attorno all'asse
  dell'edificio × metà della larghezza media; in alto = altezza dalla base.
- **Fasce luminose:** strisce alte 1,2 m ogni 1, 2 o 3 piani da 4 m (dal
  seme), da 2 m in su; tratti di 8 m accesi o spenti ciascuno per conto
  suo.
- **Finestre rade:** finestre di 1,5 × 1,5 m ogni 6 m in orizzontale e 4 m
  in verticale, da 2 m in su; accese secondo la quota dell'edificio.
- **Vetrata scura:** vetro scuro, liscio e un po' metallico; circa il 5%
  delle celle di 3 × 4 m ha una luce.
- **Pannelli ciechi:** giunzioni ogni 4 m, nessuna finestra; una fascia
  luminosa sottile sotto il bordo del tetto.
- Brillano solo le parti accese, nel colore di luce dell'edificio.

## Prestazioni

- Da 1 a 3-5 chiamate di disegno per blocco.
- Da 12 a 60-250 triangoli per edificio.
- Collisioni convesse: 24,5 µs l'una (misurato), circa 0,9 ms per blocco
  in media.
- Il frame peggiore durante il caricamento (oggi circa 22 ms) deve restare
  sotto i 50 ms del test esistente. Se non ci sta, le misure delle
  collisioni si arrotondano ai 2 m pari, per condividere più forme.

## Fuori scope

Interni, versioni semplificate per la distanza, luci che cambiano nel
tempo, dettagli sul tetto oltre la forma, luci vere dalle finestre.

## Testing

- **Forme:**
  - tutte dentro il cubo unitario, con la base a -0,5 larga quanto il lotto
    e la cima a 0,5;
  - avvolgimento coerente con le normali;
  - normali unitarie;
  - al massimo 256 triangoli;
  - involucro convesso pronto per ogni forma.
- **Generatore:**
  - i quattro dati nuovi per ogni edificio, nei limiti e deterministici;
  - forme della lista della zona;
  - `Dome` e `Vault` solo per edifici bassi e larghi;
  - tutte le facciate e tutte le luci presenti, magenta sotto il 10%;
  - almeno 8 forme diverse in una sezione;
  - i test di oggi restano verdi.
- **Blocco vestito:**
  - una `MultiMeshInstance3D` per forma, con la mesh giusta e il numero
    giusto di istanze;
  - dati personalizzati attivi, `building_custom` coerente col piano;
  - una collisione convessa per edificio, nella stessa posizione di quello
    disegnato, che contiene tutti i suoi vertici;
  - riquadri d'ingombro che coprono l'edificio più alto.
- **Shader:** controllo del codice (dati per istanza, test delle pareti) e
  render offscreen (xvfb) di un paese e di un centro città, senza errori di
  compilazione, da guardare prima di passarli all'utente.
- **Mondo interno e fisica:** i test esistenti aggiornati. L'internal-cruiser
  urta un edificio a un terzo della sua altezza, perché le forme si
  stringono verso l'alto.
- **Caricamento:** il test del frame peggiore resta sotto i 50 ms.
