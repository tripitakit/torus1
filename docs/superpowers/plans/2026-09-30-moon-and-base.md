# Moon, Base Selene and Landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tidally locked moon (radius 250 km, 0.1 g) on a real circular orbit 20,000 km from the planet, with Base Selene (tower, module arms, tubes, six pads) and physical landings of the void-cruiser.

**Architecture:** `moon_orbit.gd` holds the pure math (rates, frames, velocity conversion, moon gravity). `moon.gd` (child of `PlanetSystem`) turns rigidly about the planet's axis at `ω_rel = ω_moon − ω_ring` and builds its mesh and material. The void-cruiser attaches to the moon below 30 km altitude: each tick it is carried by the moon's rotation, its `velocity` becomes relative to the moon, and its forces use `ω_moon`. The moon ground is analytic (a sphere); Base Selene (`moon_base.gd`) is an animatable body under the moon with box/prism colliders. Touching a level surface slowly lands, otherwise crashes. `landing_guide.gd` computes the target pad, gates and readout; the cockpit shows a moon panel.

**Tech Stack:** Godot 4.6.1 double precision, GDScript, gl_compatibility. Headless `extends SceneTree` tests; in-tree physics tests on a small scene (no station).

**Spec:** `docs/superpowers/specs/2026-09-30-moon-and-base-design.md`

## Global Constraints

