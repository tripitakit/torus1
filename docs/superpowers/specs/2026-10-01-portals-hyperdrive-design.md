# Portali e iperguida Terra–Luna

Data: 2026-10-01. Stato: approvato a voce, parte per parte.

## Scopo

Raggiungere la luna oggi vuol dire attraversare circa 20.000 km. Due portali (wormhole) collegano in 3 secondi
la zona di Torus1 con lo spazio sopra Base Selene, nei due sensi. Insieme:

- il marcatore HUD di SELENE si vede solo entro 5.000 km dal centro della luna (fatto, `cef6234`);
- un indicatore di avvicinamento al portale, con la velocità verde (OK) o rossa (TOO FAST!).

## Decisioni dell'utente

- Diametro interno dell'apertura 300 m.
- Portale Terra: fermo nel riferimento di Torus1, circa 100 km oltre l'anello, verso il lato della luna, a
  circa 120 km dalla partenza. Si entra volando verso l'esterno: il lato attivo guarda il pianeta.
- Portale Luna: fermo sulla luna, 20 km sopra Base Selene, lato attivo verso il basso. Si esce in picchiata
  verso la base; per tornare si sale dentro dal basso.
- Si entra solo sotto 300 m/s (velocità rispetto al portale). A 300 m/s o più: schianto.
- Si esce alla velocità d'entrata.
- Effetto sub-spazio: tunnel 3D attorno alla telecamera (approccio A), lampi bianchi a inizio e fine.

## Portali

Un nodo `portal.gd` per portale. Asse locale +Z: la normale del lato attivo (punta fuori dal lato da cui si
entra). Origine: centro dell'apertura.

- Bordo: anello di raggio interno 150 m, spessore 15 m; 8 blocchi squadrati sul bordo. Colore della luce:
  blu (Terra), ambra (Luna).
- Orizzonte: disco semitrasparente che ondeggia, senza collisione.
- Luci: 16 lampade sul bordo che si accendono in sequenza; un beacon forte visibile da ogni distanza
  (shader delle lampade della stazione, come il beacon di Selene).
- Collisione: il bordo e i blocchi (box disposti in cerchio) in uno StaticBody3D. Toccarli è uno schianto.
- Il portale Terra è figlio di PlanetSystem (lo spostamento dell'origine lo porta con sé). Il portale Luna è
  figlio della Luna; `moon._place` aggiorna il suo corpo fisico a ogni tick, come la base.

Posizione Terra, negli assi di PlanetSystem (centro del pianeta nell'origine, asse Y): raggio
`ring_radius + 100 km`, ruotato di 80 km d'arco dalla direzione della partenza (+Z) verso −X (lato della
luna alla partenza), nel piano y = 0. +Z del portale verso il centro del pianeta, Y del portale = asse.

Posizione Luna, negli assi della luna: sito della base sollevato di 20 km lungo la verticale; +Z del portale
= giù.

## Salto

A ogni passo di fisica, prima di muovere la nave, si prende il segmento da dove è a dove arriva. Se attraversa
il piano dell'apertura passando dal lato +Z al lato −Z, entro 150 m dal centro:

- velocità ≥ 300 m/s: schianto nel punto d'attraversamento (vicino alla luna `crashed_on_moon`, quindi
  ripartenza sulla piazzola 1; altrimenti al dock, come oggi);
- sotto: inizia il transito.

Attraversare da dietro (−Z verso +Z) non fa niente.

Transito, 3 s:

- la nave resta ferma dove è entrata, senza collisioni; comandi, cruise e freno ignorati;
- il cockpit mostra il tunnel e i lampi;
- alla fine la nave va all'altro portale: posizione, orientamento e velocità relativi al portale d'entrata,
  ruotati di 180° attorno alla Y del portale, riportati sul portale d'uscita. Esce quindi dal lato attivo,
  allontanandosi, alla stessa velocità, spostata di lato come era entrata;
- riferimento all'uscita: lunare per il portale Luna (è sotto i 30 km), dell'anello per il portale Terra;
- cruise e freno spenti, auto-livello azzerato, `is_landed` falso.

La nave all'uscita si allontana dal lato attivo, quindi non rientra se non torna indietro apposta.

## HUD

- Pannello GATE, in alto al centro, entro 5 km dal portale più vicino:
  - `GATE → LUNA  3.2 km` (o TERRA);
  - `APPROACH 120 m/s  OK` verde sotto 300 m/s, `APPROACH 350 m/s  TOO FAST!` rosso;
  - `WRONG SIDE` quando la nave è dietro al lato attivo.
  La velocità mostrata è il modulo della velocità rispetto al portale (quella che decide lo schianto).
- Marcatore GATE: il marcatore di SELENE con colore azzurro e scritta "GATE", sul portale più vicino entro
  2.000 km, nascosto sotto 300 m.

## Codice

- `scripts/portal_rules.gd` (puro): costanti, `crossing(from, to, portal) -> float` (frazione del
  segmento, −1 se non attraversa dal lato attivo), `speed_ok`, `exit_transform`, `exit_velocity`,
  `earth_transform(ring_radius)`, `moon_local_transform(base_local)`, `readout(...)`.
- `scripts/portal.gd`: costruzione del portale, `destination` (nome), `active_transform()`.
- `scripts/subspace_tunnel.gd`: tunnel e lampi attaccati al cockpit; `start()`, `stop()`, avanzamento in
  `_process`.
- `beacon_marker.gd`: colore e prefisso come variabili.
- `void_cruiser.gd`: elenco dei portali (gruppo `portals`), controllo d'entrata in `_move`, transito,
  uscita, collisione col bordo, HUD.
- `moon.gd`: crea il portale Luna e ne aggiorna il corpo. Scena: `EarthPortal` sotto PlanetSystem.
- `cockpit.gd`: pannello GATE, marcatore GATE, tunnel.

## Test

- `test_portal_rules`: attraversamento dal lato attivo, da dietro, fuori dal disco, segmento che non arriva;
  soglia 300; uscita (spostamento laterale, velocità, orientamento; andata e ritorno ribaltati);
  posizioni dei portali; righe del pannello.
- `test_portal_physics` (scena vera): Terra → Luna a 100 m/s, poi Luna → Terra; 400 m/s schianto; bordo
  schianto; da dietro nessun salto.
- `test_cockpit`: pannello GATE e marcatore GATE presenti e nascosti all'avvio; tunnel spento all'avvio.
- Prova sulla GPU con screenshot (portale da vicino e da lontano, tunnel). Il gioco non si avvia.
