# Interno: barche sui laghi e attracco animato — progetto

Pezzo 4 di 4 per popolare l'interno. Stile low poly sci-fi. L'utente ha chiesto di procedere: le scelte sotto
sono default di Claude, da rivedere in gioco.

## Una sola tecnica: anelli rettangolari arrotondati (`scripts/loop_traffic.gd`)

- Un percorso è un rettangolo (x0, z0, larghezza, altezza) con gli angoli arrotondati (raggio uniforme per
  materiale). Si percorre in un senso o nell'altro (giri all'ora negativi = senso opposto).
- **Lo muove solo lo shader**, come i cruiser: i dati del percorso stanno nella base del transform dell'istanza
  (9 numeri a 32 bit): (x0, z0, larghezza), (altezza, fase, giri all'ora), (id, quota o raggio, modo). Il nodo si
  sposta solo per traslazione. Giri all'ora interi, così il ricominciare di `TIME` non si vede.
- **Due modi**:
  - sul cilindro, per le barche: x è l'arco a raggio R, sull'acqua a quota 0;
  - piatto, per l'attracco: x e z sul piano della piattaforma, a una quota fissa.
- `pose` e `pose_from_data` sono le copie in GDScript per i test.

## Barche (`scripts/lake_boats.gd`)

- **Laghi**: gruppi di lotti d'acqua che si toccano. In ciascuno si prende il rettangolo di lotti d'acqua più
  grande.
- **Rotta**: il rettangolo rientrato di 40 m, angoli di 30 m. Si usano al massimo i 12 laghi più grandi.
- **Barche**: una ogni 500 m di rotta, almeno una per lago, al massimo 40 per sezione, a 8–12 m/s. Senso di
  marcia casuale per lago.
- **Modello**: idroscivolante sci-fi di circa 11 m: scafo a cuneo sfaccettato, cabina di vetro, pinne,
  striscia d'accento luminosa, scia bianca piatta dietro.
- Un MultiMesh per sezione, nessuna collisione.

## Attracco animato (`scripts/dock_crowd.gd`)

Sulla piattaforma di ogni ponte (60 × 60 m). Il centro, un quadrato di 24 m dove si posa la nave, resta libero.

- **Persone**: 24, a piedi a 1,2–1,6 m/s su anelli fra 14 e 25 m dal centro, nei due sensi, con un leggero
  dondolio. Figurine low poly di 1,8 m in tute bianche, arancio o ciano con visiera luminosa.
- **Carrelli**: 3 mezzi di servizio sull'anello esterno (28 m), a 5 m/s, con lampeggiante arancio.
- **Droni**: 4 droni di carico che girano in tondo (raggio 8 m) sopra gli angoli, fra 12 e 25 m d'altezza.
- Visibili fino a 600 m (`visibility_range_end`). Niente collisioni: non devono intralciare l'attracco.

## Luce

Tutti `unshaded`, illuminati dall'ora come le altre strutture dell'interno.

## Test

- `test_loop_traffic`: percorso continuo e chiuso, verso di marcia, senso opposto, dati dello shader uguali
  alla copia in GDScript, ricominciare di `TIME`.
- `test_lake_boats`: laghi e rettangoli tutti d'acqua, rotta sempre sull'acqua (con margine), numeri.
- `test_dock_crowd`: persone fuori dal centro e sulla piattaforma, carrelli sul bordo, droni sopra.
- `test_interior_world`: MultiMesh delle barche nelle sezioni con laghi, persone, carrelli e droni in ogni
  ponte.
- Prova GPU: immagini e FPS a confronto nella stessa sessione.

## Cambiato durante l'esecuzione

- **Fascia delle persone**: 14–25 m (non 27). Agli angoli arrotondati i carrelli rientrano fino a 27 m dal
  centro, e le persone potevano passarci attraverso (trovato dal test).
- **Barche**: nelle sezioni provate si raggiunge il tetto di 40 barche (i laghi sono grandi).
- **Misure FPS** (A/B nella stessa sessione, 5 s per inquadratura): attracco 207–208 senza barche e attracco
  animato, 203–207 con; volo basso 137–138 contro 137–139; dall'alto 141–144 contro 143–146. Nessuna
  differenza oltre il rumore.

## Correzioni dopo la prova in gioco (richieste dell'utente)

- **Dock dei ponti vuoto**: persone, carrelli e droni non stanno lì. "Attracco" voleva dire il molo delle barche.
- **Moli sui laghi**: per ogni lago con barche, sul lato del rettangolo navigabile, nel lotto di terra piana più
  vicino al centro del lato, c'è un pontile largo 12 m. Va dalla riva (2 m sulla terra) fino a 3 m dalla rotta,
  a 2 m sull'acqua. Sulla terra c'è una piattaforma di carico di 24 × 24 m, e gli edifici del lotto vengono
  tolti. Pontile e piattaforma hanno collisione.
- **Sosta delle barche**: a ogni giro si fermano 20 s alla punta del pontile, con frenata e ripartenza a
  0,5 m/s². È una funzione generale degli anelli (`LoopTraffic.with_stop`): la velocità di crociera è scelta
  perché il giro duri esattamente 3600 / n secondi. Le barche dello stesso lago sono sfasate di una frazione del
  giro.
- **Vita sul molo**: 8 persone sulla piattaforma, 2 carrelli che fanno la spola lungo il pontile, 2 droni che
  volano fra la piattaforma e la punta del pontile (a 15 m).
- **Scia tolta**: il triangolo piatto sull'acqua faceva z-fighting con la superficie, cioè appariva e spariva.
- **Pedoni nei paesi e nella città** (`town_walkers.gd`): 10–20 per lotto su anelli a piedi sparsi a caso negli
  spazi aperti, ad almeno 2 m dagli edifici e fuori dalle strade; di notte metà spariscono.
  - Stanno sul nodo della sezione, un MultiMesh per pezzo di terreno, visibili entro 500 m.
  - Non possono stare nel nodo del pezzo, perché quello è ruotato e lo shader degli anelli vuole un nodo
    solo traslato.
- **Finestre che "sfarfallano"**: nessuna faccia doppia negli edifici e nessun edificio sovrapposto (verificato
  sulle sezioni 1, 2, 5 e 11). La causa più probabile sono le celle delle finestre più piccole di un pixel, che
  brulicano quando ci si muove. Lo shader ora sfuma il disegno verso la media della facciata fra 3 e 1,5
  pixel per cella (`fwidth`).
- **Tempo di costruzione all'attracco**: 2,77 s (limite del test 3 s).
- **FPS** (A/B nella stessa sessione): volo basso 116–124 senza pedoni, moli e barche, 115–122 con; dall'alto
  123–130 contro 127–134. Nessuna differenza oltre il rumore.
