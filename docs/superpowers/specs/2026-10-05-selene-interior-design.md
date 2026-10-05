# Interni della base Selene — progetto

Una scena interna della base Selene, camminabile in prima persona, in omaggio a Base Alpha di *Spazio 1999*
(prima stagione): sala di sbarco sotto il pad, Travel Tube, corridoio principale, Main Mission, infermeria,
alloggi, sala comune. L'equipaggio cammina nei corridoi, lavora alle console e in infermeria.

## Scelte dell'utente

- Si entra **dall'Eagle posata su un pad di Selene**, con il nuovo tasto **B** (HUD `B BASE`). K resta "a
  piedi in superficie" come oggi.
- **Nucleo iconico:** una decina di ambienti fatti a mano.
- **Equipaggio con vita di routine:** chi cammina, chi è seduto alle console, chi lavora in piedi.
- **Approccio A:** scena separata, come gli interni delle sezioni (il mondo esterno si stacca).
- Spec, piano e implementazione nella stessa sessione.

## Riferimenti di Base Alpha

- Pareti a pannelli modulari 1,2 × 2,4 m, **beige** chiaro; corridoi larghi 2,4 m con **pannelli curvi
  luminosi** bianchi sulle pareti; corridoi laterali stretti (1,8 m).
- **Colonna di comunicazione** cilindrica all'incrocio, con i cartelli di direzione.
- Porte scorrevoli; la porta della **Travel Tube** con la sua insegna.
- **Main Mission:** sala lunga con la grande vetrata sulla superficie lunare, il **Big Screen**, scrivanie bianche
  curve con pannelli del computer grigio scuro a luci lampeggianti, lampade a globo; l'**ufficio del
  Comandante** rialzato, dietro una parete scorrevole.
- Arredi di design italiano anni '70 (bianco, arancio).
- Equipaggio in tuta color avena, **manica sinistra colorata** per reparto.

## Struttura

- `scripts/selene_interior.gd` — la scena (`Node3D`), costruita a codice: stanze, porte, arredi, luci,
  collisioni, Travel Tube, equipaggio.
- `scripts/selene_layout.gd` — funzioni pure: stanze, porte, percorsi dell'equipaggio, posti alle console.
- `scripts/selene_crew.gd` — l'equipaggio: modello Quaternius con scheletro e animazioni vere (pochi, da vicino),
  colori per reparto, camminata sui percorsi, seduti, al lavoro.
- `scripts/game_mode.gd` — nuovo modo `IN_BASE`, tasto B, uscita con K.
- `project.godot` — azione `base` sul tasto B (66).

## Entrata e uscita

- **Entrata:** a bordo dell'Eagle posata su un pad di Selene (`_ship_pad()` non vuoto), l'HUD della nave mostra
  `B BASE`; B: dissolvenza (2 s, "il pad scende nell'hangar"), il mondo esterno si stacca (come
  `enter_interior`), si è a piedi nella **sala di sbarco**, accanto alla piattaforma dell'ascensore.
- **Uscita:** a piedi entro 3 m dalla piattaforma dell'ascensore l'HUD mostra `K EAGLE`; K: dissolvenza, il mondo
  esterno torna, si è a bordo dell'Eagle sullo stesso pad, ferma.
- Mentre si è dentro la luna e il resto non girano (staccati, come dentro le sezioni).

## Ambienti (pavimento a y = 0, griglia di 1,2 m)

| ambiente | misura (m) | altezza | note |
|---|---|---|---|
| Sala di sbarco | 12 × 9,6 | 4,8 | piattaforma dell'ascensore 6 × 6 al centro, luci gialle di avviso; porta della Travel Tube |
| Travel Tube | cabina 2,4 × 3,6 | 2,4 | due fermate: **Sbarco** e **Centro** |
| Ricevimento Travel Tube | 4,8 × 4,8 | 2,4 | in capo al corridoio, scrivania e lampada |
| Corridoio principale | 18 × 2,4 | 2,4 | pannelli curvi luminosi, colonna di comunicazione all'incrocio a metà |
| Corridoio laterale | 2 × 9,6 × 1,8 | 2,4 | incrocia il principale alla colonna |
| Main Mission | 20 × 12 | 4,8 | in fondo al corridoio, porta doppia |
| Ufficio del Comandante | 7,2 × 6 | 4,2 | rialzato 0,6 m (3 gradini) in un capo della Main Mission, parete scorrevole |
| Infermeria | 9,6 × 7,2 | 2,4 | lettini, armadi, pannelli |
| Alloggi | 2 × 4,8 × 4,8 | 2,4 | letto, scrivania, poltroncina |
| Sala comune | 9,6 × 9,6 | 2,4 | tavoli bianchi, poltroncine arancio, distributore |

