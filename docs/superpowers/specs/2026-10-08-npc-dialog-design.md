# Dialogo libero con i personaggi (Gemma via Ollama) — progetto

Primo pezzo dell'avventura (premessa: gli equipaggi dell'UltraTelescopio e dell'Area 2 non rispondono più alla
radio; si parte da Selene, si cercano indizi su Torus1). Qui solo il **motore di dialogo**: avvicinarsi a una
persona, scriverle, ricevere la risposta da un modello locale. La trama completa, gli indizi e lo stato della
missione vengono dopo.

## Cosa vede il giocatore

- A piedi (Selene, sezioni di Torus1), con una persona entro **2,5 m davanti**, l'HUD mostra `P PARLA`.
- **P**: la persona si ferma e si gira verso il pilota; il pilota non si muove più; in basso si apre un
  **terminale anni '70** (ambra su nero, carattere a spaziatura fissa, cursore lampeggiante) con l'intestazione
  del personaggio (`>> FERRAND / COMANDO SELENE`), le ultime battute e la riga dove scrivere.
- **Invio** manda la domanda; la risposta compare lettera per lettera mentre arriva. **Esc** saluta e chiude.
- Mentre il terminale è aperto i tasti del gioco (K, H, 1–9, movimento) non agiscono.

## Personaggi

| Chi | Dove | Scheda |
|---|---|---|
| Comandante **Tomas Ferrand** | Selene, il suo ufficio sopra Main Mission (la persona "command" già in piedi lì) | `assets/npc/people/ferrand.cfg` |
| Dottoressa **Ines Okafor** | Selene, Main Mission, in piedi a una console della vetrata (persona nuova) | `okafor.cfg` |
| **Nico Bastiani**, investigatore privato | Torus1, in piedi alla piazzola dove porta il teleport 3 | `bastiani.cfg` |
| Equipaggio di Selene (gli altri 11) | dove sono ora | `selene_crew.cfg`, generica |
| Passanti di Torus1 (qualsiasi, vicino) | dove camminano | `townsfolk.cfg`, generica |

- Nome, età e mestiere delle comparse vengono da un **numero fisso** (indice del membro dell'equipaggio, id del
  giro del passante): la stessa persona ha sempre lo stesso nome.
- L'equipaggio sa del silenzio radio; la gente di Torus1 **non sa nulla** di rilevante.

## Ollama

- **Obbligatorio.** Al primo dialogo il gioco interroga `http://127.0.0.1:11434/api/version`; se non risponde
  avvia `OLLAMA_VULKAN=1 <binario> serve` (binario: impostazione `torus1/npc/ollama_binary`, di base
  `~/ollama/bin/ollama`) e aspetta fino a 15 s. All'uscita lo spegne **solo se l'ha avviato lui**.
- Se non parte o una chiamata fallisce: il terminale mostra `ERRORE: OLLAMA NON RISPONDE` e il dialogo non
  prosegue. Nessuna modalità senza Ollama.
- Modelli: `gemma3:1b` per le risposte (sulla GPU via Vulkan, ~0,5 s), `embeddinggemma` per gli embedding
  **sul processore** (`num_gpu: 0`, ~0,2 s a domanda) per lasciare la VRAM a Godot. Entrambi tenuti caricati
  (`keep_alive` 30 min).

## Fatti e embedding

- `assets/npc/facts.txt`: un fatto per riga, `chi | frase`. `chi` è `tutti`, `selene`, `torus1` o il nome di un
  personaggio. Più alcune righe `chiacchiere | …` (saluti, "che lavoro fai") che non entrano mai nel prompt ma
  dicono che una domanda è "del mondo".
- `tools/bake_npc_facts.gd` (si lancia a mano con Ollama acceso) calcola il vettore di ogni frase
  (`title: none | text: <frase>`) e scrive `assets/npc/facts.json` (`[{who, text, vector}]`).
- Durante il gioco si calcola solo il vettore della domanda (`task: search result | query: <domanda>`), poi:
  - **fuori tema**: se la somiglianza più alta con *tutti* i fatti è sotto **0,25**, il modello non viene
    chiamato e il personaggio risponde con una sua frase "non so" (misurato: domande sul mondo 0,43–0,62,
    chiacchiere 0,29–0,33, "sei un'IA?" 0,25, fuori tema 0,17–0,22);
  - altrimenti i **4 fatti più vicini** fra quelli che il personaggio conosce entrano nel prompt.

