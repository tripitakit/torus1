# Avamposti sulla faccia nascosta: UltraTelescopio e Area 2 — progetto

Due strutture sulla faccia della luna opposta al pianeta, lontane fra loro: l'**UltraTelescopio** (grande
parabola e cupola ottica, edificio di controllo) e l'**Area di Smaltimento Nucleare 2** (omaggio al pilot
*Breakaway* di *Spazio 1999*: campo dei silo delle scorie con recinto laser e deposito di monitoraggio
circolare). Gli edifici si esplorano a piedi (airlock + sala), con il livello di dettaglio degli interni di
Selene.

## Scelte dell'utente

- Si arriva con l'Eagle su un pad di ciascun sito; i siti sono bersagli del computer di bordo; a piedi, **K al
  portello dell'airlock** per entrare e, dentro, per uscire.
- Strutture **vuote** (nessuna persona).
- Telescopio: **grande parabola + cupola**.
- Approccio A: il costruttore degli interni di Selene diventa generico ("stile Alpha"), Selene e avamposti lo usano.
- Spec, piano e implementazione nativa.

## Riferimenti (Area 2 nel pilot)

Area a croce con 35 coperchi di silo (12 nel braccio ovest, 12 nel sud, 7 nel nord, 4 nell'est), pad centrale per
gli Eagle con nastro trasportatore e montacarichi verso i pozzi, schermi antiradiazioni, recinto laser
perimetrale; depositi di monitoraggio circolari con il loro pad.

## Dove

- **UltraTelescopio:** Mare Moscoviense, 27° N, 147° E. **Area 2:** fondo di Tsiolkovskiy, 20° S, 129° E.
  Separazione ~50° (~218 km sulla luna del gioco, raggio 250 km). Entrambi sulla faccia opposta al pianeta
  (test: direzione del sito · direzione del pianeta < 0).
- **Terreno piano** attorno a ciascun sito come per Selene (`MoonTerrain`, ora una lista di siti):
  telescopio piano entro 350 m, raccordo fino a 900 m; Area 2 piano entro 450 m, raccordo fino a 1.200 m.
  Nessuna pietra sul piano (`MoonRocks`).

## Esterni (`scripts/moon_sites.gd`, nodi `Sites/Telescope`, `Sites/Area2` della luna)

Corpi statici figli della luna, aggiornati a ogni tick come la base (`moon._place`). Low poly, bianco e grigio
con bande arancio.

- **UltraTelescopio:** parabola di 60 m su traliccio e piattaforma girevole (ruota lenta in azimut, 1 giro ogni
  4 min); cupola ottica Ø 20 m con fenditura aperta e il tubo del telescopio; edificio di controllo (14 × 12 m,
  alto 6) con il portello dell'airlock, una vetrata verso la parabola; pad per l'Eagle (Ø 30 m) a 120 m.
- **Area 2:** campo a croce (bracci larghi 40 m, lunghi 84 m dal quadrato centrale: ~15.000 m², due campi da
  football) in regolite compattata grigio chiaro; 35 coperchi di silo (cilindri bassi Ø 6 m con simbolo della
  radioattività) nei bracci; quadrato centrale con pad degli Eagle, nastro trasportatore, montacarichi e una pila
  di cilindri di piombo; **recinto laser**: pali ogni 10 m lungo il bordo della croce con 3 fasci rossi luminosi
  (collisione: ferma pedone e rover); **deposito di monitoraggio** circolare (Ø 22 m, alto 6) fuori dal recinto,
  a un angolo, con portello dell'airlock e vetrata sul campo; pad per l'Eagle (Ø 30 m) accanto al deposito.
- Collisioni: edifici, cupola, base della parabola, coperchi dei silo, pila di cilindri, pali e fasci.

## Pad e computer di bordo

- I pad dei siti sono il 7 (telescopio) e l'8 (deposito) di `moon.pad_transform(number)`; guida d'atterraggio e
  lettura del pad valgono per tutti i pad entro `GUIDE_RANGE` (prima solo Selene). **H** (scendere nella base)
  resta solo per i pad 1–6.
- Bersagli del computer di bordo: `TELESCOPE`, `AREA 2` (lato luna), arrivo 500 m sopra il pad.

## Interni (costruttore stile Alpha, `scripts/alpha_interior.gd`)

`SeleneInterior` diventa una sottoclasse; il costruttore comune fa stanze, pareti piene unite (angoli chiusi),
soffitti a cassettoni, zoccolo e strisce, porte con cornici, arredi, finestre con sfondo dipinto, luci,
ambiente. La pianta comune (`scripts/alpha_plan.gd`): pareti unite e `room_at` da una lista di stanze e porte.

- **Telescopio** (`telescope_layout.gd`): **airlock** 4,8 × 4,8 (alto 3) con armadietti delle tute, panca, luci
  rotanti di avviso, portello esterno (non si apre: è l'uscita); **sala di controllo** 12 × 9,6 (alta 4,2) con
  console a ferro di cavallo, scrivanie con monitor, banchi di computer con bobine, grande schermo con
  l'immagine del telescopio (galassia a spirale), vetrata verso la parabola (sfondo dipinto: parabola sul cielo
  nero).
- **Deposito** (`depot_layout.gd`): **airlock** come sopra; **sala monitor** 12 × 12 (alta 4,2) con console di
  sorveglianza, letture di radioattività (barre e il simbolo), mappa dei silo, banchi di computer, vetrata sul
  campo (sfondo dipinto: la croce dei silo e i pali del recinto).
- Nessuna persona.

## Entrare e uscire

- A piedi sulla luna entro 3 m dal portello: HUD `K AIRLOCK`; K (dissolvenza 0,4 s): il mondo esterno si stacca,
  si è nell'airlock davanti al portello. Se c'è anche un mezzo vicino, K sale a bordo (precedenza ai mezzi).
- Dentro, entro 2,5 m dal portello: `K USCITA`; K: fuori, a piedi davanti al portello, come prima.
- HUD dentro: `OUTPOST`, velocità, nome della stanza.

## Test

TDD; solo i test nuovi o toccati.

- `tests/test_alpha_plan.gd` / test di Selene: la pianta di Selene resta identica dopo il passaggio al
  costruttore comune (test esistenti di layout, interni, equipaggio).
- `tests/test_moon_sites.gd`: siti sulla faccia nascosta e lontani fra loro; terreno piano al sito e raccordo;
  nessuna pietra; 35 silo divisi 12/12/7/4; area della croce ~15.000 m²; pali del recinto ogni ≤ 10 m su tutto il
  bordo; (scena) il pedone si ferma contro il recinto; pad 7 e 8.
- `tests/test_outpost_layouts.gd`: per i due avamposti: stanze, raggiungibilità dall'airlock, angoli chiusi,
  uscita nell'airlock.
- `tests/test_outpost_interior.gd`: la porta interna si apre; il pedone non attraversa il portello.
- `tests/test_game_mode.gd` (toccato): `K AIRLOCK` vicino al portello; K entra e K esce davanti al portello; H non
  vale sul pad del telescopio.
- `tests/test_flight_computer.gd` / `test_nav_targets.gd` (toccati): i bersagli nuovi.
- Prova GPU: i due siti da fuori, le due sale da dentro.

## Fuori da questo lavoro

- Persone; animazione di Eagle cargo e nastro; rover che entra nel recinto; esplosione dell'Area 2.

## Cambiato durante l'esecuzione

- **Costruttore comune:** `AlphaInterior` ha preso da Selene materiali, stanze, pareti, porte, arredi, finestra,
  luci; Selene ne è una sottoclasse e i suoi test sono rimasti verdi. Le porte possono dare sull'esterno
  ("hatch": il portello, mai aperto dentro).
- **Varco del recinto** largo 12 m (più del passo dei pali, 10 m), sul lato nord del braccio est, verso il
  deposito.
- **Torri faro:** la faccia nascosta era al buio alla prova GPU; 3 torri al telescopio e 4 all'Area 2 con una luce
  ciascuna (150 m).
- **Vista dalla vetrata del telescopio:** la parabola dipinta più in basso e più grande, perché la finestra mostra
  la fascia centrale dello sfondo.
- **Prova GPU:** i due siti da lontano e da terra, il recinto, il deposito, le due sale e gli airlock.
