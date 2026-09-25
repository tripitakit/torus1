# Volo orbitale e assistenza di volo del void-cruiser

## Contesto

Il void-cruiser vola in modo arcade: un attrito (`linear_damping` 0,5 e
`angular_damping` 0,5) dimezza velocità e rotazione ogni secondo, e nessuna
forza esterna agisce sulla navetta. L'anello (raggio 6949,6 km attorno a un
pianeta grande come la Luna) è fermo nella scena.

Questo lavoro rende il volo più realistico:
- un'assistenza di volo che si può spegnere (inerzia pura);
- la gravità del pianeta, con l'anello che orbita a circa 840 m/s;
- un HUD dell'orbita e la linea dell'orbita prevista nello spazio.

## Decisioni prese con l'utente

- **Orbita dell'anello:** approccio A, sistema che ruota con l'anello. Nella
  scena l'anello resta fermo; la navetta riceve gravità, forza centrifuga e
  Coriolis. È fisicamente identico a un anello che orbita, visto da chi sta
  sull'anello.
- **Forze orbitali:** agiscono sempre, con l'assistenza accesa o spenta.
- **Assistenza accesa:** come oggi. Attrito su moto e rotazione, rampa fino a
  100x, blocco C che spinge a v-max.
- **Assistenza spenta:** nessun attrito né sul moto né sulla rotazione;
  nessuna rampa (spinta fissa 1x, 150 m/s²); nessun limite di velocità.
- **Blocco C con l'assistenza spenta:** tiene la velocità che la navetta ha
  quando lo premi (i propulsori compensano gravità, centrifuga e Coriolis).
- **Tasto:** Tab accende e spegne l'assistenza. Si parte con l'assistenza
  accesa.
- **HUD:** righe `ASSIST`, `ALTITUDE`, `PERIAPSIS`, `APOAPSIS` e gli avvisi
  `IMPACT` ed `ESCAPE`, più la linea 3D dell'orbita.

## Numeri

- GM del pianeta: 4,9048·10¹² m³/s² (la Luna).
- Raggio dell'orbita dell'anello: 1 737 400 + 5 212 200 = 6 949 600 m.
- Velocità angolare dell'anello: ω = √(GM / R³) ≈ 1,2088·10⁻⁴ rad/s.
- Velocità dell'anello: ω · R ≈ 840,1 m/s; un giro in circa 14,4 ore.
- Gravità all'altezza dell'anello: circa 0,1 m/s².
- Velocità di fuga all'altezza dell'anello: circa 1,19 km/s.

Vicino all'anello gravità e centrifuga si annullano: a 10 km dall'anello
resta circa 0,0004 m/s². Le forze si sentono scendendo verso il pianeta
(0,9 m/s² a 1000 km dalla superficie) e con Coriolis ad alta velocità
(2ωv, circa 0,24 m/s² a 1 km/s).

## Architettura

### `scripts/orbital_frame.gd` (nuovo, funzioni pure)

- `MOON_GM`.
- `orbit_angular_velocity(gm, orbit_radius)`: ω di un'orbita circolare.
- `frame_acceleration(offset, velocity, gm, omega)`: accelerazione nel
  sistema che ruota. `offset` è la posizione rispetto al centro del pianeta,
  `velocity` la velocità rispetto all'anello, `omega` il vettore di rotazione
  (asse × ω). Somma di:
  - gravità `-GM · offset / |offset|³`;
  - centrifuga `-ω × (ω × offset)`;
  - Coriolis `-2 ω × velocity`.
- `inertial_velocity(offset, velocity, omega)`: velocità vera rispetto alle
  stelle, `velocity + ω × offset`.