- Binary `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` only. Helpers in the scratchpad: `rt.sh <tests...>`, `suite.sh` (`/tmp/claude-1000/-home-patrick-projects-playground-torus1/88be7e76-cf17-4eba-b962-d57871ddb62e/scratchpad/`). In a worktree session: single commands, edit scripts in files, no loops over variables, never `pkill -f` a pattern that appears in the same command line.
- RED is `FAIL`/`SCRIPT ERROR`/`Parse Error`; the user wants RED seen.
- Numbers from the spec: moon orbit radius `2.0e7`, radius `250000`, `GM 6.1e10`; attach below altitude 30 km, detach above 32 km; landing: vertical speed < 5 m/s, horizontal < 2 m/s, ship up within 25° of local vertical; ship half height 3.75 m; base 30° from the sub-planet point on the near side; six pads 60 × 60 m raised 2 m, pad number 1–6; tower hexagonal 60 m; four arms of five modules 20 × 40 × 10 m at 90 m spacing; tubes 6 m across; hangars 30 × 40 × 12 m; guide within 20 km of the base, gates at 50/100/200/400 m above the pad.
- Plan-level decisions (spec gaps, recorded in the spec's "Cambiato durante l'esecuzione" at the end): moon mesh 512 segments, ring spacing 20 m up to 2 km from the base growing ×1.08 to a 3 km cap (≈215k vertices; sag ≤ ~5 m far away); start angle −30° in the planet frame (60° ahead of the ship's start); moon ground has no physics body (analytic sphere).
- The planet node sits at `PlanetSystem`'s origin with identity rotation; the ring's axis is the planet's Y. `WorldOriginRebase` moves every child of the scene root except the ship: the moon, being under `PlanetSystem`, moves with it.
- Code/comments English, docs Italian; commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; add `.uid` files of new scripts/tests.

## Review Focus

1. **Velocity jumps at attach/detach** and ships oscillating across the 30 km boundary — `_test_attach_and_detach_keep_the_true_velocity` (Task 3).
2. **A landed ship drifting, sinking or sliding** over minutes while carried by the moon — `_test_landed_ship_stays_put_for_many_ticks` (Task 4).
3. **Origin shifts while near or on the moon** — the carry must use the planet centre after the shift — `_test_landed_ship_survives_an_origin_shift` (Task 4).
4. **Hitting a base wall at speed** must bounce, landing only on level surfaces — `_test_hitting_a_module_bounces` (Task 6).
5. **Crash restart** on the moon lands on pad 1, on the planet still restarts at a dock — Task 8 tests.

---

### Task 1: Moon orbit math

**Files:** Create `scripts/moon_orbit.gd`, `tests/test_moon_orbit.gd`.

**Interfaces (Produces):**
```gdscript
const ORBIT_RADIUS := 2.0e7
const RADIUS := 250000.0
const GM := 6.1e10
const ATTACH_ALTITUDE := 30000.0
const DETACH_ALTITUDE := 32000.0
const START_ANGLE := -PI / 6.0
static func moon_rate(planet_gm: float) -> float            # ω_moon
static func relative_rate(planet_gm: float, ring_radius: float) -> float  # ω_moon − ω_ring
static func centre_offset(angle: float) -> Vector3            # moon centre from planet centre, planet frame (axis Y)
static func moon_basis(angle: float) -> Basis                 # Basis(Vector3.UP, angle): moon-local −X faces the planet
static func spin(axis: Vector3, angle: float, pivot: Vector3) -> Transform3D  # rotation about `axis` through `pivot`
static func to_ring_velocity(moon_velocity: Vector3, offset_from_planet: Vector3, axis: Vector3, rel_rate: float) -> Vector3
static func to_moon_velocity(ring_velocity: Vector3, offset_from_planet: Vector3, axis: Vector3, rel_rate: float) -> Vector3
static func gravity(offset_from_moon: Vector3) -> Vector3     # uniform sphere inside RADIUS
```

- [ ] **Step 1: Test (RED)** `tests/test_moon_orbit.gd`:
  - `moon_rate(OrbitalFrame.MOON_GM)` ≈ 2.476e-5 (±0.5%), period ≈ 70.5 h; `relative_rate(MOON_GM, 6949600)` ≈ −9.61e-5 (±0.5%).
  - `centre_offset(a)` has length `ORBIT_RADIUS`, y = 0, equals `moon_basis(a) * Vector3(ORBIT_RADIUS, 0, 0)`; `moon_basis(a) * Vector3(-1, 0, 0)` points from the moon centre to the planet (tidal lock).
  - `spin(UP, a, pivot) * pivot == pivot`; spinning `centre_offset(a)` about the planet by `d` gives `centre_offset(a + d)`.
  - For random offset/velocity: `to_moon_velocity(to_ring_velocity(v)) == v`; a point fixed on the moon (moon velocity 0) at offset `r` has ring velocity `(axis × r) · rel_rate`.
  - `gravity(Vector3(RADIUS, 0, 0)).length()` ≈ 0.976 m/s² (0.1 g); inside, linear (half at `RADIUS/2`); points to the centre.
- [ ] **Step 2: Run** → Parse Error (missing script).
- [ ] **Step 3: Implement**

```gdscript
extends RefCounted

# The moon: a tidally locked body on a circular orbit about the planet, in
# the planet's orbital plane (axis = the planet's Y). Seen from the ring's
# turning frame it is a rigid body turning about the planet's axis at
# relative_rate(); its own frame turns at moon_rate().

const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

const ORBIT_RADIUS := 2.0e7
const RADIUS := 250000.0
# 0.1 g at the surface: 0.0995 * 9.80665 * RADIUS^2.
const GM := 6.1e10
# The ship flies in the moon's frame below ATTACH_ALTITUDE and leaves it
# above DETACH_ALTITUDE (no flicker across the boundary).
const ATTACH_ALTITUDE := 30000.0
const DETACH_ALTITUDE := 32000.0
# 60 degrees ahead of the ship's start along the ring's motion.
const START_ANGLE := -PI / 6.0

static func moon_rate(planet_gm: float) -> float:
	return OrbitalFrame.orbit_angular_velocity(planet_gm, ORBIT_RADIUS)

static func relative_rate(planet_gm: float, ring_radius: float) -> float:
	return moon_rate(planet_gm) - OrbitalFrame.orbit_angular_velocity(planet_gm, ring_radius)

static func moon_basis(angle: float) -> Basis:
	return Basis(Vector3.UP, angle)

static func centre_offset(angle: float) -> Vector3:
	return moon_basis(angle) * Vector3(ORBIT_RADIUS, 0.0, 0.0)

static func spin(axis: Vector3, angle: float, pivot: Vector3) -> Transform3D:
	var turn := Basis(axis.normalized(), angle)
	return Transform3D(turn, pivot - turn * pivot)

static func to_ring_velocity(moon_velocity: Vector3, offset_from_planet: Vector3, axis: Vector3, rel_rate: float) -> Vector3:
	return moon_velocity + (axis.normalized() * rel_rate).cross(offset_from_planet)

static func to_moon_velocity(ring_velocity: Vector3, offset_from_planet: Vector3, axis: Vector3, rel_rate: float) -> Vector3:
	return ring_velocity - (axis.normalized() * rel_rate).cross(offset_from_planet)

static func gravity(offset_from_moon: Vector3) -> Vector3:
	var reach := maxf(offset_from_moon.length(), RADIUS)
	return -offset_from_moon * (GM / (reach * reach * reach))
```
- [ ] **Step 4: Run** → pass. **Step 5: Commit** "Moon orbit math".

---

### Task 2: The moon node, its mesh, textures and scene wiring

**Files:** Create `tools/moon_textures.gd`, `assets/textures/moon/color.png`, `assets/textures/moon/normal.png`, `scripts/moon.gd`, `tests/test_moon.gd`; modify `scenes/torus1_system.tscn` (add `PlanetSystem/Moon`).

**Interfaces (Produces, `moon.gd`):** `@export planet_path := NodePath("../Planet")`, `@export planet_gm := OrbitalFrame.MOON_GM`, `@export ring_radius := 6949600.0`, `var angle := MoonOrbit.START_ANGLE`; `func relative_rate() -> float`; `func planet_centre() -> Vector3`; `func axis() -> Vector3` (planet Y, world); `func frame_omega() -> Vector3` (`axis() * moon_rate`); `func rel_omega() -> Vector3`; `func centre() -> Vector3` (= `global_position`); `func up_at(point: Vector3) -> Vector3`; `func altitude(point: Vector3) -> float`; `func base_transform() -> Transform3D` (world: origin on the surface at the base site, y = local up, x = moon-local +Z); `static func base_direction() -> Vector3` (moon-local: `Vector3(-cos(30°), sin(30°), 0)`); `func advance(delta: float)`; `func build()`; mesh node `Surface`.

- [ ] **Step 1: Textures.** `tools/moon_textures.gd` (`extends SceneTree`, run `<binary> --headless --path . -s tools/moon_textures.gd`): 2048 × 1024 equirectangular height field (u = longitude from `atan2(z, x)`, v = colatitude from +Y) of ~700 craters (radius 1–60 km, power-law, seeded RNG 1999), bowl `−depth·(1 − (d/r)²)` inside, raised rim `+0.25·depth·exp(−((d−r)/(0.25r))²)`, depth `0.2 r`; no crater centre within 8 km of the base direction; low-frequency `FastNoiseLite` maria darkening. Each crater touches only its bounding box of pixels (longitude span widened by `1/sin(colatitude)`, wrapping). Albedo = `0.42 ± noise − 0.08·maria + rim brightening`; normal map (tangent space: x east, y north) from the height gradient. Writes both PNGs. Commit the tool and the PNGs (the tool is not a test).
- [ ] **Step 2: Test (RED)** `tests/test_moon.gd` (a small scene: `PlanetSystem` Node3D with a `Planet` Node3D and the moon):
  - after `advance(10.0)`, `angle` grew by `10 × relative_rate()`; `global_position` is `ORBIT_RADIUS` from the planet, on its equatorial plane;
  - the base direction faces the planet within 31° (30° off the sub-planet point) at several angles;
  - `base_transform().origin` is `RADIUS` from the centre; its `basis.y` is the local up;
  - the surface mesh: every vertex at `RADIUS` (±0.01 m) from the moon centre; the first 20 rings around the base are ≤ 20.5 m apart; vertex count between 150k and 300k;
  - `altitude(centre + up × (RADIUS + 100))` ≈ 100.
- [ ] **Step 3: Run** → Parse Error.
- [ ] **Step 4: Implement `scripts/moon.gd`:**
  - `build()`: builds `Surface` (MeshInstance3D): an ArrayMesh in base-centred polar coordinates — pole at `base_direction()`, rings at arc distances `s_0 = 0, s_{k+1} = s_k + step`, `step = 20` while `s < 2000`, then `step ×= 1.08` up to 3000, until `s ≥ π·RADIUS`; 512 segments round each ring; closing vertex at the antipode. Winding: front faces outward (check with the normal test). Normals = vertex direction. Built with `PackedVector3Array`s and `add_surface_from_arrays` (no SurfaceTool: speed).
  - Material: `ShaderMaterial` with `MOON_SHADER`: `varying vec3 local_dir` (object-space normalized `VERTEX`); fragment: equirect `u = atan(z, x)/TAU + 0.5`, `v = acos(y)/PI`, sampled with `textureGrad` using the derivative of whichever of `u` / `fract(u + 0.5)` is smaller (no seam line); vertex sets `TANGENT = normalize(cross(vec3(0,1,0), NORMAL))`, `BINORMAL = cross(NORMAL, TANGENT)` so `NORMAL_MAP` works; a fine procedural detail `value noise(local position / 40 m)` × 0.1 on the albedo; `ROUGHNESS = 0.95`.
  - `_ready()`: `build()`, `_place()`. `_physics_process(delta)`: `advance(delta)` (not in the editor). `advance`: `angle += relative_rate() * delta; _place()`. `_place()`: `transform = planet.transform * Transform3D(MoonOrbit.moon_basis(angle), MoonOrbit.centre_offset(angle))`.
- [ ] **Step 5: Scene.** Add to `torus1_system.tscn` under `PlanetSystem`: `[node name="Moon" type="Node3D" parent="PlanetSystem"]` with `script = ExtResource(moon.gd)`.
- [ ] **Step 6: Run** `test_moon`, `test_scene_wiring`, `test_orbital_flight_in_tree` → pass; measure `build()` time (ledger). **Commit** "The moon: orbit, mesh and crater textures".

---

### Task 3: Flying in the moon's frame

**Files:** Modify `scripts/void_cruiser.gd`; Test `tests/test_moon_landing_physics.gd` (new, in-tree).

**Interfaces (Produces, `void_cruiser.gd`):** `@export var moon_path := NodePath("../PlanetSystem/Moon")`; `var has_moon`, `var in_moon_frame := false`, `var is_landed := false`, `var crashed_on_moon := false`; `func moon_node() -> Node3D`; `func ring_velocity() -> Vector3` (true velocity in the ring frame whatever the frame).

- [ ] **Step 1: Test (RED)** `tests/test_moon_landing_physics.gd`: a scene root `Node3D` holding `PlanetSystem` (at the real offset `(0, -4000, -6959600)`) with `Planet` (plain Node3D, `planet_radius` set via a tiny script or the cruiser's own default) and `Moon`, a `VoidCruiser`, and a `WorldOriginRebase` tracking it. Helpers place the ship at a moon-local point (`moon.to_global(dir * (RADIUS + h))`) with a ring-frame velocity. Tests:
  - `_test_attach_and_detach_keep_the_true_velocity`: ship at altitude 31 km, moving in with the moon's surface velocity plus 50 m/s downward: after it crosses 30 km, `in_moon_frame` is true and `ring_velocity()` changed by less than the gravity step; lifted back past 32 km, detached with the same continuity; staying between 30 and 32 km does not flip the frame.
  - `_test_carried_with_the_moon`: attached at 10 km altitude with zero moon-frame velocity and gravity off (brake engaged): after 120 ticks the ship's moon-local position is unchanged (≤ 0.01 m) while the moon moved ~3.7 km.
  - `_test_moon_gravity_pulls_down`: attached, free: after 60 ticks the moon-frame velocity points to the moon centre, ≈ 0.98 m/s² × 1 s.
- [ ] **Step 2: Run** → Parse/FAIL.
- [ ] **Step 3: Implement** in `void_cruiser.gd`:
  - `_sync_moon()` (called with `_sync_planet()`): moon node, `has_moon`.
  - At the start of `_fly(delta)` (before crash handling returns): `_follow_moon()` — if `in_moon_frame`, apply `MoonOrbit.spin(moon.axis(), moon.angle - _moon_angle_seen, moon.planet_centre())` to `global_transform` and rotate `velocity` by the same basis; always set `_moon_angle_seen = moon.angle`. Then `_update_moon_frame()`: distance to the centre vs `RADIUS + ATTACH/DETACH`; on change convert `velocity` with `to_moon_velocity` / `to_ring_velocity` (offset from the planet centre, `moon.axis()`, `moon.relative_rate()`).
  - `_external_acceleration()`: omega = `moon.frame_omega()` if `in_moon_frame` else `ring_omega()`; add `MoonOrbit.gravity(pos - moon.centre())` when `has_moon`.
  - `ring_velocity()`.
- [ ] **Step 4: Run** → pass; `test_void_cruiser`, `test_orbital_flight_in_tree`, `test_void_cruiser_physics` still pass. **Commit** "The void-cruiser flies in the moon's frame near it".

---

### Task 4: Moon ground: landing, crash, take-off

**Files:** Modify `scripts/void_cruiser.gd`; Test `tests/test_moon_landing_physics.gd`.

**Interfaces (Produces):** `const LANDING_VERTICAL_SPEED := 5.0`, `LANDING_HORIZONTAL_SPEED := 2.0`, `LANDING_TILT := deg_to_rad(25.0)`, `HALF_HEIGHT := 3.75`; `static func landing_ok(velocity: Vector3, up: Vector3, ship_up: Vector3) -> bool`; `func touch_down(up: Vector3) -> void` (lands or crashes); `func land_at(transform: Transform3D) -> void` (used by GameMode).

- [ ] **Step 1: Tests (RED):**
  - `_test_landing_ok_limits` (pure): 4.9 m/s down, 1.9 m/s across, 24° tilt → true; 5.1 down, 2.1 across or 26° → false; nose pointing anywhere horizontally → true.
  - `_test_soft_level_touch_lands`: 50 m up, 3 m/s down in the moon frame, level → within 20 s `is_landed`, ship centre at `RADIUS + HALF_HEIGHT` (±0.05 m), velocity zero, no `crashed` signal.
  - `_test_fast_touch_crashes`, `_test_sideways_touch_crashes`, `_test_tilted_touch_crashes` (30°): `crashed` emitted, `crashed_on_moon` true.
  - `_test_landed_ship_stays_put_for_many_ticks`: after landing, 600 ticks: moon-local position within 0.01 m.
  - `_test_landed_ship_survives_an_origin_shift`: landed, push the ship's global position past 5 km from the origin before the rebase runs (as in test_orbital_flight_in_tree): still landed, moon-local position within 0.05 m.
  - `_test_up_thrust_takes_off`: landed, `Input.action_press("move_up")` for 1 s → not landed, altitude > 10 m; release.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement:** in `_move(delta)`, when `in_moon_frame`: `sphere_entry` from the ship's position to the next against `moon.centre()`, radius `RADIUS + HALF_HEIGHT`; on entry move to the contact point and `touch_down(moon.up_at(point))`. `touch_down`: `landing_ok(velocity, up, global_basis.y)` → `is_landed = true`, velocity and angular velocity zero, position snapped to `RADIUS + HALF_HEIGHT`; else `crashed_on_moon = true` and `_crash_at(point)`. In `_fly`: if `is_landed`: clear inputs except the vertical thrust; if `thrust_input.y > 0` → `is_landed = false` and fly on; else keep velocity zero and return (carry still applied). `_external_acceleration()` returns zero while landed. `restart_after_crash()` also clears `crashed_on_moon` and `is_landed`. `land_at(t)`: `global_transform = t`, frame attach with zero velocity, `is_landed = true`, `_moon_angle_seen` synced.
- [ ] **Step 4: Run** → pass (plus the void-cruiser tests). **Commit** "Landing on the moon: level and slow lands, anything else crashes".

---

### Task 5: Moon HUD panel

**Files:** Create `scripts/landing_readout.gd`, `tests/test_landing_readout.gd`; modify `scripts/cockpit.gd`, `scripts/void_cruiser.gd`; Test `tests/test_cockpit.gd`.

**Interfaces:** `static func LandingReadout.readout(altitude: float, vertical: float, drift: float, tilt: float, pad: int, landed: bool) -> Dictionary` with keys `pad` ("PAD 3" or ""), `alt` ("ALT 123 m"), `vs` ("V/S -3.2 m/s"), `drift` ("DRIFT 1.1 m/s"), `level` ("LEVEL 12°"), `status` ("LANDED", "TOO FAST" when below 200 m and over a limit, else ""), `colors` {vs, drift, level} (green within limits, red over); `cockpit.update_moon(readout: Dictionary)` (panel `Hud/MoonPanel`, same place and style as `ApproachPanel`; hidden on an empty readout); the cruiser computes `altitude`, `vertical` (moon frame, positive up), `drift`, `tilt` and calls it each frame while `in_moon_frame` (pad 0 until Task 7), and hides the dock approach panel meanwhile.

- [ ] Steps: RED test for the formatter and colours (limits exactly at 5 / 2 / 25); RED cockpit test (panel exists, hidden by default, shows lines and colours); implement; run `test_landing_readout test_cockpit test_cockpit_in_tree`; **commit** "Moon HUD: altitude, vertical speed, drift, level".

---

### Task 6: Base Selene

**Files:** Create `scripts/moon_base.gd`, `tests/test_moon_base.gd`; modify `scripts/moon.gd` (build the base), `scripts/void_cruiser.gd` (collision: level contact lands, walls bounce); Test `tests/test_moon_landing_physics.gd`.

**Interfaces:** `static func MoonBase.layout() -> Array` of `{kind: "tower"|"module"|"tube"|"pad"|"hangar", name: String, centre: Vector2 (x east, z south, metres in the base's tangent plane), size: Vector3, yaw: float, number: int (pads)}`; `static func MoonBase.pad_centres() -> Array[Vector2]` (pads 1–6 in order); `func MoonBase.build(base_node: AnimatableBody3D, radius: float)` adds meshes and colliders; `moon.base_node()` (`Moon/Base`, an `AnimatableBody3D` with `sync_to_physics = false` at `base_transform()` in moon-local terms); `moon.pad_transform(number) -> Transform3D` (world: pad top centre, y up).

Layout (tangent plane, base centre at 0): tower hexagon radius 20 m, height 60 m at (0, 0); arms along ±x and ±z: modules at 90, 180, 270, 360, 450 m from the centre (long side along the arm), tubes between consecutive modules and from the tower to the first; pads at x = ±(560, 660, 760) m on the E/W arms' axis, numbered E 1–3 outward, W 4–6 outward; each pad's hangar 70 m off the arm's axis (+z), tube pad→hangar. Each piece placed on the sphere: base-local position `(x, sqrt(R² − x² − z²) − R + h/2, z)`, basis tilted by the local up.

Look: modules, hangars and the tower as one MultiMesh per `BuildingShapes` style (BLOCK for modules/hangars, RING_TOWER for the tower) with the building shader (`TerrainDressing.BUILDING_SHADER` material, colours from `TOWN_COLORS`' white/light grey, `building_custom` look: facade 0 bands, accent cool white); tubes `CylinderMesh` radius 3 (light grey `StandardMaterial3D`); pads `BoxMesh` 60 × 2 × 60 with `DockPadTexture.platform_material(60)`, four lamps (the station's `LAMP_SHADER`) at the corners, a `Label3D` number lying flat on the pad. Colliders: `BoxShape3D` per module/hangar/pad/tube piece, a convex prism (6 sides) for the tower.

- [ ] Steps:
  - RED `tests/test_moon_base.gd`: six pads numbered 1–6; every pair of pieces' footprints apart (tubes may touch the pieces they join); pads ≥ 100 m apart; everything within 1.3 km of the centre; `moon.pad_transform(n)` on the sphere at `RADIUS + 2` (pad top) with basis y = local up (±0.01).
  - RED physics in `test_moon_landing_physics.gd`: `_test_soft_landing_on_a_pad` (ship 30 m over pad 2, 3 m/s down → landed at pad top + HALF_HEIGHT), `_test_hitting_a_module_bounces` (20 m/s horizontal into a module → not landed, not crashed, velocity reversed along the wall normal).
  - Implement `moon_base.gd`, build it from `moon.build()`, and in `void_cruiser._move` (moon frame): `move_and_collide`; a collision whose normal is within `LANDING_TILT` of `moon.up_at(position)` → `touch_down(normal)`; otherwise bounce as now.
  - Run `test_moon_base test_moon test_moon_landing_physics`; **commit** "Base Selene: tower, module arms, tubes, pads and hangars".

---

### Task 7: Landing guide

**Files:** Create `scripts/landing_guide.gd`, `tests/test_landing_guide.gd`; modify `scripts/void_cruiser.gd`.

**Interfaces:** `const GUIDE_RANGE := 20000.0`, `const GATE_HEIGHTS := [50.0, 100.0, 200.0, 400.0]`, `const GATE_SIZE := 70.0`; `static func target_pad(ship: Vector3, pads: Array) -> int` (index of the nearest pad transform); `static func gate_segments(pad: Transform3D, ship: Vector3) -> PackedVector3Array` (four squares GATE_SIZE wide at GATE_HEIGHTS above the pad, level with it, plus a line from the ship to the top gate). The cruiser, in the moon frame within GUIDE_RANGE of the base, draws them in the existing `ApproachGuide` line node (dock gates hidden meanwhile) and passes the pad number, altitude above the pad top and the other values to `update_moon`.

- [ ] Steps: RED pure tests (nearest pad, squares level and centred above the pad at the right heights, line ends); RED in-tree check (guide line visible near the base, pad number in the panel); implement; run `test_landing_guide test_moon_landing_physics test_cockpit`; **commit** "Landing guide to the nearest pad".

---

### Task 8: Restart on pad 1 after a moon crash

**Files:** Modify `scripts/game_mode.gd`; Test `tests/test_game_mode.gd`.

- [ ] Steps: RED test `_test_moon_crash_restarts_landed_on_pad_1` (crash the ship on the moon, press R: `is_landed`, `in_moon_frame`, at `moon.pad_transform(1)` + HALF_HEIGHT up); the existing planet-crash test still restarts at a dock. Implement: `restart_after_crash()` → if `crashed_on_moon`: `cruiser.land_at(pad transform lifted by HALF_HEIGHT)` else `_place_by_port(...)`. Run `test_game_mode`; **commit** "After a moon crash, restart landed on pad 1".

---

### Task 9: Live check

- [ ] Full suite; headless game 900 frames clean.
- [ ] Real-GPU probe (as for the forests): camera near the moon and over the base; FPS, draw calls; xvfb render of the base.
- [ ] Update the spec's "Cambiato durante l'esecuzione" with the plan-level decisions and measured numbers; hand over to the user: fly to the moon (where it is at start, how to find it), land on a pad, take off.
