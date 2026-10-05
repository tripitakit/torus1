# Superficie lunare: tracce, orme, sassi e massi — progetto

Tracce del Moon Buggy e orme degli stivali sulla regolite, che restano per tutta la sessione; sassi e massi sparsi
sulla luna; i massi più grandi fermano rover e pedone.

## Scelte dell'utente

- Densità media, più alta sui bordi dei crateri giovani; quasi niente sul piazzale di Selene e sui pad.
- I massi fermano solo rover e pedone (collisioni solo vicino a loro); l'Eagle li ignora.
- Spec, piano e implementazione nella stessa sessione.

## Vincoli

- Profondità a 24 bit (`gl_compatibility`): tracce e orme piatte sfarfallerebbero; si sollevano dal suolo di
  max(0,02 m, 0,0004 × distanza dalla camera), sono trasparenti, non scrivono la profondità, e si disegnano solo
  vicino.
- La luna si muove: tracce, orme e sassi sono figli del nodo della luna, in coordinate della luna, con un'origine
  locale vicina (le posizioni a 250 km dal centro perderebbero precisione nei float a 32 bit della GPU).
- Un corpo statico figlio della luna si sposta un tick in ritardo: il corpo dei massi va aggiornato a ogni tick
  come quello della base (`moon.gd _place`).

## Sassi e massi (`scripts/moon_rocks.gd`, nodo `Rocks` della luna)

- **Tre taglie**, ognuna su una griglia del piano della faccia del cubo (come i crateri piccoli), una pietra al
  più per cella, scelta da un hash della cella (stessi sassi tornando nello stesso posto):

  | taglia | cella | probabilità base | misura | disegnati entro | ricostruiti ogni |
  |---|---|---|---|---|---|
  | sassolini | 2 m | 0,6 | 0,1–0,3 m | 60 m | 20 m |
  | sassi | 8 m | 0,35 | 0,3–0,8 m | 200 m | 50 m |
  | massi | 40 m | 0,6 | 0,8–4 m | 600 m | 150 m |

- **Densità:** la probabilità si moltiplica per 1 + min(3, bordo) dove bordo è l'altezza dei crateri piccoli in
  quel punto (`MoonTerrain.crater_height`, positiva sui bordi rialzati e sull'ejecta), al più 1. Entro 700 m dal
  centro di Selene (base e pad) nessuna pietra; fino a 1.200 m (piazzale piatto) il 5%; fino a 2.500 m sale a
  pieno.
- **Aspetto:** tre forme low poly irregolari, grigio regolite, girate e scalate a caso (più larghe che alte),
  affondate nel suolo per un quarto della loro altezza, con l'alto del suolo. MultiMesh per taglia; la faccia del
  cubo è quella sotto il giocatore (cambiando faccia le pietre vicino allo spigolo cambiano).
- **Ricostruzione:** su un thread separato, ogni taglia quando la sua finestra (arrotondata al passo della tabella)
  cambia.
- **Chi le porta:** `moon.follow_rocks(point, collide)` ogni tick dal rover e dal pedone (`collide` sì) e
  dall'Eagle nel riferimento lunare (solo disegno).
- **Collisioni:** un `StaticBody3D` `RockBody` figlio della luna, con una sfera per ogni masso entro 60 m dal
  rover o dal pedone (raggio 0,45 × misura, centro 0,2 × misura sopra il suolo), rifatte quando chi le porta si
  sposta di 10 m; aggiornato a ogni tick insieme alla base. Il rover li urta (i sassi sotto 0,4 m gli passano
  sotto, come oggi), il pedone pure.

## Tracce del rover (`scripts/moon_tracks.gd`, nodo `Tracks` della luna)

- Due solchi larghi 0,3 m, sotto le ruote dei due lati (±0,9 m dal centro). Un campione ogni 0,5 m di strada,
  solo a terra e oltre 0,3 m/s; in aria la traccia si interrompe e riparte all'atterraggio (anche dopo uno stacco
  oltre 2 m).
- Strisce in blocchi di 200 campioni (100 m), ognuno con la sua origine; disegno del battistrada a chevron nello
  shader, regolite più scura (alfa ~0,5), più marcata al centro; visibili entro 600 m.
