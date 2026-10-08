# Fatti e personalità dei personaggi — progetto

Il motore di dialogo (2026-10-08-npc-dialog) funziona, ma le risposte **non rispondono alla domanda** e la
**personalità è piatta**: 43 fatti in terza persona e un paragrafo di carattere non bastano a `gemma3:1b`, che
inventa quando non trova niente di concreto. Qui: una base di conoscenza per personaggio, nella sua voce.

## Dati

Per ogni personaggio una cartella `assets/npc/people/<id>/`:

- `sheet.cfg` — nome, etichetta, nucleo breve in seconda persona, quali fatti del mondo conosce (`knows`), frasi
  "non so", se ricorda (`remembers`). Le schede generiche (`selene_crew`, `townsfolk`) hanno i segnaposto
  `{name}`, `{surname}`, `{age}`, `{job}`, `{place}`, anche in `qa.txt` e `memories.txt`.
- `qa.txt` — coppie `domanda | risposta`, una per riga, nella voce del personaggio, al massimo due frasi:
  **100** per Ferrand, Okafor, Bastiani; **40** per le schede generiche.
- `memories.txt` — 30–50 ricordi e opinioni in prima persona, uno per riga.

`assets/npc/facts.txt` resta per i fatti del mondo condivisi (`tutti`, `selene`, `torus1`); i fatti personali e le
"chiacchiere" passano nei file dei personaggi.

**Indizi (per la trama, non usati ora):** ogni riga di `qa.txt`, `memories.txt` o `facts.txt` può cominciare con
`[dopo:<indizio>]`: resta nascosta finché il giocatore non ha quell'indizio. Commenti `#` e righe vuote ignorati.

## Vettori

`tools/bake_npc_knowledge.gd` (sostituisce `bake_npc_facts.gd`) calcola con `embeddinggemma`:
- fatti e ricordi come testi (`title: none | text: …`);
- le **domande** delle coppie come domande (`task: search result | query: …`), come quella del giocatore: il
  confronto è fra domanda e domanda.

Scrive `assets/npc/knowledge.json`: `{"world": [...], "people": {id: {"qa": [...], "memories": [...]}}}`.

## Prompt

1. `system`: nucleo + regole + `I tuoi ricordi:` (i 3 più vicini) + `Fatti che conosci:` (i 2 più vicini fra quelli
   che conosce).
2. Le **3 coppie** con la domanda più simile, come turni già avvenuti (al posto dei 2 esempi fissi).
3. Le ultime 6 battute, la domanda.

Soglia fuori tema (0,25) sulla somiglianza massima con fatti del mondo, domande delle coppie e ricordi del
personaggio.

## Personaggi (canone)

- **Tomas Ferrand**, 56: nato nella sezione 412 di Torus1, figlio di un macchinista; 18 anni pilota di Eagle, poi
  vicecomandante, comandante di Selene da 9 anni. Separato; una figlia, Elsa (24), studia ingegneria su Torus1.
  Caffè nero, sveglia alle 5. Selene ha 180 persone e 4 Eagle (2 in manutenzione). La radio di Selene e il satellite
  relè Eco funzionano ai test: sono gli avamposti a tacere. Se la radio non torna, pensa di chiedere al pilota di
  volare laggiù.
- **Ines Okafor**, 38: nata nella sezione agricola 1530, genitori contadini; dottorato in radioastronomia
  all'Università dell'Anello; da 5 anni responsabile scientifica dell'UltraTelescopio (parabola di 300 m, cupola
  con alloggi per sei, turni di sei settimane). Squadra di turno: Rhea Lindqvist (45, capoturno, sua amica), Sami
  Haddad (29, astronomo, scherza sempre), Paolo Ferri (50, tecnico della parabola, burbero, cucina per tutti), June
  Akagi (26, dottoranda, primo turno lungo). Ultima chiamata ieri alle 18. Ha paura della notte lunare.
- **Nico Bastiani**, 51: investigatore privato in questa sezione, ufficio sopra il Bar Orbita; 20 anni nella
  sicurezza dell'anello, lasciata 6 anni fa dopo un caso finito male (un ragazzo scomparso, arrestato l'uomo
  sbagliato). Beve solo chinotto. Sorella Lia, tecnica dei filtri d'aria. Clienti: merci sparite agli attracchi,
  mariti gelosi, gatti. Mai stato sulla Luna; sa che all'attracco si vede chi arriva fuori orario.
- **Area 2**: Viktor Brandt (capo, ex militare, rigido), Ana Ruiz (chimica), Kofi Mensah (tecnico, primo turno).
  Ultima chiamata ieri alle 20.
- **Comparse**: l'equipaggio sa del silenzio e ne parla per sentito dire; la gente di Torus1 non sa nulla della Luna
  ma sa che sopra il Bar Orbita c'è un investigatore.

## Test

- `test_npc_brain.gd`: lettura delle cartelle; righe `[dopo:…]` nascoste senza l'indizio e visibili con; scelta
  delle 3 coppie e dei ricordi con vettori finti; messaggi nell'ordine giusto; segnaposto riempiti anche in coppie e
  ricordi; ogni scheda nominata ha ≥100 coppie, ogni generica ≥40, ogni risposta ≤ 2 frasi.
- `test_npc_talk.gd` aggiornato alla nuova base.
- `test_npc_live.gd`: le 10 domande di prima più 10 nuove a ciascuno; risposte stampate per il confronto.
