# Viaggio continuo dentro la stazione (pezzo C)

## Contesto

Il pezzo A (`2026-09-24-station-interior-access-design.md`) ha costruito il
mondo interno: il bridge d'attracco e le due sezioni che collega. Il pezzo B
(`2026-09-24-section-terrain-design.md`) ha riempito le sezioni di campi,
strade, laghi, paesi e città, generati dal numero della sezione.

Oggi le due sezioni sono chiuse all'estremità lontana. Questo pezzo apre i
passaggi: dentro si vola di sezione in sezione, attraverso i bridge, lungo
tutto l'anello. Il mondo interno si costruisce un po' alla volta mentre si
vola, senza scatti.

## Decisioni prese con l'utente

- **Passaggi:** sempre aperti. Tutti e due i tappi di ogni sezione hanno il
  foro del bridge.
- **Approccio:** una catena di sezioni e bridge caricata a pezzi mentre si
  vola (approccio 1).
- **Velocità:** rampa a gradini, in comune fra le due navette.
  - Internal-cruiser: 1x → 10x fra 0 e 5 s, poi resta a 10x (circa 1 km/s).
  - Void-cruiser: 1x → 10x fra 0 e 5 s, poi 10x → 100x fra 5 e 10 s
    (circa 21,6 km/s).
- **Uscita:** da qualsiasi bridge. Si esce all'anello d'attracco del bridge
  in cui ci si trova.

## Scope

Dentro:
- Catena dritta di sezioni e bridge lungo l'asse, caricata e scaricata
  attorno alla navetta.
- Piano delle sezioni generato in un thread; blocchi vestiti pochi per frame.
- Spostamento dell'origine lungo l'asse.
- Luci che si spengono in dissolvenza oltre 25 km.
- Un dock su ogni bridge; uscita dal bridge più vicino.
- Rampa a gradini per le due navette.
- Correzione: `GameMode` libera il mondo esterno se il gioco si chiude
  mentre si è dentro.

Fuori:
- Vedere oltre le sezioni caricate: in fondo al tubo più lontano c'è il buio.
- Velocità speciali nei bridge.
- Mappa o indicatore della posizione sull'anello (dentro non c'è HUD).
- La piega di 0,18° fra una sezione e l'altra: la catena resta dritta.
- Porte o chiusure nei passaggi.

## Catena

Il mondo interno è una fila dritta lungo l'asse Z. Ogni pezzo ha un
**posto** (un intero) contato dal bridge d'attracco.

- **Passo** `P = lunghezza sezione + lunghezza bridge` (circa 21 834 m).
- **Bridge al posto `r`:** centro a `z = -r · P`. Il bridge d'attracco è al
  posto 0, centrato sull'origine.
- **Sezione al posto `s`:** centro a `z = -(s + 0,5) · P`, fra il bridge `s`
  (dal lato +Z) e il bridge `s + 1` (dal lato -Z).
  - La sezione al posto 0 è quella "davanti" del pezzo A; quella al posto -1
    è quella "dietro".
- **Numero vero sull'anello:**
  - bridge al posto `r`: `(bridge d'attracco + r) mod 2000`;
  - sezione al posto `s`: `(bridge d'attracco + s + 1) mod 2000`.
  - Dopo la 1999 viene la 0: si può fare il giro completo.
- I pezzi sono figli di un nodo `Chain`. Nomi: `Chain/Section_<posto>` e
  `Chain/Bridge_<posto>` (per esempio `Section_-1`).
- Ogni sezione ha il suo nodo al proprio centro. Contiene i blocchi
  (`Chunk_aa_bb`, come nel pezzo B), i tappi `CapBehind` (lato +Z, guarda
  verso -Z) e `CapAhead` (lato -Z, guarda verso +Z), entrambi con il foro
  del bridge, e i soli `Sun_kk`.
