# Assistenza al volo e all'attracco

## Contesto

Il void-cruiser vola per inerzia pura: non c'è attrito, e per fermarsi bisogna
spingere al contrario. La spinta base è già forte (150 m/s², 1×) e con la rampa
arriva a 10× e 100×. Per attraccare serve stare entro 150 m dal pad e sotto
20 m/s rispetto al pad, poi premere F.

La guida di attracco (quadrati e mirino, `2026-09-27-curved-docking-guide-design.md`)
dice dove andare, ma:
- non dice a che velocità andare;
- non aiuta a frenare;
- scorre di lato: il pad fa un giro attorno al bridge ogni 107 s circa
  (3,4°/s), e il percorso lo insegue.

## Decisioni prese con l'utente

L'utente ha scelto cinque interventi fra quelli proposti:
1. **Frenata:** B una volta. La navetta annulla da sola la velocità relativa al
   dock e poi la tiene.
2. **Spinta di precisione:** vicino al dock scala con la distanza.
3. **Velocità consigliata:** frenata costante, dopo la verifica sotto. Colori:
   verde, giallo, rosso.
4. **Pannello di avvicinamento.**
5. **Percorso fermo nello spazio:** mira a dove sarà il pad all'arrivo.

## Cosa ha cambiato il prototipo

Prima di scrivere questa spec ho simulato una navetta che segue il percorso con
il bridge che ruota. Sono emersi due punti:

- **"Arrivo in circa 30 s" non va bene.** Seguendo quella velocità mancano
  sempre 30 s all'arrivo. Il punto di mira resta sempre 100° avanti al pad e
  gira con lui. Si usa invece la **frenata costante a 1 m/s²**. È una delle due
  opzioni proposte all'utente, e la conferma è arrivata con `/goal spec + piano`.
- **Il punto d'incontro va scelto, non inseguito.**
  - Mirare a "dove sarà il pad fra il tempo di frenata" mandava spesso il
    percorso dall'altra parte del bridge. Per esempio, a 1,5 km davanti al pad
    il percorso girava per 4,8 km, con 178 m/s consigliati.
  - Ora l'orario d'arrivo è il **primo passaggio del pad sotto la navetta**,
    dopo il tempo minimo di frenata. Il pad arriva al massimo dopo un giro, cioè
    107 s.
  - Il percorso scende quasi dritto. Se sei in anticipo, la velocità consigliata
    è bassa: si aspetta il pad.
- **L'orario si fissa una volta e si tiene.** Si rifà solo se il tempo rimasto
  scende sotto il 30% del tempo di frenata costante, o supera 3 volte quel tempo
  più un giro del bridge.
- **Risultato della simulazione:**
  - il percorso si sposta nello spazio in media di 1,3 m/s, contro 92 m/s
    mirando al pad di adesso;
  - volando al 70% o al 140% della velocità consigliata, il percorso resta quasi
    fermo.

## Funzioni pure (`scripts/docking_assist.gd`)

- **`precision_factor(distance)`:**
  - 1 da 2 km in su;
  - 0,1 da 200 m in giù;
  - lineare fra i due.
- **`scaled_thrust(input, ramp, precision)`:**
  - con fattore 1, solo la spinta avanti riceve la rampa;
  - sotto 1, tutti gli assi sono moltiplicati per il fattore, senza rampa.
- **`brake_velocity(velocity, target, max_acceleration, delta)`:** in un tick
  porta la velocità verso quella voluta, cambiandola al massimo di
  `max_acceleration · delta`.
- **Pianificazione:**
  - `arrival_time(length)`: √(2 · length / 1 m/s²), il tempo della frenata
    costante;
  - `plan_arrival(ship, pad, spin, length)`: il tempo di frenata, più l'attesa
    finché il pad (angolo + spin · t) arriva all'angolo della navetta. Tutto nel
    sistema del bridge;
  - `keeps_plan(time_left, length, spin)`: vero fra 0,3 × il tempo di frenata e
    3 × il tempo di frenata + 2π/spin;
  - `advised_speed(length, time_left)`: 2 · length / time_left, cioè arrivare in
    orario frenando in modo costante; 0 se il tempo è finito;
  - `future_pad(pad, spin, time)`: il pad ruotato attorno all'asse Y del bridge
    di spin · time.
- **Pannello:**
  - `speed_rating(speed, advised)`: OK fino alla velocità consigliata, CAUTION
    fino a 1,25 volte, OVER oltre;
  - `format_time(s)`: "42 s", "3:05", "—" per nessuna lettura;
  - `readout(length, time_left, speed, closing, distance)`: le righe `DIST`,
    `REL SPEED`, `ADVISED`, `ETA`, lo stato, il rating e "pronto".
    - L'ETA è lunghezza / velocità di avvicinamento, "—" sotto 0,5 m/s.
    - Lo stato è "DOCK READY" se la regola di attracco è soddisfatta,
      "TOO FAST" se sei entro 150 m ma troppo veloce, vuoto altrimenti.

## Navetta (`scripts/void_cruiser.gd`)

**Dock più vicino.** `_nearest_dock()` restituisce stazione, indice, port,
distanza e velocità del pad, oppure vuoto oltre 20 km, fuori dall'albero o senza
stazione.