- La sala di sbarco e il "centro" (ricevimento, corridoi, stanze) sono due zone della stessa scena, lontane 200 m
  e senza collegamento a piedi: le unisce la Travel Tube.
- **Main Mission:** vetrata lunga sulla parete lunga (sfondo dipinto: superficie lunare grigia, cielo nero
  stellato, il pianeta); Big Screen sulla parete corta opposta all'ufficio; 8 scrivanie bianche curve in due file
  con pannelli del computer (grigio scuro, luci lampeggianti) e lampade a globo; ufficio del Comandante con
  scrivania e parete scorrevole che si apre quando ci si avvicina.

## Aspetto

- Pannelli beige (giunti scuri ogni 1,2 m), luci bianche nei pannelli curvi, soffitto chiaro, pavimento grigio
  scuro; colonna di comunicazione bianca con cartelli (testo: MAIN MISSION, MEDICAL CENTRE, CREW QUARTERS,
  RECREATION, TRAVEL TUBE).
- **Porte scorrevoli** (1,2 m, doppie 2,4 m): si aprono di lato in 0,5 s quando il giocatore o un membro
  dell'equipaggio è entro 2 m, si chiudono dopo; collisione solo da chiuse.
- Luci: poche `OmniLight3D` (al più 8 per oggetto, come altrove) più la luce propria dei pannelli; ambiente
  caldo.
- Arredi low poly a codice: poltroncine, tavoli, scrivanie curve, lettini, lampade.

## Travel Tube

- Cabina con porta; dentro l'HUD mostra la destinazione (`K CENTRO` o `K SBARCO`). K: la porta si chiude,
  dissolvenza di 1,5 s, si è nella cabina dell'altra fermata, la porta si apre.

## Equipaggio (`selene_crew.gd`)

- Circa **20 persone**, modello Quaternius con **scheletro e `AnimationPlayer`** (Walk, Idle, Working), non la
  texture dei pedoni: sono poche e servono più pose.
- **Colori** dalle ossa (come `PeopleModel`): tuta avena, stivali scuri (piedi), pelle (testa e mani), **manica
  sinistra** del reparto — Main Mission arancio, Medicina bianco, Sicurezza viola, Tecnici giallo, Comando nero.
- **Camminatori (10):** giri fissi fra corridoio e stanze attraverso le porte, a 1,2 m/s; si fermano (Idle) 3–8 s
  alle mete; se il giocatore è davanti entro 1,2 m si fermano finché non si sposta.
- **Seduti (8):** alle scrivanie della Main Mission, posa seduta costruita piegando anche e ginocchia sulla posa
  Idle, il busto che si muove appena.
- **Al lavoro in piedi (2–3):** Working in infermeria e a un pannello del corridoio; il Comandante in piedi nel
  suo ufficio (Idle).

## Giocatore

- A piedi come dentro le sezioni (W/S, A/D, mouse, J, Spazio), gravità 9,81 verso −Y, urta pareti, arredi,
  porte chiuse e persone.
- HUD a piedi: `IN BASE`, la velocità, il nome dell'ambiente in cui si è; `K EAGLE` vicino all'ascensore,
  `K CENTRO`/`K SBARCO` nella Travel Tube.

## Test

TDD; solo i test nuovi o toccati.

- `tests/test_selene_layout.gd`: ogni ambiente del centro è raggiungibile dal ricevimento passando per le porte;
  le stanze non si sovrappongono; i percorsi dell'equipaggio stanno sul pavimento e attraversano le pareti solo
  dalle porte; un posto a sedere per scrivania.
- `tests/test_selene_interior.gd`: il pedone non attraversa una parete; una porta si apre con il pedone a 2 m e si
  chiude quando si allontana; la Travel Tube porta all'altra fermata; la parete dell'ufficio si apre.
- `tests/test_selene_crew.gd`: i colori per reparto (manica sinistra); un camminatore avanza sul suo percorso e si
  ferma con il giocatore davanti; la posa seduta ha le ginocchia piegate (anche più basse in piedi).
- `tests/test_game_mode.gd` (toccato): `B BASE` solo con l'Eagle posata su un pad di Selene; B → `IN_BASE`, mondo
  esterno staccato; K vicino all'ascensore → di nuovo sull'Eagle sullo stesso pad.
- **Prova GPU:** sala di sbarco, corridoio con la colonna, Main Mission con le persone sedute, infermeria; FPS.

## Fuori da questo lavoro

- Parlare con l'equipaggio; vista vera della luna dalla vetrata; altri settori della base; entrare dalla
  superficie a piedi; suoni.
