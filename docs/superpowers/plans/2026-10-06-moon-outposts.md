# Moon Outposts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native, by the plan's author in the
> same session). Interfaces and tests are fixed here; implementation is written during execution.

**Goal:** UltraTelescopio e Area 2 sulla faccia nascosta, con pad, bersagli, esterni, recinto laser e interni
esplorabili (airlock + sala) col costruttore stile Alpha.

**Architecture:** `AlphaPlan` (pareti/room_at generici) e `AlphaInterior` (costruttore generico) estratti da
Selene; `TelescopeLayout`/`DepotLayout` + `OutpostInterior`; `MoonSites` (dati, terreno, esterni, collisioni)
sulla luna; pad 7–8 e bersagli; `GameMode` con `IN_OUTPOST`.

**Tech Stack:** Godot 4.6.1 doppia precisione, `gl_compatibility`, GDScript, test `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-06-moon-outposts-design.md`

## Global Constraints

- Godot `~/Godot_v4.6.1-stable-double_linux.x86_64`; un test `--headless --path . -s tests/<file>.gd`.
- Solo test nuovi o toccati; TDD. Misure e posizioni della spec.
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Selene cambiata dal passaggio al costruttore comune — i test di Selene (layout, interni, equipaggio,
   game mode) restano verdi.
2. Corpi dei siti un tick indietro rispetto alla luna — aggiornati in `_place` come la base.
3. H che porta in Selene dal pad del telescopio — `_test_h_only_on_selene_pads`.
4. `MoonTerrain.height` più lento (chiamato moltissimo) — confronto con il coseno, `acos` solo vicino a un sito.
5. Uscita dall'avamposto in un punto bloccato — si torna dove si era entrati.

---

### Task 1: AlphaPlan + AlphaInterior (rifattorizzazione, nessun cambiamento per Selene)

**Produces:** `AlphaPlan.walls(rooms, doors, windows) -> Array`, `AlphaPlan.room_at(rooms, point) -> String`;
`AlphaInterior` (Node3D) con `layout: GDScript`, `build_shell()`, gli aiuti di costruzione, `SlidingDoor`,
`room_name()`; `SeleneInterior extends AlphaInterior`.

- [ ] Test esistenti di Selene verdi: `test_selene_layout`, `test_selene_interior`, `test_selene_crew`.

### Task 2: Piante degli avamposti

**Produces:** `TelescopeLayout`, `DepotLayout` con `rooms()`, `doors()`, `walls()`, `furniture()`, `room_at()`,
`room_rect()`, `corridors()`, `window_view() -> Dictionary {room, kind}`, `hatch() -> Transform3D` (centro del
portello, faccia verso dentro), `spawn() -> Transform3D`.

- [ ] `tests/test_outpost_layouts.gd`.

### Task 3: Interni degli avamposti (`outpost_interior.gd`)

**Produces:** `OutpostInterior.new()` con `layout`; `near_hatch(point) -> bool`; `spawn_transform()`.

- [ ] `tests/test_outpost_interior.gd`.

### Task 4: Siti sulla luna (`moon_sites.gd`, `moon_terrain.gd`, `moon_rocks.gd`, `moon.gd`)

**Produces:** `MoonSites.SITES` (`telescope`, `area2`: direzione, piano, raccordo); `MoonSites.silos() ->
Array[Vector2]`, `fence_posts() -> Array[Vector2]`, `cross_area() -> float`; `moon.site_transform(name)`,
`moon.pad_transform(7|8)`, `moon.hatch_transform(name)` (mondo); nodi `Sites/*`.

- [ ] `tests/test_moon_sites.gd`.

### Task 5: Pad e bersagli

**Produces:** `moon.all_pads() -> Array[Transform3D]`; `landing_target()` su tutti i pad; `FlightComputer`
TARGETS/MOON_SIDE con `TELESCOPE`, `AREA 2`; `NavTargets.point` per i due.

- [ ] Test toccati dei bersagli e del game mode (`_test_h_only_on_selene_pads`).

### Task 6: GameMode

**Produces:** `Mode.IN_OUTPOST`, `enter_outpost(name)`, `exit_outpost()`, `_near_hatch() -> String`.

- [ ] `tests/test_game_mode.gd`: `_test_k_airlock_prompt`, `_test_k_enters_and_leaves_the_outpost`.

### Task 7: Prova GPU, README, note
