# Fatti e personalità — piano

> Esecuzione: nativa, TDD, ramo `npc-knowledge`. Spec: `docs/superpowers/specs/2026-10-08-npc-knowledge-design.md`.

## Task 1: formato e NpcBrain
- Test rossi in `test_npc_brain.gd`: `parse_lines(text) -> [{after, text}]`, `parse_qa(text) -> [{after, q, a}]`,
  `visible(entries, clues) -> Array`, `person(id)` dalla cartella, `fill` anche di qa e ricordi,
  `pick(entries, vector, count) -> Array` (per `vector` di ogni voce), `messages(sheet, memories, facts, pairs,
  history, question)`.
- NpcBrain: `load_knowledge(path) -> {world, people}`; `best` su più liste.

## Task 2: contenuti
- Cartelle `ferrand`, `okafor`, `bastiani` (100 coppie, 30–50 ricordi), `selene_crew`, `townsfolk` (40 coppie,
  ricordi generici); `facts.txt` ripulito (solo fatti del mondo). Test: conteggi, ≤2 frasi, nessun segnaposto
  rimasto dopo `fill`.

## Task 3: bake e NpcTalk
- `tools/bake_npc_knowledge.gd` → `assets/npc/knowledge.json`; rimuovere `bake_npc_facts.gd` e `facts.json`.
- `NpcTalk`: usa la base per persona (`knowledge`), `clues` (vuoto) per le righe `[dopo:]`.
- `test_npc_talk.gd` aggiornato; `TownFolk.sheet_for` invariato nell'interfaccia.

## Task 4: prova dal vivo e documenti
- `test_npc_live.gd` con 20 domande; confronto con le risposte di prima; README; commit.

## Decisioni prese durante l'esecuzione

- I vettori in `knowledge.json` sono base64 dei float32 (2,2 MB invece di ~5): si leggono senza convertire numeri.
- `embed_many` nel client: i 550 vettori in ~30 s a gruppi di 32.
- Prima prova dal vivo: anche con la coppia identica nel prompt (somiglianza 1,0) `gemma3:1b` rispondeva altro
  (Ferrand: "Viktor Brandt" al telescopio). Quindi **risposta scritta** quando la domanda somiglia a una coppia
  ≥ 0,63 (riformulazioni giuste 0,65–0,91, abbinamenti sbagliati fino a 0,60), il modello solo per il resto.
- Il filtro fuori tema contava anche le coppie e non scattava più (mondiali: 0,33 con le coppie): ora la domanda è
  "del mondo" se somiglia ≥ 0,55 a una coppia o ≥ 0,30 a un fatto o a un ricordo.
- Le frasi delle comparse sono neutre (nome e mestiere possono essere femminili).
- Dopo il merge: risposte del modello ancora sconclusionate con `gemma3:1b`. Il Gemma 3 4B locale (`gemma3-local`)
  non aveva il formato per la chat; con quello dei modelli ufficiali (`tools/ollama/gemma3-4b-chat.Modelfile`)
  segue ricordi e fatti molto meglio. Misurato nel gioco: risposte in 3–4 s (1 s col 1B), il modello per un terzo
  sul processore perché Godot occupa la scheda video, FPS durante il dialogo ancora alti. Predefinito ora il 4B
  (`torus1/npc/chat_model`), con le risposte scritte per le domande vicine alle coppie.
