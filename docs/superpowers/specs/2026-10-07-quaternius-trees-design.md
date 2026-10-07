# Alberi di Quaternius nelle sezioni — progetto

Gli alberi delle colline e delle montagne di Torus1, vicino alla camera, sono i modelli low poly con texture di
Quaternius (CC0, poly.pizza) al posto delle forme a tornio generate.

## Scelte dell'utente

- Famiglia **con texture**: pini, betulle, aceri, alberi "normali", alberi secchi (5 varianti ciascuno).
- Modelli dettagliati entro **~500 m**.
- Implementazione nativa.

## Modelli (`scripts/tree_models.gd`, `assets/trees/*.glb`)

- `pine.glb`, `birch.glb`, `maple.glb`, `normal.glb`, `dead.glb`, letti a runtime con `GLTFDocument`. Ogni
  variante: la mesh con la sua posizione nel file applicata, portata ad **altezza 1** con la **base del tronco
  sull'origine** (media dei vertici più bassi), così l'istanza la scala all'altezza dell'albero (10–25 m).
- Materiali: uno shader nostro per superficie (texture della corteccia o delle foglie; foglie con ritaglio della
  trasparenza, senza culling) che nasconde l'albero oltre `TREE_DETAIL` dalla camera.
- **Quale albero:** le conifere → pini; le latifoglie → aceri, normali e betulle; **5% secchi** vicino al limite del
  bosco (oltre 450 m di quota). Variante scelta da un hash della posizione: stesso albero, stessa variante.

## Livelli

- **Entro `TREE_DETAIL` (500 m):** i modelli di Quaternius. Un gestore (`scripts/near_trees.gd`) li ricostruisce
  attorno alla camera ogni `REBUILD_STEP` (40 m) di spostamento: per ogni pezzo di terreno con alberi entro la
  portata, su un thread a parte, sceglie gli alberi entro `TREE_DETAIL + REBUILD_STEP + 20` e li mette in un
  MultiMesh per variante, figlio del pezzo (le sue coordinate: lo spostamento dell'origine non li sfasa).
- **Da 500 m a 3 km:** le forme semplici di oggi; il loro shader le nasconde entro `TREE_DETAIL` (stesso taglio: nessun
  albero doppio, nessun buco).
- **Oltre 3 km:** le sagome lontane di oggi.

## Test

- `tests/test_tree_models.gd`: 25 varianti (5 per tipo); altezza 1, base del tronco sull'origine; foglie con
  ritaglio; variante fissa per posizione; tipi per conifere, latifoglie e secchi.
- `tests/test_near_trees.gd`: la scelta prende solo gli alberi entro la portata, tutti, divisi per variante con le
  stesse trasformazioni; il gestore costruisce i MultiMesh nei pezzi vicini.
- `tests/test_interior_world.gd` (toccato): lo shader delle forme semplici ha il taglio a `TREE_DETAIL`.
- Prova GPU: un bosco da terra e dal cruiser, FPS.

## Cambiato durante l'esecuzione

- **Distanza 350 m invece di 500:** sopra un bosco fitto, a 500 m 2.709 alberi dettagliati davano 40 FPS; a 350 m
  1.712 alberi, 60 FPS (vsync). Una costante (`TreeModels.DETAIL`), il taglio delle forme semplici la segue.
- **Foglie viste da dietro:** lo shader gira la normale delle facce posteriori (prima macchie nere fra le foglie).
- **Colori:** sono quelli delle texture di Quaternius: aceri autunnali (rossi, arancio), betulle gialle, alberi
  "normali" verde acceso, pini verde chiaro.
- **Prova GPU:** sorvolo di un bosco a 30 m dal cruiser interno.

## Dopo la prova dell'utente: impostori

L'utente ha visto il confine fra modelli e forme semplici (metà collina di un tipo e metà dell'altro, un confine
che segue la camera, alberi che spuntano). Ora:

- **Impostori** cotti una volta sulla GPU (`tools/bake_tree_impostors.gd`) dagli stessi modelli: vista di lato e
  dall'alto di ogni variante, senza luce, in due atlanti 5 × 5 (`assets/trees/impostors_side.png`, `..._top.png`),
  i pixel trasparenti col colore medio della variante (salvato in `impostors.json`). Ogni albero lontano è due
  pannelli incrociati e uno orizzontale (6 triangoli) con la sua variante (scritta nel colore dell'istanza dai pezzi
  di terreno; `NearTrees` la legge da lì: vicino e lontano coincidono).
- **Passaggi sfumati** pixel per pixel (retinatura dipendente dalla distanza, pixel complementari): modelli →
  impostori negli ultimi 50 m prima di `DETAIL`; impostori → sagome lontane colorate come la variante negli
  ultimi 300 m prima di 3 km.
- **`DETAIL` a 250 m:** volando bassi radenti sul bosco, a 350 m si scendeva a 30 FPS (vsync); a 250 m 60.
- **Luce degli impostori:** normale verso l'alto dell'albero su entrambe le facce (visti da dietro erano scuri).
- **Prova GPU:** avvicinamento a un bosco da 1,5 km a 120 m senza confini visibili; a 1,5 km 46 FPS come su master
  (44,5), non un peggioramento.
