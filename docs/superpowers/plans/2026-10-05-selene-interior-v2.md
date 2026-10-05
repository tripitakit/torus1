# Selene Interior v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native, by the plan's author in the
> same session). Interfaces and tests are fixed here; implementation is written during execution.

**Goal:** Interni di Selene più ampi, chiusi, dettagliati e sci-fi, con meno persone, colonna completa e viaggio
vero in Travel Tube.

**Architecture:** `SeleneLayout` v2 (pianta, pareti unite, frecce della colonna, percorsi) → `SeleneInterior`
(pareti piene, dettagli, colonna, tunnel e cabina `TubeCar`) → `SeleneCrew` (12, seduti dopo l'ingresso in
scena) → `GameMode` (K in cabina/chiamata, prompt).

**Tech Stack:** Godot 4.6.1 doppia precisione, `gl_compatibility`, GDScript, test `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-05-selene-interior-v2-design.md`

## Global Constraints

- Godot `~/Godot_v4.6.1-stable-double_linux.x86_64`; un test `--headless --path . -s tests/<file>.gd`.
- Solo test nuovi o toccati; TDD. Pianta e misure della tabella della spec.
- Cabina 4,4 × 3,2 × 2,8; viaggio ~10 s (2 s di accelerazione, 2 di frenata); anelli del tunnel ogni 6 m.
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Pedone che esce dalla cabina in corsa o resta indietro — la porta della cabina è chiusa in viaggio, chi è
   dentro si sposta con lei — `_test_ride_carries_the_walker`.
2. Fessure fra pareti agli angoli e agli incroci — `_test_corners_closed`.
3. Seduti che tornano in piedi entrando nella scena — `_test_seated_after_entering_the_scene`.
4. Cabina all'altra fermata: il giocatore resta bloccato — `_test_call_brings_the_car`.
5. Persone dentro pareti o arredi con la nuova pianta — `_test_routes_clear_of_walls_and_furniture`.

---

### Task 1: Pianta v2 (`selene_layout.gd`)

**Produces:** come v1 più: stanza `tunnel` (zona "tube"), porte di tipo `tunnel`; `walls()` unite
`{from, to, height, window, faces: [room a sinistra, room a destra]}`; `post_signs() -> Array` di
`{normal: Vector3, lines: Array[[label, arrow ("←","→","↑","↓")]]}`; `tube_car_stops() -> Dictionary`
`{dock: Vector3, centre: Vector3}` (centro della cabina); `crew_seats() -> Array` (i 4 occupati); percorsi 6.

- [ ] `tests/test_selene_layout.gd`: aggiornato alla v2 più `_test_corners_closed`, `_test_post_arrows`.

### Task 2: Scena v2 (`selene_interior.gd`) — pareti piene e dettagli

**Produces:** pareti a box dalle `walls()` unite; dettagli dei corridoi, delle porte, della Main Mission,
dell'hangar e delle stanze; colonna con schermo, console e cartelli con le frecce.

- [ ] `tests/test_selene_interior.gd`: posizioni v2 (muro, porte, ufficio, salita).

### Task 3: Travel Tube (`selene_interior.gd`: `TubeCar`, tunnel)

**Produces:** `SeleneInterior.tube_car() -> Node3D`; `car_stop() -> String` ("dock"/"centre"/"" in viaggio);
`start_ride() -> bool`; `call_car(stop) -> bool`; `in_car(point) -> bool`; `near_tube_door(point) -> String`
(la fermata davanti alla cui porta si è, o "").

- [ ] `tests/test_selene_interior.gd`: `_test_ride_carries_the_walker`, `_test_car_door_shut_while_riding`,
  `_test_call_brings_the_car`.

### Task 4: Equipaggio v2 (`selene_crew.gd`, `_build_crew`)

- [ ] `tests/test_selene_crew.gd`: `_test_twelve_in_the_base` (12, 4 seduti),
  `_test_seated_after_entering_the_scene`.

### Task 5: GameMode

- [ ] `tests/test_game_mode.gd`: `_test_tube_ride_from_game_mode` (K in cabina, attesa del viaggio, centro; e
  ritorno), `_test_k_by_the_lift_returns_to_the_eagle` invariato.

### Task 6: Prova GPU, README, note

- [ ] Scatti (SubViewport + `frame_post_draw`): hangar, corridoio e colonna, Main Mission, cabina nel tunnel,
  infermeria; FPS. README; "Cambiato durante l'esecuzione"; commit.