- Ogni bridge ha il suo nodo al proprio centro. Contiene i 4 pezzi di tubo
  (`Segment_k`), le 3 luci (`Light_k`) e il dock (`Dock/Platform`,
  `Dock/Light`, `Dock/Sign`).

## Caricamento

Le distanze sono misurate lungo l'asse, fra la navetta e il centro della
sezione.

- **Si carica** ogni sezione entro 1,25 P. Sono 2 o 3 sezioni: quella in
  cui si è, più una o due vicine.
- **Si scarica** una sezione oltre 1,5 P. Il margine evita di caricare e
  scaricare di continuo al confine.
- **Bridge:** esistono i bridge ai due capi di ogni sezione caricata. Un
  bridge costa meno di 1 ms e si costruisce subito, tutto intero.
- **Una sezione nuova**, passo per passo:
  1. nodo, tappi e soli subito;
  2. piano generato in un thread del `WorkerThreadPool` (circa 70 ms, fuori
     dal gioco);
  3. poi al massimo 16 blocchi vestiti per frame, i più vicini alla navetta
     per primi (misurato: circa 13 ms per frame nel caso peggiore).
- **Una sezione da scaricare:** al massimo 32 blocchi liberati per frame
  (misurato: circa 7 ms), poi il nodo con tappi e soli.
  - Una sezione il cui piano è ancora in generazione non si scarica
    finché il thread non ha finito.
- **All'attracco** le due sezioni accanto al bridge si costruiscono subito,
  intere, dietro la dissolvenza, come nel pezzo B.
- **Chiusura del mondo interno:** prima di liberarlo si aspetta la fine dei
  thread ancora al lavoro.
- **Tempi di volo:** a 1 km/s una sezione nuova comincia a caricarsi circa
  16 s prima di arrivarci; il caricamento dura meno di 1 s.

## Spostamento dell'origine

La catena si allunga di 21,8 km a ogni sezione. Per non allontanarsi troppo
dall'origine:
- quando la navetta supera 10 km dall'origine lungo Z, il nodo `Chain` e la
  navetta si spostano insieme della stessa quantità lungo Z;
- l'asse resta a `x = y = 0`;
- lo spostamento avviene nel passo di fisica, prima che la navetta si muova.
  I corpi fissi seguono il nodo padre (verificato nel pezzo A).

## Luci

- Ogni luce del mondo interno (soli, luci dei bridge, luci dei dock) si
  spegne in dissolvenza fra 24 e 25 km dalla camera
  (`distance_fade_begin` 24 000, `distance_fade_length` 1000).
- Con 3 sezioni e 4 bridge caricati le luci sono 76. Entro 25 km da
  qualunque punto della catena ne restano circa 54. Il limite del motore
  è 64.
- Il limite di 8 luci per oggetto resta verificato con la regola del cubo
  (pezzo B), sulla catena caricata.

## Dock e uscita

