# Dialogo libero con i personaggi — piano

> Esecuzione: nativa (in sessione), TDD, un commit per task sul ramo `npc-dialog`.

**Goal:** parlare liberamente con Ferrand, Okafor, Bastiani, l'equipaggio di Selene e i passanti di Torus1,
con risposte di `gemma3:1b` e fatti scelti da `embeddinggemma`.

**Spec:** `docs/superpowers/specs/2026-10-08-npc-dialog-design.md`

**Comandi:** `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/<test>.gd`
(si eseguono solo i test nuovi o toccati).

## Global constraints

- Ollama: `OLLAMA_VULKAN=1 ~/ollama/bin/ollama serve`, `127.0.0.1:11434`; modelli `gemma3:1b`, `embeddinggemma`.
- Embedding sul processore (`options.num_gpu = 0`); chat sulla GPU.
- Soglia fuori tema 0,25; 4 fatti; 6 battute di memoria; `num_predict` 60; `temperature` 0,6.
- Tasto P (azione `talk`, physical_keycode 80); raggio 2,5 m davanti (coseno > 0,5).

## Review focus

1. Scrivere nel terminale non deve muovere il pilota né far scattare K/H/1–9.
2. Una risposta scartata dal filtro non deve restare a metà nel terminale.
3. Il passante nascosto deve riapparire anche se si esce dalla sezione durante il dialogo.
4. Ollama avviato dal gioco va spento all'uscita, mai uno già acceso dall'utente.
5. Testo UTF-8 (accenti) intatto attraverso lo streaming a pezzi.

---

### Task 1: dati e `NpcBrain`

**Files:** `assets/npc/facts.txt`, `assets/npc/people/{ferrand,okafor,bastiani,selene_crew,townsfolk}.cfg`,
`scripts/npc_brain.gd`, `tests/test_npc_brain.gd`.

**Interfaces (produce):**
- `NpcBrain.person(id: String) -> Dictionary` — `{id, name, label, core, knows: PackedStringArray, examples: Array[[q,a]], dunno: PackedStringArray, remembers: bool}`; le schede generiche hanno `{name}`, `{age}`, `{job}`, `{place}` nel `core`/`label`.
- `NpcBrain.fill(person, identity: Dictionary) -> Dictionary` — sostituisce i segnaposto.
- `NpcBrain.parse_facts(text: String) -> Array` — `[{who, text}]` (commenti `#` e righe vuote ignorati).
- `NpcBrain.load_facts(path) -> Array` — `[{who, text, vector: PackedFloat32Array}]` da facts.json.
- `NpcBrain.best(facts, vector) -> float` — somiglianza massima con tutti i fatti.
- `NpcBrain.relevant(facts, vector, knows, count) -> PackedStringArray` — i `count` più vicini fra quelli noti (mai `chiacchiere`).
- `NpcBrain.messages(person, facts: PackedStringArray, history: Array, question: String) -> Array` — messaggi Ollama.
- `NpcBrain.rejected(reply) -> bool`, `NpcBrain.trim(reply) -> String`, `NpcBrain.dunno(person, rng) -> String`.

**Test (prima rossi):** scheda di Ferrand letta con nome, 2 esempi, ≥2 "non so"; `fill` sostituisce i segnaposto;
`parse_facts` salta commenti; `relevant` con vettori finti sceglie i più vicini e salta i fatti non noti e le
chiacchiere; `best` sotto/sopra soglia; `messages` = system (contiene nucleo e fatti) + 2×2 esempi + storia + domanda;
`rejected` su "Sono un'intelligenza artificiale", "un modello linguistico", "IA" (parola intera) ma non su "Ciao, via";
`trim` taglia all'ultima frase completa.

### Task 2: `OllamaClient` e bake dei fatti

**Files:** `scripts/ollama_client.gd`, `tools/bake_npc_facts.gd`, `assets/npc/facts.json`, `tests/test_ollama_client.gd`.

**Interfaces:** `OllamaClient` (Node): `ensure_running() -> bool` (await), `embed(text: String) -> PackedFloat32Array`
(await; vuoto se errore), `chat(messages) -> void` con segnali `piece(text)`, `finished(text)`, `failed(reason)`;
statico `parse_lines(buffer: PackedByteArray) -> [pieces: Array[Dictionary], rest: PackedByteArray]` (NDJSON a pezzi,
byte UTF-8 spezzati tenuti nel resto); `stop_if_started()` chiamato in `_exit_tree`.

