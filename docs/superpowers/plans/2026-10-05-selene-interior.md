# Selene Interior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native, by the plan's author in the
> same session). Interfaces and tests are fixed here; implementation is written during execution.

**Goal:** Interni camminabili della base Selene in stile Base Alpha (sala di sbarco, Travel Tube, corridoio,
Main Mission, infermeria, alloggi, sala comune) con l'equipaggio che cammina, siede e lavora; si entra con B
dall'Eagle posata su un pad di Selene, si esce con K all'ascensore.

**Architecture:** `SeleneLayout` (dati puri: stanze, porte, percorsi, posti) → `SeleneInterior` (scena costruita
a codice: pareti con i vani delle porte, arredi, luci, collisioni, porte scorrevoli, Travel Tube) →
`SeleneCrew` (Quaternius con scheletro, colori per reparto, camminatori/seduti/al lavoro). `GameMode` stacca il
mondo esterno come per gli interni delle sezioni (nuovo modo `IN_BASE`). Il pedone è `InteriorWalker` con
gravità piatta.

**Tech Stack:** Godot 4.6.1 doppia precisione, `gl_compatibility`, GDScript, test `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-05-selene-interior-design.md`

## Global Constraints

- Godot `~/Godot_v4.6.1-stable-double_linux.x86_64`; un test `--headless --path . -s tests/<file>.gd`.
- Solo test nuovi o toccati; TDD.
- Valori della spec: griglia 1,2 m; misure della tabella degli ambienti; porte 1,2 m (doppie 2,4 m), aperte
  entro 2 m in 0,5 s; dissolvenze 2 s (entrata), 1,5 s (Travel Tube); `K EAGLE` entro 3 m dalla piattaforma;
  camminatori 1,2 m/s, soste 3–8 s, si fermano con il giocatore davanti entro 1,2 m; gravità 9,81 −Y.
- Colori delle maniche: Main Mission arancio, Medicina bianco, Sicurezza viola, Tecnici giallo, Comando nero.
- Tasto `base` = B (66).
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Ritorno dall'interno: la luna e l'Eagle staccati e riattaccati — l'Eagle deve ritrovarsi ferma sullo stesso
   pad (la luna non deve "saltare" mentre era staccata) — `_test_base_round_trip_keeps_the_ship_on_its_pad`.
2. Pedone che passa attraverso una porta chiusa o resta incastrato in una porta che si chiude — la porta resta
   aperta finché qualcuno è entro 2 m — `_test_door_stays_open_while_someone_is_in_it`.
3. Camminatori dell'equipaggio che attraversano pareti o arredi — percorsi solo per i vani delle porte e lontani
   0,5 m dagli arredi — `_test_routes_clear_of_walls_and_furniture`.
4. Equipaggio che sbarra la strada al giocatore per sempre (si fermano entrambi) — il camminatore si ferma al più
   10 s, poi riparte — `_test_walker_waits_then_goes_on`.
5. Luci: al più 8 per oggetto in `gl_compatibility` (pareti lunghe divise in pezzi) — controllo nella prova GPU e
   `_test_wall_pieces_short`.

---

### Task 1: Pianta (`selene_layout.gd`, funzioni pure)

**Produces:** `SeleneLayout.rooms() -> Array` di `{name, label, rect: Rect2 (x, z), height, zone ("dock"/"centre")}`;
`doors() -> Array` di `{a, b, centre: Vector3, width, axis ("x"/"z")}`; `walls() -> Array` di segmenti
`{from: Vector2, to: Vector2, height}` (con i vani delle porte); `routes() -> Array` di `{department, points:
PackedVector3Array}` (giri chiusi); `seats() -> Array` di `Transform3D` (uno per scrivania); `workers() -> Array`
di `{department, transform}`; `lift_centre() -> Vector3`; `tube_stops() -> Dictionary` `{dock: Transform3D,
centre: Transform3D}`; `room_at(point: Vector3) -> String`; `furniture() -> Array` di `{kind, transform, size}`.