- `orbit_of(offset, inertial, gm)`: orbita di Keplero. Restituisce periasse e
  apoasse come distanze dal centro (apoasse infinito se l'orbita è aperta),
  più vettore di eccentricità, semilato retto e normale del piano, che
  servono al disegno.
- `orbit_points(orbit, count, max_radius)`: punti dell'orbita attorno al
  centro, per anomalia vera. Un'orbita chiusa fa il giro completo; un'orbita
  aperta si ferma dove il raggio raggiunge `max_radius`.

### Modello di volo condiviso (`flying_craft.gd`)

Tre punti di aggancio, che l'internal-cruiser lascia com'erano:
- `_linear_damping_now()` e `_angular_damping_now()`: l'attrito da usare in
  questo passo (di base, quello impostato);
- `_external_acceleration()`: accelerazione esterna (di base zero), aggiunta
  alla velocità a ogni passo.

### Void-cruiser (`void_cruiser.gd`)

- `flight_assist` (vero all'avvio). Tab (azione `flight_assist`) lo inverte
  e spegne il blocco C.
- Assistenza spenta: attrito zero su moto e rotazione, moltiplicatore della
  spinta sempre 1.
- Blocco C:
  - assistenza accesa: come oggi, spinta in avanti forzata e rampa;
  - assistenza spenta: nessuna spinta forzata; l'accelerazione esterna vale
    zero, quindi la velocità resta quella che era. Z/X la cambiano e il
    blocco tiene quella nuova. W/A/S/D e C spengono il blocco come oggi.
- Il pianeta: `planet_path` (di base `../PlanetSystem/Planet`). A ogni passo
  di fisica e a ogni frame la navetta legge dal nodo il centro, l'asse
  (asse Y del nodo, che è l'asse dell'anello) e il raggio del pianeta.
  Senza nodo pianeta (per esempio nei test fuori scena) non ci sono forze e
  l'HUD dell'orbita mostra `—`.
- `ring_radius` (6 949 600) e `planet_gm` sono impostazioni esportate; un
  test verifica che il raggio coincida con quello della stazione nella
  scena.
- L'origine mobile sposta il pianeta: rileggere il centro a ogni frame
  basta, niente altro cambia.

### HUD (`cockpit.gd`)

Nuove righe sotto `CRUISE`, in quest'ordine: `ASSIST`, `ALTITUDE`,
`PERIAPSIS`, `APOAPSIS`, `IMPACT`, `ESCAPE`.
- `ASSIST  ON` nel colore dell'HUD, `ASSIST  OFF` in giallo.
- Quote in chilometri interi sopra la superficie (per esempio
  `ALTITUDE  5222 km`). Un periasse sotto la superficie è negativo.
- `IMPACT` (rosso) compare quando il periasse è sotto la superficie.
- `ESCAPE` (rosso) compare quando l'orbita è aperta; allora `APOAPSIS  —`.
- Senza dati sull'orbita: tre righe con `—` e nessun avviso.

### Linea dell'orbita

- Nodo `OrbitLine` della navetta, con posizione indipendente dalla navetta
  (`top_level`), centrato sul pianeta.
- `ArrayMesh` a linea spezzata con 256 punti, ricostruita a ogni frame;
  materiale senza luce, azzurro semitrasparente, nessuna ombra.
- Orbita aperta: disegnata fino a 5 volte la distanza attuale dal centro.
- Nascosta senza pianeta.

## Fuori scope

- La rotazione lentissima del cielo (pianeta, sole, stelle) dovuta al
  sistema che ruota: un giro ogni 14,4 ore.
- Carburante, limiti ai propulsori (compensare le forze col blocco C costa
  sempre al massimo pochi m/s², molto sotto i 150 m/s²).
- Accelerazione del tempo.
- Forze orbitali dentro la stazione e sull'internal-cruiser.
- Atmosfera.
- La traiettoria vista dall'anello (con Coriolis): la linea mostra l'orbita
  vera rispetto alle stelle.

## Testing

- **`orbital_frame.gd`:**
  - ω dell'anello ≈ 1,2088·10⁻⁴ rad/s, velocità ≈ 840,1 m/s;
  - all'altezza dell'anello, nel piano, accelerazione netta ≈ 0;
  - lontano dall'asse della rotazione conta solo la gravità GM/r²;
  - Coriolis perpendicolare alla velocità, di modulo 2ωv;
  - ferma sull'anello: velocità vera ≈ 840 m/s, orbita circolare
    (periasse = apoasse = raggio dell'anello);
  - velocità vera più bassa: periasse sotto il raggio attuale;
  - oltre la velocità di fuga: orbita aperta, apoasse infinito;
  - i punti dell'orbita stanno alla distanza data dalla formula
    `p / (1 + e cos ν)` e, per un'orbita chiusa, la linea si chiude.
- **Assistenza:**
  - Tab la inverte e spegne il blocco C;
  - spenta: velocità e rotazione non calano senza spinta; W tenuto 10 s dà
    circa 1500 m/s (nessuna rampa, nessun limite);
  - accesa: i test di oggi su rampa, 21,6 km/s e blocco C restano verdi.
- **Forze:**
  - un'orbita circolare vera a 2500 km dal centro, con l'assistenza spenta:
    dopo 600 s simulati il raggio cambia di meno di 50 m;
  - blocco C con l'assistenza spenta in un punto di gravità forte: la
    velocità non cambia; Z la cambia e il blocco tiene quella nuova.
- **HUD:** righe nell'ordine giusto; testi di `ASSIST`, `ALTITUDE`,
  `PERIAPSIS`, `APOAPSIS`; `IMPACT` ed `ESCAPE` solo quando servono; `—`
  senza dati.
- **Linea:** 256 punti, centrata sul pianeta, nascosta senza pianeta.
- **Scena vera:**
  - la navetta trova il pianeta; il raggio dell'orbita coincide con quello
    della stazione;
  - l'HUD mostra una quota plausibile (circa 5222 km al punto di partenza);
  - dopo uno spostamento dell'origine la linea è ancora centrata sul
    pianeta;
  - Tab arriva alla navetta (nessun controllo dell'interfaccia lo
    intercetta).

## Verifica

Avvio headless senza errori e un render offscreen (xvfb) della linea
dell'orbita, da guardare prima di passarlo all'utente.

## Rischi noti

- **Tab e il fuoco dell'interfaccia:** Godot usa Tab per spostare il fuoco
  fra i controlli. L'HUD non ha controlli che prendono il fuoco; un test in
  scena lo verifica.
- **Precisione della linea:** i punti sono a milioni di metri dal centro del
  pianeta; in float a 32 bit l'errore è sotto il metro, invisibile.
