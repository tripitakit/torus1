# Moon Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native, by the plan's author in the
> same session). Interfaces and tests are fixed here; implementation is written during execution.

**Goal:** Tracce del rover e orme degli stivali che restano per la sessione; sassi e massi deterministici sulla
luna, i massi grandi come ostacoli per rover e pedone.

**Architecture:** Tre nodi figli della luna (`Rocks`, `Tracks`, `Footprints`) con funzioni pure testabili
(posizioni delle pietre, campionatore delle tracce, passo delle orme); il rover e il pedone li alimentano dal loro
`_physics_process`; `moon.gd` aggiorna il corpo dei massi a ogni tick come quello della base.

**Tech Stack:** Godot 4.6.1 doppia precisione, `gl_compatibility`, GDScript, test `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-05-moon-surface-design.md`

## Global Constraints

- Godot `~/Godot_v4.6.1-stable-double_linux.x86_64`; un test `--headless --path . -s tests/<file>.gd`.
- Solo test nuovi o toccati; TDD.
- Valori come da tabelle della spec (celle, probabilità, misure, raggi, passi; tracce 0,5 m, 0,3 m, ±0,9 m;
  orme 0,7/1,4 m, ±0,15 m, 0,13 × 0,32 m).
- Sollevamento max(0,02, 0,0004 × distanza), trasparenti, `depth_draw_never`.
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Corpo dei massi un tick indietro rispetto alla luna (rover che "attraversa" o urta il vuoto) —
   `_test_boulder_shapes_follow_the_moon`.
2. Pietre sui pad / nella base — `_test_none_at_selene`.
3. Tracce che proseguono dritte in aria o da fermo — `_test_no_samples_in_the_air_or_standing`.
4. Precisione: posizioni a 250 km nei float della GPU — origine locale per blocco (controllo a vista nella prova
  GPU).
5. Costo della ricostruzione delle pietre (thread separato; finestra per taglia) — misura nella prova GPU (FPS).

---

### Task 1: Sassi e massi — funzioni pure (`moon_rocks.gd`)

**Produces:** `MoonRocks.CLASSES` (dizionari `{cell, chance, low, high, reach, step}` per PEBBLE, ROCK, BOULDER),
`density(direction: Vector3) -> float` (moltiplicatore 0..4, 0 entro 700 m da Selene),
`stones_in(face: int, kind: int, low: Vector2, high: Vector2) -> Array` di
`{direction: Vector3, size: float, spin: float, squash: float, shape: int}` per le celle del rettangolo del piano
(metri sul piano della faccia).

- [ ] `tests/test_moon_rocks.gd` (parte pura): `_test_same_cell_same_stones`, `_test_denser_on_crater_rims`
  (`density` su un punto del bordo di un cratere fresco ≥ 2 × su un punto dove `crater_height` ≈ 0),
  `_test_none_at_selene` (nessuna pietra nelle celle entro 700 m dal centro della base), `_test_sizes_in_range`.

### Task 2: Sassi e massi — nodo, disegno, collisioni

**Produces:** nodo `MoonRocks` (Node3D) creato in `moon.gd build()` come `Rocks`, con `follow(point_local:
Vector3, collide: bool)`; `moon.follow_rocks(point: Vector3, collide: bool)`; `StaticBody3D` `RockBody`
aggiornato in `moon._place`. Rover (`moon_rover.gd`), pedone (`moon_walker.gd`) e nave (`void_cruiser.gd`, solo
disegno) chiamano `follow_rocks`.

- [ ] Test (scena piccola, come `test_moon_rover.gd`): `_test_boulder_shapes_near_the_walker_only`,
  `_test_boulder_shapes_follow_the_moon`, `_test_rover_stops_at_a_boulder`, `_test_walker_stops_at_a_boulder`.

### Task 3: Tracce del rover (`moon_tracks.gd`)

**Produces:** `MoonTracks.wheel_points(at: Transform3D) -> Array` (sinistra, destra al suolo);
`MoonTracks.Recorder` (stato) con `step(at: Transform3D, airborne: bool, speed: float) -> Array` (campioni da
aggiungere, `[]` o `[[left, right, up, new_strip: bool]]`); nodo `Tracks` (`add(left, right, up, new_strip)`
in coordinate della luna, `sample_count() -> int`). Il rover lo alimenta.

- [ ] `tests/test_moon_tracks.gd`: `_test_one_sample_every_half_metre`, `_test_no_samples_in_the_air_or_standing`,
  `_test_new_strip_after_a_jump`, `_test_rover_leaves_tracks` (scena piccola, 5 s: 70–80 campioni).

### Task 4: Orme (`moon_footprints.gd`)

**Produces:** `MoonFootprints.Gait` (stato) con `step(moved: float, jogging: bool, took_off: bool, landed: bool)
-> Array` di `{side: float (−1/+1/0), kind: int (WALK, JOG, TAKEOFF, LANDING)}`; nodo `Footprints`
(`add(position, nose, up, side, kind)` in coordinate della luna, `print_count() -> int`). Il pedone lo alimenta.

- [ ] `tests/test_moon_footprints.gd`: `_test_walk_stride`, `_test_jog_stride`, `_test_sides_alternate`,
  `_test_jump_prints`, `_test_walker_leaves_prints` (scena piccola, 5 s di camminata: 10–12 orme).

### Task 5: Prova GPU e note

- [ ] Scatti: tracce dietro il rover, orme (camminata, corsa, salto), un campo di massi; FPS sopra la base e lontano.
- [ ] "Cambiato durante l'esecuzione" nella spec; commit.