- [ ] `tests/test_selene_layout.gd`: `_test_rooms_sizes`, `_test_rooms_do_not_overlap`,
  `_test_every_centre_room_reached_from_reception`, `_test_routes_cross_walls_only_at_doors`,
  `_test_routes_clear_of_walls_and_furniture`, `_test_one_seat_per_desk`, `_test_room_at`,
  `_test_wall_pieces_short` (nessun pezzo di parete oltre 12 m).

### Task 2: Pedone a gravità piatta e HUD della base

**Produces:** `InteriorWalker.flat := false` (con `true` su è +Y); `WalkerHud.set_title(text)`,
`set_prompt(text: String)` (vuoto = nascosto; `set_board_prompt` resta), `set_place(text)`.

- [ ] `tests/test_interior_walker.gd` (toccato): `_test_flat_gravity` (su un pavimento piano a y = 0 il pedone
  resta in piedi e cammina lungo −Z).
- [ ] `tests/test_walker_hud.gd` se esiste, altrimenti dentro `test_interior_walker.gd`: `_test_prompt_and_place`.

### Task 3: La scena (`selene_interior.gd`)

**Produces:** `SeleneInterior.build()`; nodi `Rooms`, `Doors/Door_<i>` (`SlidingDoor`: `open_amount() -> float`,
aperta se un corpo nel gruppo `selene_people` è entro 2 m), `OfficeWall`, `Tube`; `spawn_transform() ->
Transform3D` (sala di sbarco, accanto alla piattaforma); `near_lift(point) -> bool`; `tube_ride(from_stop) ->
Transform3D`; `room_name(point) -> String`.

- [ ] `tests/test_selene_interior.gd`: `_test_walker_stops_at_a_wall`, `_test_door_opens_and_closes`,
  `_test_door_stays_open_while_someone_is_in_it`, `_test_office_wall_opens`, `_test_tube_goes_to_the_other_stop`,
  `_test_spawn_on_the_dock_floor`.

### Task 4: Equipaggio (`selene_crew.gd`)

**Produces:** `SeleneCrew.DEPARTMENTS` (nome → colore); `SeleneCrew.member_mesh() -> ArrayMesh` (mesh con
scheletro, UV.x parti: 0 tuta, 1 stivali, 2 pelle, 3 manica sinistra); `CrewMember` (Node3D con `Skeleton3D`,
`AnimationPlayer`) `walk_route(points)`, `sit()`, `work()`, `idle()`; nodo `Crew` in `SeleneInterior` con i 20.

- [ ] `tests/test_selene_crew.gd`: `_test_sleeve_is_the_left_arm`, `_test_department_colours`,
  `_test_walker_follows_route`, `_test_walker_stops_for_the_player`, `_test_walker_waits_then_goes_on`,
  `_test_seated_knees_bent`, `_test_twenty_in_the_base`.

### Task 5: GameMode e tasto B

**Produces:** azione `base` (B); `Mode.IN_BASE`; `GameMode.enter_base()`, `exit_base()`, `_can_enter_base() ->
bool`; `Cockpit.set_base_prompt(shown)`.

- [ ] `tests/test_game_mode.gd` (toccato): `_test_base_prompt_only_on_a_selene_pad`, `_test_b_enters_the_base`,
  `_test_k_by_the_lift_returns_to_the_eagle`, `_test_base_round_trip_keeps_the_ship_on_its_pad`,
  `_test_tube_ride_from_game_mode`.

### Task 6: Prova GPU, README e note

- [ ] Prova GPU (SubViewport propria, `frame_post_draw`): sala di sbarco, corridoio con la colonna, Main Mission
  con i seduti, infermeria; FPS.
- [ ] README (tasto B, interni di Selene); "Cambiato durante l'esecuzione" nella spec; commit.