- Restano per tutta la sessione (anche entrando e uscendo dalla stazione); oltre 2.000 blocchi (200 km) i più
  vecchi si tolgono.

## Orme (`scripts/moon_footprints.gd`, nodo `Footprints` della luna)

- **Camminata:** un'orma ogni 0,7 m, alternate sinistra/destra a ±0,15 m dalla linea di marcia.
- **Corsa:** ogni 1,4 m, più lunghe (×1,3) e più marcate.
- **Salto:** allo stacco due orme affiancate; all'atterraggio due impronte larghe (×1,4) con un alone "schizzato".
- Ogni orma è un quadrato 0,13 × 0,32 m orientato come la marcia; lo shader disegna la suola (contorno
  arrotondato, righe trasversali, tacco). MultiMesh a blocchi di 512, visibili entro 150 m, per tutta la sessione
  (oltre 200 blocchi i più vecchi si tolgono).

## Test

TDD; solo i test nuovi o toccati.

- `tests/test_moon_rocks.gd`: stessa cella stesse pietre; densità sui bordi dei crateri più che doppia rispetto al
  piano; nessuna pietra entro 700 m da Selene; (scena piccola) le sfere dei massi solo entro 60 m dal giocatore e
  ferme rispetto alla luna mentre si muove; il rover si ferma contro un masso; il pedone pure.
- `tests/test_moon_tracks.gd`: un campione ogni 0,5 m; nessuno in aria o da fermo; la traccia si spezza dopo un
  salto; (scena piccola) 5 s di guida lasciano ~75 campioni per lato.
- `tests/test_moon_footprints.gd`: passo di camminata e corsa, alternanza dei lati, due orme allo stacco e due
  all'atterraggio; (scena piccola) 5 s di camminata lasciano ~11 orme.
- Prova GPU: tracce dietro il rover, orme di camminata, corsa e salto, un campo di massi vicino a un cratere.

## Fuori da questo lavoro

- Polvere sollevata, tracce dell'Eagle all'atterraggio, salvataggio delle tracce fra una sessione e l'altra.
- Collisioni dei sassi con l'Eagle.

## Cambiato durante l'esecuzione

- **Una forma per taglia:** una sola mesh di pietra per taglia (sfera grossolana deformata), varietà da rotazione,
  schiacciamento e scala, invece di tre forme.
- **Campioni delle tracce esattamente ogni 0,5 m:** a 20 m/s un tick copre 0,33 m; i campioni si mettono lungo il
  tratto percorso, non solo dove capita il tick (prima cadevano ogni 0,5–0,83 m).
- **Orme:** il passo sa da solo di essere in volo fra stacco e atterraggio.
- **Test delle pietre sulla scena** in un file a parte (`test_moon_rocks_scene.gd`). Il corpo dei massi si
  aggiorna a ogni tick come la base, anche se il test passa pure senza (qui arriva comunque in tempo).
- **Prova GPU:** tracce a chevron dietro il rover, orme di camminata, corsa e salto, massi e sassi a 3 km dalla
  base; 54–57 FPS guidando lontano dalla base.
- **Dopo la revisione finale:**
  - **Sul suolo disegnato:** pietre, tracce e orme stanno sul suolo come lo disegna la toppa (il reticolo di 8 m,
    `MoonPatch.drawn_radius`), non su quello vero: fra i crateri i due differiscono di decine di centimetri, e tracce
    e orme finivano sotto il suolo in un terzo dei punti.
  - **Blocchi di orme vicini:** un'orma oltre 40 m dalla prima del suo blocco ne apre uno nuovo (un blocco si
    disegna in base alla distanza dal suo centro: prima le orme sotto i piedi sparivano dopo 150 m di cammino).
  - **Orme illuminate dall'alto:** la loro base era specchiata, e il piano risultava rivolto in giù.
  - **Tracce a blocchi di 25 m:** ogni campione ricostruisce il suo blocco; prima (100 m) costava 2–4 ms per tick.
  - **Pietre solo se visibili:** volando con l'Eagle più in alto di quanto una taglia si vede, quella taglia non si
    ricostruisce (prima due core lavoravano senza sosta per pietre invisibili).
