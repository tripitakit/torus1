# Interno: traffico aereo dei cruiser interni — progetto

Pezzo 3 di 4 per popolare l'interno. Stile: low poly molto sci-fi, come auto, treni ed edifici. L'utente ha
chiesto di procedere senza domande: i punti sotto sono default scelti da Claude, da rivedere in gioco.

## Rotte (`scripts/air_traffic.gd`)

- **Circuiti lungo la sezione**: 6 per sezione, a forma di stadio nel piano srotolato (x intorno, z lungo):
  due tratti dritti lungo z a ±80 m di lato e due curve a semicerchio di 80 m vicino alle pareti (da 1,5 a
  3 km da ciascuna). Angoli distribuiti a 1/6 di giro l'uno dall'altro, a partire da mezzo passo dalla spina:
  stanno sempre ad almeno 30° dai piloni.
- **Anelli intorno**: 4 per sezione, cerchi attorno all'asse a z fissa, a più di 300 m dalle stazioni (lì c'è
  il pilone). Il senso di marcia si alterna.
- **Quota**: la più alta del terreno sotto la rotta (campioni ogni 100 m), più 350 m, più 0–300 m a caso: sopra
  le torri (300 m al massimo) e sopra i monti.
- **Cruiser**: 8 per circuito e 12 per anello, cioè 96 per sezione, a distanza uguale. Velocità 70–90 m/s sui
  circuiti e 60–80 m/s sugli anelli. Nelle curve dei circuiti si inclinano di 30° verso l'interno.
- **Tutto deterministico** dal numero della sezione e dal tempo di gioco.

## Disegno

- **Il processore calcola le posizioni** a ogni frame: sono solo circa 300 cruiser caricati, una posizione
  ciascuno, scritte nel buffer di un MultiMesh per sezione. Costa poco ed è più semplice di un moto tutto
  nello shader con tre tipi di curva.
- **Modello**: dardo sfaccettato con cupola, due gondole motore con scarico luminoso nel colore d'accento,
  luci di posizione rossa e verde alle estremità delle ali. Circa 9 m di lunghezza. Tinta per cruiser dalla
  stessa tavolozza delle auto.
- **Luci**: un secondo MultiMesh di punti (dimensione minima in pixel) con lampeggio bianco, così i cruiser
  lontani si vedono, di notte molto più che di giorno.
- **Shader** `unshaded` illuminato dall'ora, come le altre strutture.
- **Niente collisioni.**

## Test

- `test_air_traffic`: rotte (numero, distanza dalla spina, dalle stazioni e quota sopra il terreno lungo
  tutta la rotta), percorso continuo (anche nelle curve e al giro), velocità, inclinazione in curva.
- `test_interior_world`: MultiMesh dei cruiser e delle luci in ogni sezione, cruiser che si muovono.
- Prova GPU: immagini e FPS a confronto nella stessa sessione.

## Cambiato durante l'esecuzione

- **Moto nello shader, non nel processore**: calcolare in GDScript circa 300 posizioni a ogni frame costava
  1–2 ms. Ogni cruiser porta la sua rotta nei 9 numeri a 32 bit della base del transform dell'istanza
  (traslazione 0); la sezione si sposta solo lungo z, quindi `MODEL_MATRIX[3]` dà la sua posizione. Il numero di
  giri all'ora è intero, così il ricominciare di `TIME` non si vede. `pose` e `pose_from_data` sono le copie
  in GDScript per i test.
- **Monti**: nessuna rotta su terreno più alto di 600 m: un circuito sopra un picco di 1.500 m passerebbe a
  150 m dall'asse. Ogni circuito si sposta al primo angolo libero a passi di 10° (a 30° dalla spina e a 40° dagli
  altri circuiti); nelle sezioni con la catena montuosa possono essere meno di 6. Gli anelli volano sempre sopra
  tutti i circuiti della sezione (150 m), così le rotte non si incrociano mai.
- **Lampeggio**: 2,5 m, acceso 0,2 s ogni 1,4 s (prima 1,5 m e 0,12 s: da lontano si vedeva poco).
- **Misure FPS** (A/B nella stessa sessione, 5 s per inquadratura): attracco 209–210 senza cruiser e 200–211
  con; volo basso 131–139 contro 139–141; dall'alto 144–147 contro 141–142; in mezzo al traffico aereo 117–118
  contro 114–117. Il costo resta dentro il rumore delle misure (0–4%).
- **Tempo di costruzione all'attracco**: 2,55 s (limite del test: 3 s); le rotte si calcolano nel worker.
- **Cruiser più sci-fi, con ali corte** (richiesta dell'utente). Dardo sfaccettato di 9,4 m, apertura sotto i
  5,5 m (`MAX_SPAN`, controllato dal test): ali tozze piegate in giù con una gondola a ogni estremità (luce
  rossa a sinistra e verde a destra, scarico luminoso dietro), due derive inclinate con il bordo luminoso, un
  grande ugello esagonale luminoso in coda, strisce d'accento sui fianchi.
- **Numero di cruiser** (richiesta dell'utente: 96 erano troppi). Per sezione un numero casuale fra 30 e 60
  (`CRAFT`, dal numero della sezione), diviso fra le rotte in proporzione alla lunghezza, almeno 2 per rotta.
