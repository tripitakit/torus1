# Persone animate nelle sezioni — progetto

Le persone dentro le sezioni (pedoni dei paesi e delle città, gente sui moli, passeggeri degli ascensori) oggi
sono sagome a birillo. Al loro posto un umano low poly CC0 che cammina.

## Scelte dell'utente

- Umano low poly di Quaternius ("Animated Human", CC0), non lo stile giocattolo.
- Colori come oggi: tute bianche, arancio, ciano, grigie.
- Spec, piano e implementazione nella stessa sessione.

## Il modello

- `assets/people/animated_human.glb`: Quaternius, "Animated Human", pubblico dominio (CC0), da poly.pizza.
  Credito nel README.
- Una mesh skinnata: 1.578 triangoli, 4.733 vertici (facce piatte), 41 ossa, nessuna texture. Animazioni:
  Walk (ciclo di 1 s), Idle (10 s), Run, Working, Jump, Punch, Death. Si usano Walk e Idle.
- Si legge a runtime con `GLTFDocument` dal file grezzo (come `heights.bin` della luna, niente import
  dell'editor).

## Perché una texture di animazione

I pedoni sono MultiMesh mossi dallo shader di `LoopTraffic` (nessun nodo per persona): uno scheletro lì non
funziona. La camminata si "cuoce" in una texture: per ogni fotogramma la posizione e la normale di ogni vertice.
Lo shader legge la riga del fotogramma giusto. Funziona con `gl_compatibility` (`texelFetch` nel vertex
shader).

## Cottura (`scripts/people_model.gd`, funzioni pure)

- **Skinning sulla CPU:** per ogni fotogramma si mette lo scheletro nella posa della clip e si calcola ogni
  vertice come somma pesata (4 ossa) di posa dell'osso × inverso della posa di riposo. Nessuna GPU: si testa
  headless.
- **Fotogrammi:** Walk, 16 fotogrammi sul ciclo di 1 s. Idle: una posa ferma (fotogramma 0) per i passeggeri.
- **Misura e verso:** scalato a 1,8 m di altezza (piedi a y = 0 nella posa di riposo), muso verso +Z come la
  sagoma di oggi; centrato sui piedi. Le radici della clip che spostano il bacino in avanti si annullano (la
  camminata resta sul posto; avanza lo shader).
- **Parti (UV.x come oggi):** dall'osso che pesa di più su ogni vertice. Gambe e piedi: parte scura (1); busto,
  braccia, mani e collo: tuta (0); testa: casco della tuta (0) con una visiera luminosa (2) sui vertici
  della faccia (davanti, all'altezza degli occhi).
- **Texture:** RGBA in float (`Image.FORMAT_RGBAF`), posizione in RGB; le normali in una seconda texture uguale.
  Una texel per vertice per fotogramma, a righe di 1.024 texel (4.733 × 16 = 75.728 texel, 74 righe). L'indice
  della texel del vertice nel fotogramma 0 sta in UV.y della mesh.
- **Prodotti:** `walk_mesh()` (la mesh in posa di riposo, con UV), `walk_textures()` (posizioni, normali),
  `idle_mesh()` (mesh statica nella posa Idle, per i passeggeri). Calcolati una volta, alla prima richiesta.

## Disegno

- **Shader:** il materiale dei pedoni (`LoopTraffic.material` con un'opzione "animato") prende la posa del
  vertice dalla texture invece di `VERTEX`. Fotogramma: la fase del ciclo = strada percorsa / passo, con il
  passo di 1,4 m per ciclo (la velocità del pedone la sa lo shader: lunghezza del giro × giri l'ora). Così i
  piedi non scivolano. Fra due fotogrammi si interpola. Il sobbalzo (`bob`) di oggi si toglie per i pedoni
  animati: lo fa la camminata.
- **Due livelli:** costo per persona da ~40 a ~1.600 triangoli. Entro **80 m** dalla camera il modello
  animato; oltre, la sagoma di oggi. Due MultiMesh per pezzo di terreno sullo stesso buffer: quello animato con
  `visibility_range_end` 150 m (per pezzo) e lo shader che lo fa sparire oltre 80 m (per persona); quello
  semplice che sparisce entro 80 m (per persona). Stessa regola per i moli.
- **Passeggeri degli ascensori:** la mesh Idle al posto della sagoma, con i materiali di oggi per tuta.

## Test

TDD; solo i test nuovi o toccati.

- `tests/test_people_model.gd`: il modello si legge; alto 1,8 m con i piedi a y = 0; muso verso +Z (le punte dei
  piedi davanti alle caviglie); a metà ciclo i piedi si scambiano (nel fotogramma 0 il sinistro è davanti, a
  metà ciclo il destro); il bacino non avanza nel ciclo; le parti (gambe scure, testa con visiera); la texture
  del fotogramma 0 riproduce la mesh nella posa skinnata; la mesh Idle è ferma e alta 1,8 m.
- `tests/test_interior_world.gd` (toccato): un pezzo di terreno con pedoni ha i due MultiMesh sullo stesso buffer;
  i passeggeri usano la mesh Idle.
- **Prova GPU:** scatti ravvicinati in un paese, su un molo, in un ascensore; FPS in città prima e dopo.

## Fuori da questo lavoro

- Corsa, lavoro, saluti; persone che si fermano o si girano verso il giocatore.
- Più modelli (donne, bambini); vestiti diversi oltre al colore della tuta.
- Ombre delle persone.