## Prompt (sotto ~400 token)

1. `system`: il nucleo del personaggio in seconda persona ("Tu sei …, sei un essere umano …"), le regole (italiano,
   al massimo due frasi, dai del tu al pilota, solo i fatti dati, se non sai dillo da persona), poi
   `Fatti che conosci:` e i 4 fatti.
2. Due battute d'esempio come turni già avvenuti (user/assistant).
3. Le ultime **6 battute** con questo personaggio.
4. La domanda.

Opzioni: `num_predict` 60, `temperature` 0,6. La risposta si taglia all'ultima frase completa.

## Filtri

- Dopo la risposta: se contiene una parola vietata (`intelligenza artificiale`, `modello linguistico`, `Google`,
  `assistente`, `sono un programma`, `IA`) si scarta e si **rigenera una volta**; se fallisce ancora, una frase
  "non so" del personaggio. Durante lo streaming il testo si mostra subito: una risposta scartata viene
  cancellata dal terminale e sostituita.

## Memoria

- Ferrand, Okafor, Bastiani: le ultime 6 battute restano per tutta la sessione (tornando da loro riprendono il
  filo). Le comparse dimenticano quando si chiude il dialogo. Niente salvataggio su disco.

## Passanti di Torus1

- Il tempo degli shader dei giri (`LoopTraffic`) passa da `TIME` a una **variabile globale** `loop_clock`
  impostata ogni frame dal gioco (`LoopTraffic.clock()`, secondi modulo 3600): così il processore sa dove sta
  ogni passante. Barche e scie la usano anche loro.
- Premendo P si cerca, fra i passanti animati vicini (`WalkersNear_*`), quello più vicino entro 2,5 m davanti,
  escluso chi di notte è a casa (stesso calcolo dello shader: `night_hide`).
- Quel passante si **nasconde** (dato personale dell'istanza, `INSTANCE_CUSTOM.x = 1`) e al suo posto compare una
  persona vera (il modello di Selene con la tuta del suo colore) che si ferma e si gira. Finito il dialogo resta
  ferma finché il pilota non è a più di 30 m; poi sparisce e il passante riappare sul suo giro.

## File

- `scripts/ollama_client.gd` — avvio/arresto del server, chat in streaming, embedding (HTTPClient, senza bloccare).
- `scripts/npc_brain.gd` — puro: schede, fatti, scelta dei fatti, soglia, messaggi, filtri, taglio.
- `scripts/npc_terminal.gd` — il terminale anni '70.
- `scripts/npc_talk.gd` — la conversazione: domanda → embedding → filtro → chat → filtro → terminale; memoria.
- `scripts/town_folk.gd` — identità delle comparse, passante più vicino, sostituto.
- Modifiche: `loop_traffic.gd`, `boat_wake.gd`, `interior_world.gd` (clock, passanti), `selene_crew.gd` (tuta),
  `selene_layout.gd` / `selene_interior.gd` (Ferrand, Okafor), `game_mode.gd` (P, prompt, Bastiani),
  `walker_hud.gd`/`interior_walker.gd` (blocco movimento), `project.godot` (azione `talk`, globale `loop_clock`).
- Dati: `assets/npc/facts.txt`, `assets/npc/facts.json`, `assets/npc/people/*.cfg`.

## Test

- Senza Ollama: `test_npc_brain.gd` (schede lette, fatti scelti con vettori finti e solo fra quelli noti, soglia,
  messaggi nell'ordine giusto, parole vietate, taglio), `test_town_folk.gd` (nome fisso, passante più vicino e
  davanti, notte), `test_loop_traffic.gd` (clock), `test_npc_terminal.gd` (righe, streaming, Esc).
- Con Ollama: `test_npc_live.gd` — dieci domande a ciascuno dei tre personaggi; nessuna parola vietata nelle
  risposte finali, tempi stampati.
- Prova GPU: il terminale aperto davanti a Ferrand.
