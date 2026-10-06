# Velocità più alte e teletrasporto di debug — progetto

## Scelte dell'utente

- Limiti **per quota**: luna 800 m/s sotto 2 km, fino a 15.000 m/s in alto; spazio aperto 50.000 m/s; vicino a
  Torus1 e ai portali 1.000 m/s.
- Teletrasporto di debug sui tasti **1–9** con una piccola legenda nell'HUD, destinazioni:
  1 Torus1 davanti al primo attracco, 2 dentro una sezione col cruiser interno, 3 a piedi su una piazzola di paese,
  4 Eagle posata sul pad 1 di Selene, 5 dentro Selene (hangar), 6 Eagle sul pad dell'UltraTelescopio, 7 Eagle sul
  pad dell'Area 2, 8 a piedi davanti all'airlock dell'Area 2, 9 Eagle in orbita bassa (5 km sopra Selene).
- Spec, piano e implementazione nativa.

## Limiti di velocità (`speed_limit.gd`)

La nave frena a 1.500 m/s² (10× la spinta base). Una zona lenta va annunciata da lontano, altrimenti a 50 km/s
la si attraversa prima di frenare (il riferimento della luna si aggancia sotto 30 km; la zona di Torus1 vale
entro 20 km). Ogni zona lenta diventa una **curva di frenata**: il limite a distanza `d` dalla zona è la velocità
da cui si frena in tempo, con un terzo della frenata (`SAFE_BRAKE` = 500 m/s²):

    limite(d) = sqrt(basso² + 2 · SAFE_BRAKE · d)

- **Torus1 e portali:** 1.000 m/s entro 20 km; oltre, la curva dalla distanza dai 20 km.
- **Luna:** 800 m/s sotto 2 km di quota; oltre, la curva dalla quota sopra i 2 km (a 30 km ~5,3 km/s, a 100 km
  ~9,9 km/s). Vale anche fuori dal riferimento della luna (avvicinandosi).
- **Tetto:** 15.000 m/s nel riferimento della luna, 50.000 m/s fuori.
- Il limite è il più basso di quelli che valgono (come oggi).

## Teletrasporto (`debug_teleport.gd`, `GameMode`)

- Azioni `teleport_1` … `teleport_9` sui tasti 1–9 (codici 49–57, oggi liberi).
- Da qualunque modo: prima si torna a bordo dell'Eagle, fuori da interni, basi e avamposti (le uscite che il gioco
  ha già); poi la destinazione; il tutto dentro la dissolvenza di 0,4 s. Ignorato durante uno schianto o una
  dissolvenza.
- Legenda in alto a destra (sotto il riquadro del bersaglio), carattere piccolo, sempre visibile:
  `1 DOCK  2 SEZIONE  3 PIAZZOLA  4 SELENE  5 HANGAR  6 TELESCOPIO  7 AREA 2  8 AIRLOCK  9 ORBITA`.

## Test

- `test_speed_limit.gd` (toccato): valori per zona e per quota; frenata simulata da 15 km/s verso la luna che
  arriva sotto i 2 km a non più di 800 m/s (e lo stesso verso Torus1 da 50 km/s).
- `test_speed_limit_physics.gd` (toccato): la spinta piena si ferma al limite del punto; la frenata vicino
  all'anello scende a 1.000.
- `tests/test_debug_teleport.gd`: ogni tasto porta nel modo e nel posto giusti, partendo anche da dentro una
  sezione, da Selene, a piedi e da un avamposto; la legenda c'è.

## Cambiato durante l'esecuzione

- **Legenda** in alto a destra: in basso a destra copriva la navball.
- **Test della nave:** la spinta piena ora raggiunge il nuovo limite dello spazio aperto in 20 s (prima 10 s).
- **Prova:** teletrasporto 7 sulla GPU (Eagle posata sul pad 8, legenda a schermo); test di tutti i tasti.
