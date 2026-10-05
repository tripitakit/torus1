# Interni di Selene v2 — progetto

Seconda versione degli interni della base Selene, dopo la prova dell'utente: meno persone, ambienti più larghi e
alti, pareti chiuse negli angoli, colonna di comunicazione completa, viaggio vero in Travel Tube, pose sedute
corrette (o in piedi), molti più dettagli in stile *Spazio 1999*.

Base: `docs/superpowers/specs/2026-10-05-selene-interior-design.md` (tutto quello che qui non cambia resta).

## Richieste dell'utente

- Troppe persone; corridoi troppo stretti; soffitti troppo bassi.
- Pareti che non si chiudono negli angoli (si vede attraverso).
- Colonna di comunicazione scarna: manca lo schermo, manca la console di pulsanti, mancano le frecce di direzione.
- Animazione della Travel Tube: **viaggio vero dentro la cabina** (scelta dell'utente).
- Pose sedute sbagliate (appena piegati): correggerle, o lasciarli in piedi se troppo complicato.
- Molto più sci-fi e dettagliata, in linea con *Spazio 1999*.

## Pianta v2 (griglia 1,2 m, pavimento a y = 0)

| ambiente | x | z | altezza |
|---|---|---|---|
| Sala di sbarco (hangar) | 194 … 206 | −6 … 6 | 8,0 |
| Nicchia Travel Tube sbarco | 197,6 … 202,4 | 6 … 9,6 | 3,0 |
| Tunnel | 2,4 … 197,6 | 6 … 9,6 | 3,6 (zona "tube", non a piedi) |
| Nicchia Travel Tube centro | −2,4 … 2,4 | 6 … 9,6 | 3,0 |
| Ricevimento | −3,6 … 3,6 | 0 … 6 | 3,6 |
| Corridoio principale (largo 4,8) | −2,4 … 2,4 | −21,6 … 0 | 3,6 |
| Corridoi laterali (larghi 3,0) | ±2,4 … ±12 | −10,5 … −7,5 | 3,6 |
| Main Mission | −12 … 12 | −36 … −21,6 | 6,0 |
| Ufficio del Comandante (pavimento 0,6) | 12 … 18 | −32,4 … −25,2 | 5,4 |
| Infermeria | −21,6 … −12 | −12,6 … −5,4 | 3,6 |
| Alloggi A / B | −9,6 … −4,8 | −15,3 … −10,5 / −7,5 … −2,7 | 3,6 |
| Sala comune | 12 … 21,6 | −13,8 … −4,2 | 3,6 |

Porte: ricevimento–corridoio aperta 4,8; corridoio–Main Mission doppia 3,6; corridoio–laterali aperte 3,0;
infermeria 1,8; alloggi 1,2; sala comune doppia 2,4; ufficio parete scorrevole 4,8 (vetrata); Travel Tube 1,8
(ricevimento–nicchia, sbarco–nicchia); nicchie–tunnel aperture "tunnel" (non contano a piedi).

## Pareti chiuse

Pareti uniche e piene (spessore 0,2): i lati di tutte le stanze sulla stessa linea si uniscono, si tolgono i vani
delle porte, ogni pezzo si allunga di mezzo spessore agli estremi che non sono un vano; altezza = la più alta
delle stanze che tocca. Test: attorno a ogni angolo di stanza (quadrato di 0,2 m) non c'è un punto scoperto.

## Persone: 12

4 operatori seduti alle scrivanie della Main Mission (8 scrivanie), il Comandante in piedi nell'ufficio, un
medico in piedi in infermeria, 6 che camminano (un percorso per reparto più uno in Main Mission).
**Seduti:** la posa si applica quando la persona è già nella scena, con il motore delle animazioni spento (prima
la posa si perdeva entrando nella scena). Se alla prova GPU non è credibile: in piedi.

## Colonna di comunicazione

Colonna bianca (ingombro 1 × 1 m) all'incrocio, con su due facce: schermo video incorniciato (immagine animata
in stile videotelefono), sotto una console inclinata di pulsanti luminosi; sulle quattro facce i cartelli con le
**frecce di direzione** verso MAIN MISSION, MEDICAL CENTRE, CREW QUARTERS, RECREATION, TRAVEL TUBE (frecce
calcolate dalla pianta: la direzione da prendere da quella faccia).

## Travel Tube

- Una **cabina** (4,4 × 3,2 m, alta 2,8) con porta scorrevole sul lato lungo, finestrini sugli altri lati, due
  panche, un pannello di comando con le spie e la mappa del percorso con un punto che avanza; corpo cinematico,
  con collisioni.
- Un **tunnel** di ~195 m fra le nicchie: sezione rettangolare 4 × 3,6 m, anelli luminosi ogni 6 m, rotaia.
- **Viaggio:** in cabina, ferma a una fermata, K: la porta si chiude, la cabina accelera (2 s), corre, frena
  (2 s), si ferma all'altra fermata (~10 s in tutto), la porta si apre. Chi è dentro viaggia con lei (si può
  camminare e guardarsi attorno).
- **Chiamata:** davanti alla porta della Travel Tube con la cabina all'altra fermata, K la chiama (arriva vuota).
- HUD: `K CENTRO`/`K SBARCO` in cabina ferma, `K CHIAMA` davanti alla porta con la cabina lontana.

## Dettagli in stile Spazio 1999

- **Corridoi:** pannelli luminosi curvi (mezzi cilindri con cornice) lungo le pareti; zoccolo scuro e strisce
  luminose a filo pavimento; soffitto a cassettoni con luci incassate; griglie di aerazione; banchi di computer a
  muro (grigio scuro, luci lampeggianti, bobine di nastro); piante in vaso.
- **Porte:** cornice scura con angoli superiori smussati, spia di stato, targa col numero, banda colorata.
- **Main Mission:** soffitto a griglia di luci; parete del Big Screen con banchi di computer ai lati; fila di
  console con monitor alla vetrata; scrivanie bianche curve con monitor e lampada a globo; piante; ufficio con
  parete vetrata scorrevole.
- **Hangar:** colonne, travi, tubazioni, strisce di pericolo, cabina di controllo vetrata, luci rotanti
  dell'ascensore.
- **Infermeria, alloggi, sala comune:** monitor, armadietti, apparecchiature, poltroncine, bancone.

## Test

TDD; solo i test nuovi o toccati.

- `test_selene_layout.gd`: tabella v2; nessuna sovrapposizione; raggiungibilità (il tunnel non conta a piedi);
  **angoli chiusi**; percorsi solo per le porte e lontani da pareti (0,3) e arredi (0,5); 8 posti; pezzi ≤ 12 m;
  frecce della colonna verso le mete.
- `test_selene_interior.gd`: muro, porte, ufficio, salita all'ufficio con le posizioni v2; **viaggio**: la
  cabina parte, arriva all'altra fermata con il pedone dentro; **chiamata**.
- `test_selene_crew.gd`: 12 persone, 4 sedute; **seduti dopo l'ingresso nella scena** con le ginocchia piegate.
- `test_game_mode.gd`: viaggio in Travel Tube da GameMode (K in cabina) e ritorno; uscita all'ascensore.
- Prova GPU: hangar, corridoio con la colonna, Main Mission, cabina in viaggio nel tunnel, infermeria.