- Ogni bridge ha il suo dock, uguale a quello del pezzo A.
- Il cartello si accende solo al dock più vicino alla navetta, e solo se la
  navetta è entro 150 m e sotto 20 m/s (stessa regola dell'attracco).
- Con F si esce all'anello d'attracco del bridge di quel dock (numero vero
  sull'anello), 60 m fuori, come nel pezzo A.
- All'ingresso si parte sempre dal dock del posto 0.

## Rampa di spinta

- La rampa passa dal void-cruiser alla classe comune `flying_craft.gd`.
  - Una lista di gradini (i moltiplicatori da raggiungere) e la durata di
    un gradino (5 s).
  - Dentro un gradino il moltiplicatore cresce in linea retta da quello
    precedente (1x all'inizio).
  - Rilasciare il tasto o invertire la direzione fa ripartire da 1x.
- Void-cruiser: gradini 10x e 100x. Internal-cruiser: solo 10x.
- Velocità massime (attrito 0,5, massima = spinta / ln 2):

  | Navetta | Base | 10x | 100x |
  |---|---|---|---|
  | Void-cruiser | 216 m/s | 2,2 km/s | 21,6 km/s |
  | Internal-cruiser | 101 m/s | 1 km/s | — |

- A 21,6 km/s il void-cruiser fa 360 m per frame. La collisione segue tutto
  lo spostamento del frame: una prova ha confermato che rimbalza sulla
  sezione.
- Senza spinta la velocità si dimezza ogni secondo: da 21,6 km/s si scende
  sotto i 20 m/s in circa 10 s.

## Correzione: mondo esterno alla chiusura

Mentre si è dentro, il mondo esterno è fuori dall'albero dei nodi e lo tiene
solo `GameMode`. Se il gioco si chiude in quel momento, quei nodi non si
liberano mai (all'ultima chiusura circa 6000 oggetti persi). `GameMode`, alla
sua distruzione, libera i nodi che ha staccato.

## Testing

- **Catena, funzioni pure:** posizione di bridge e sezioni per posto;
  numero vero sull'anello, anche quando il giro si chiude e per posti
  negativi; bridge più vicino a un punto; sezioni entro una distanza; bridge
  delle sezioni caricate.
- **Rampa:** 1x a 0 s, 5,5x a 2,5 s, 10x a 5 s, 55x a 7,5 s, 100x a 10 s e
  oltre; con il solo gradino 10x, ancora 10x a 20 s. Internal-cruiser circa
  1010 m/s dopo 20 s; void-cruiser circa 21,6 km/s dopo 20 s.
  Void-cruiser a piena velocità contro una sezione: rimbalza.
- **Mondo interno, fuori dall'albero:**
  - all'attracco ci sono le sezioni ai posti -1 e 0, intere, e i bridge -1,
    0 e 1;
  - sezioni generate dai numeri giusti;
  - tutti e due i tappi aperti, rivolti verso l'interno;
  - un dock per bridge; cartello acceso solo al dock indicato;
  - piano generato nel thread uguale a quello generato direttamente;
  - caricando attorno a un punto lontano, le sezioni lontane si scaricano e
    compaiono quelle vicine;
  - ogni luce ha la dissolvenza a 25 km; al massimo 64 luci entro 25 km da
    ogni punto campionato; al massimo 8 luci per oggetto;
  - costruzione all'attracco sotto 3 s.
- **Con frame reali:**
  - volando lungo la catena la sezione in cui si entra è sempre già pronta,
    e quelle lontane dietro spariscono;
  - nessun frame oltre 50 ms durante il caricamento;
  - un passo di caricamento veste al massimo 16 blocchi, i più vicini per
    primi;
  - spostamento dell'origine: navetta e terreno restano allineati;
  - l'internal-cruiser attraversa un bridge ed entra nella sezione dopo
    senza urti;
  - l'internal-cruiser rimbalza sul tappo attorno al foro.
- **Modalità di gioco:** uscita dal dock di un altro bridge all'anello
  giusto (anche per il bridge 1999); cartello acceso solo al dock vicino;
  mondo esterno liberato quando la scena si libera mentre si è dentro.
- Tutti i test dei pezzi A e B aggiornati ai nuovi nomi e alla nuova
  interfaccia.

## Verifica

Avvio headless della scena senza errori, più un render offscreen (xvfb) da
dentro un bridge verso la sezione successiva, da controllare a occhio prima
di passarlo all'utente.

## Rischi noti

- **Dissolvenza delle luci e limite di 64:** il test conta le luci entro
  25 km, come se il motore scartasse quelle spente prima di contare. Se
  invece le contasse, il render mostrerebbe zone buie: il rimedio è ridurre
  la distanza di dissolvenza.
- **Buio in fondo:** oltre le sezioni caricate non si vede nulla. Accettato.
- **Costo del frame su macchine più lente:** il budget di 16 blocchi per
  frame è una costante, facile da ridurre.