**Frenata (B, azione `brake`):**
- **Tasti:**
  - B accende o spegne la frenata;
  - C e B si escludono a vicenda;
  - W/A/S/D/Z/X la spengono, il rollio no.
- **A ogni tick:** la velocità va verso quella del pad (verso zero oltre
  20 km), a 10 × spinta base × fattore di precisione. Durante la frenata le
  forze orbitali sono compensate, come con C.
- **HUD:** mostra la riga "BRAKE".

**Precisione:**
- **A ogni tick:** `thrust_scale` = fattore di precisione. La spinta dei tasti
  passa da `scaled_thrust`.
- **HUD:** mostra "THRUST 0.4x" quando il fattore è sotto 1.

**Piano e pannello:**
- `_guide_clock` avanza di `delta` a ogni frame.
- **L'orario d'arrivo (`_arrival_at`) si pianifica di nuovo:**
  - quando manca;
  - quando cambia il bridge;
  - quando `keeps_plan` fallisce. Per la lunghezza si usa quella del percorso
    del frame prima (la distanza in linea retta se manca).
- **Il pannello** usa:
  - la lunghezza del percorso (la distanza in linea retta sotto 100 m);
  - la velocità relativa al pad;
  - l'avvicinamento verso il primo quadrato (verso il pad se non ci sono
    quadrati);
  - la distanza in linea retta.

**Percorso.** Mira a `future_pad(pad, spin, time_left)`.

## HUD (`scripts/cockpit.gd`)

- **Pannello di sinistra:** righe nuove "BRAKE" (arancio) e "THRUST 0.4x", sotto
  CRUISE.
- **"ApproachPanel" in alto a destra**, largo 300 px, che cresce verso sinistra:
  - righe `DistLabel`, `RelSpeedLabel`, `AdvisedLabel`, `EtaLabel`,
    `StatusLabel`;
  - la velocità relativa è colorata secondo il rating;
  - lo stato è verde se pronto, rosso se no, e nascosto se vuoto;
  - con una lettura vuota tutto il pannello è nascosto.

## Stazione

`get_spin_rate()` rende pubblica la velocità di rotazione di sezioni e bridge.

## Fuori scope

- Pilota automatico.
- Freccia verso il dock fuori schermo.
- Stessa velocità di riferimento per SPEED e per la croce delle velocità.

## Testing

- **Funzioni pure:** fattore, spinta, frenata limitata per tick, tempo di
  arrivo, piano che tiene fra i due limiti, attesa del pad (il pad è sotto la
  navetta all'arrivo), velocità consigliata, pad futuro, rating, formato del
  tempo, righe e stato del pannello.
- **Simulazione pura:** con il punto d'incontro il percorso si sposta al massimo
  di 15 m/s, e almeno 5 volte meno che senza.
- **Senza scena (off-tree):**
  - B accende la frenata e spegne C, e viceversa;
  - W/A/S/D/Z/X spengono la frenata, il rollio no;
  - lontano da tutto, la frenata ferma la navetta a 10 × spinta.
- **HUD:** righe BRAKE e THRUST, ordine delle righe, posizione del pannello e
  sue righe, testi e colori.
- **Scena vera:**
  - B porta la navetta alla velocità del pad in meno di 0,5 s;
  - a 1,1 km la spinta è 0,55× senza rampa e la riga THRUST si vede; a 5 km no;
  - il pannello si vede a 5 km e sparisce a 25 km;
  - a 120 m: "DOCK READY" da fermi, "TOO FAST" a 25 m/s;
  - con la navetta a un quarto di giro dal pad, l'ultimo quadrato è sul punto
    d'incontro sotto la navetta, non sul pad di adesso;
  - il test sull'isteresi della guida gira con il bridge fermo.
- **Tasti:** "brake" è sul tasto B.
- **Render (xvfb):** a 1,5 km, pannello, THRUST e percorso che scende sotto la
  navetta.

## Revisione dopo la review finale (2026-09-27)

Tre correzioni, la prima decisa con l'utente:
- **La frenata B è mista.**
  - **Entro 2 km dal dock** la navetta gira insieme al bridge: la velocità
    voluta è quella del bridge nel punto dove si trova la navetta. Resta ferma
    sopra lo stesso punto del bridge. A 120 m dal pad si muove di circa 7 m/s
    rispetto al pad, sotto il limite di attracco.
  - **Oltre 2 km** si ferma nello spazio e aspetta che il pad arrivi al punto
    d'incontro.
  - **Perché:** copiare la velocità del pad portava la navetta contro lo scafo
    in circa 30 s, perché il pad gira attorno al bridge e la navetta va dritta.
  - **All'uscita dall'interno** B e C sono spenti.
- **Il piano si rifà anche quando il percorso cresce** oltre 1,5 volte la
  lunghezza per cui era stato fatto. Senza questa regola, girando attorno al
  bridge il percorso arrivava a 3,8 km mentre il pad passava sotto la navetta.
- **Entro 150 m** la velocità consigliata non supera 20 m/s. Sopra quel limite
  la velocità relativa è rossa, coerente con "TOO FAST".
