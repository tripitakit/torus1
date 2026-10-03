# Interno: treno sulla spina dell'asse — progetto

Pezzo 2 di 4 per popolare l'interno. Stile: low poly molto sci-fi, come gli edifici e le auto. Vincolo:
nessun calo sensibile di FPS.

## Scelte dell'utente

- **Spina lungo l'asse**, continua attraverso sezioni e ponti.
- **Collisione** per treni, piloni, stazioni e atri.
- **2 convogli per sezione** (uno per senso), **2 stazioni** per sezione.
- **Un pilone per stazione con ascensore**: è da lì che salgono e scendono i passeggeri.

## Geometria (`scripts/spine_train.gd`)

- **Spina**: trave a sezione esagonale, mezza larghezza 10 m, alta 8 m, a `SPINE_RADIUS` 120 m dall'asse, all'angolo
  `SPINE_ANGLE` = centro della colonna di lotti 36 (36,5 / 48 di giro). Così il pilone cade al centro di un
  lotto, mai su una strada. Soli (globi di 30 m sull'asse) a 90 m; nei ponti (tubo di 600 m) passa sopra la
  piattaforma d'attracco. Strisce luminose d'accento lungo gli spigoli. Un pezzo per sezione e uno per ponte,
  ciascuno con una collisione a scatola.
- **Binari**: due, ai fianchi della spina (±14 m di lato), così i treni si vedono anche dal suolo.
- **Stazioni**: piattaforma di 200 × 50 m attorno alla spina, nel punto della stazione.
- **Scelta delle stazioni** dalla mappa: nella colonna di lotti sotto la spina, una stazione nella prima metà
  (lotti lungo 8–35) e una nella seconda (44–71). Si preferisce la città, poi un paese, il più vicino a 1/3
  (o 2/3) della sezione; altrimenti proprio a 1/3 e 2/3. Così fra due fermate ci sono sempre almeno 4 km, anche
  attraverso un ponte.
- **Pilone**: prisma esagonale di 8 m di raggio, dal suolo (quota vera della mappa, anche sui monti) alla
  piattaforma. Gli edifici del lotto vengono tolti.
- **Ascensore**: due cabine sulle facce opposte, a fase opposta. Salgono a 40 m/s con avvio e frenata dolci e
  si fermano 10 s in alto e 10 s in basso. Le muove il processore: sono poche.
- **Atrio**: sala esagonale di 25 m di raggio e 12 m di altezza alla base del pilone.

## Orario (deterministico, dal tempo di gioco)

- Velocità di crociera 100 m/s, accelerazione 2,5 m/s² (2 km per frenare o ripartire), sosta 20 s.
- Un **periodo** va dal centro di un ponte al successivo (P = sezione + ponte). Le fermate sono 2 per
  periodo, ognuna ad almeno 2 km dalle pareti, quindi il tempo per attraversare un periodo è uguale per tutti:
  `T = P / v + 2 v / a + 2 · sosta`.
- Ogni periodo ha sempre un treno per senso, e tutti i treni dello stesso senso passano al centro dei ponti
  nello stesso istante, a velocità di crociera. Quando un treno lascia la sezione k, quello della sezione k+1
  riparte dallo stesso punto: per chi guarda è lo stesso treno. Il senso opposto è sfasato di T/2.
- `progress(tau, stops, P)`: distanza percorsa nel periodo all'istante `tau` (crociera, frenata, sosta, ripartenza).

## Treni

- 6 vagoni da 24 m, circa 150 m in tutto: corpo esagonale sfaccettato, musi affusolati in testa e in coda,
  fascia di finestrini (accesi di sera, come gli edifici), striscia d'accento sotto, faro bianco davanti e
  rosso dietro.
- Ogni treno è un `AnimatableBody3D` senza `sync_to_physics`: viene spostato e non spinto, perché un corpo
  cinematico che salta trasforma il salto in velocità e allarga la collisione su tutto il tragitto. Ha una
  scatola di collisione e lo sposta il `_physics_process` del mondo interno. Figlio della sua sezione.

## Luce

- Spina, piloni, stazioni, atri, cabine e treni usano uno shader `unshaded` illuminato dall'ora
  (`interior_hour.gdshaderinc`), come le auto: un oggetto lungo 20 km sarebbe raggiunto da 20 soli (il
  limite è 8, e ognuno è una passata in più). Le facce rivolte all'asse sono più chiare.

## Test

- `test_spine_train`: scelta delle stazioni (città prima, margini, 4 km), `progress` (fermate di 20 s nel
  punto giusto, crociera ai bordi, T costante), continuità del treno fra due periodi, un treno per senso.
- `test_interior_world`: spina in ogni sezione e ponte con collisione, stazioni e piloni dal suolo alla spina,
  edifici tolti dal lotto, treni dove dice l'orario, cabine che si muovono.
- Prova GPU: FPS e immagini.

## Cambiato durante l'esecuzione

- **Luce delle strutture**: minimo 60% sulle facce in ombra (non 45%) e spina grigio chiaro (0,55), perché da
  sotto, cioè da dove la si guarda, era quasi nera.
- **Il test delle 8 luci** salta ogni oggetto con un materiale `unshaded` (globi, auto, spina, stazioni,
  treni): non è illuminato dalle luci vere.
- **Misure FPS** (A/B nella stessa sessione, vsync spento, 5 s per inquadratura): all'attracco 202–205 senza
  treno e strutture, 190–196 con (circa −5%: la spina passa sopra la piattaforma); volo basso 130–135 contro
  128–133; dall'alto 137–139 contro 136. La macchina oggi rende meno anche senza treno (volo basso 146–148 nel
  pezzo 1): i confronti vanno fatti nella stessa sessione.
- **Binario e piloni più leggeri e sci-fi** (richiesta dell'utente: erano "pesanti"; scelto lo stile "anelli e
  rotaie luminose"). Al posto della trave esagonale con i ripiani: nucleo sottile (3 m), due rotaie luminose
  per binario (sotto e sopra il treno, che corre sospeso fra le due), anelli esagonali sottili ogni 80 m attorno
  a nucleo e treni, con nodi luminosi agli spigoli (un MultiMesh per pezzo). Collisione: nucleo e rotaie.
  Pilone: albero affusolato (raggio da 4 a 2,5 m) con tre pinne sottili, anelli luminosi ogni 150 m e guide
  luminose per le cabine; mesh fatta per ogni stazione con la sua lunghezza. Piattaforma sottile (1,2 m) con i
  bordi luminosi; atrio basso con fascia di vetro e bordo del tetto luminoso.
