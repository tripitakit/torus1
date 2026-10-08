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