**Test:** `parse_lines` con una riga spezzata a metà e una "è" spezzata fra due pezzi; (vivo, se Ollama c'è)
`ensure_running` e un `embed` di 768 valori.

**Bake:** `tools/bake_npc_facts.gd` legge `facts.txt`, chiama `embed` per ogni frase, scrive `facts.json`.

### Task 3: `NpcTerminal`

**Files:** `scripts/npc_terminal.gd`, `tests/test_npc_terminal.gd`.

**Interfaces:** CanvasLayer: `open(label: String)`, `close()`, `is_open() -> bool`, `add_line(who, text)`,
`begin_reply(who)`, `append(text)`, `replace_reply(text)`, `set_waiting(bool)`, `show_error(text)`; segnali
`asked(text)`, `closed`. Ambra `#FFB000` su nero 85 %, SystemFont monospazio, ultime 8 righe, cursore che lampeggia.

**Test:** apri → `is_open`; Invio con testo emette `asked` e svuota la riga; testo vuoto non emette; `begin_reply` +
`append` costruisce la riga; `replace_reply` la sostituisce; Esc (ui_cancel) emette `closed`.

### Task 4: `NpcTalk` (conversazione)

**Files:** `scripts/npc_talk.gd`, `tests/test_npc_talk.gd`.

**Interfaces:** Node con `client` (OllamaClient o finto con gli stessi metodi/segnali) e `terminal`:
`start(person: Dictionary)`, `end()`, `talking() -> bool`; segnale `ended`. Flusso: `asked` → `embed` → se
`best < 0.25` "non so" → altrimenti `chat` con `messages`; `piece` → `append`; `finished` → `trim`; se `rejected`
→ una seconda chat, poi "non so"; la battuta va in memoria (`remembers`) o in una storia temporanea.

**Test (client finto):** domanda fuori tema → "non so" senza chat; risposta buona → in terminale e in memoria; risposta
vietata due volte → "non so"; memoria di Ferrand resta dopo `end()`, quella di una comparsa no; errore → `show_error`.

### Task 5: clock dei giri e passanti

**Files:** `project.godot` (`loop_clock`), `scripts/loop_traffic.gd`, `scripts/boat_wake.gd`,
`scripts/interior_world.gd`, `scripts/town_folk.gd`, `tests/test_loop_traffic.gd`, `tests/test_town_folk.gd`.

**Interfaces:** `LoopTraffic.clock() -> float`; shader `global uniform float loop_clock`, `INSTANCE_CUSTOM.x > 0.5`
nasconde; `InteriorWorld` imposta `loop_clock` in `_process`. `TownFolk.identity(id: int) -> {name, age, job}`;
`TownFolk.nearest(nodes: Array[MultiMeshInstance3D], from: Transform3D, time, corner, night: Callable) -> {node, index, pose}`
o `{}`; `TownFolk.stand_in(paint: Color) -> CrewMember`.

**Test:** il codice degli shader contiene `loop_clock` e non `TIME` nella posa; `identity` uguale due volte, ≥30
nomi diversi su 100; `nearest` sceglie il passante davanti entro 2,5 m, scarta quello dietro e quello di notte.

### Task 6: Selene e Bastiani nel gioco

**Files:** `scripts/selene_crew.gd` (uniform `suit`), `scripts/selene_layout.gd` (Okafor), `scripts/selene_interior.gd`
(meta `npc`), `scripts/game_mode.gd`, `scripts/walker_hud.gd`, `scripts/interior_walker.gd`, `project.godot` (`talk`),
`tests/test_npc_game.gd`.

**Interfaces:** ogni CrewMember ha `npc` (id scheda) e `npc_seed`; `GameMode.talk_target() -> Node3D`;
`InteriorWalker.frozen`/`BaseWalker.frozen` blocca movimento e sguardo. P apre il terminale; Esc chiude.

**Test:** in Selene Ferrand e Okafor esistono con `npc`; davanti a Ferrand `talk_target` è lui; a 4 m è nullo;
`frozen` non muove il pilota con controlli in avanti.

### Task 7: prova dal vivo, GPU, documenti

`tests/test_npc_live.gd` (10 domande × 3), prova GPU del terminale davanti a Ferrand, README, commit.
