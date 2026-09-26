# Docking HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Help the pilot find and approach docks from outside: perspective square gates on the line from the ship to the nearest dock (within 10 km), a fixed-size blinking beacon on every pad visible to 50 km, and a HUD cross splitting the ship's velocity along its own axes.

**Architecture:** `approach_guide.gd` (pure) computes gate distances and the gates' line segments; the void-cruiser owns a top-level `ApproachGuide` line mesh it rebuilds every frame from the nearest dock port. `torus_station.gd` adds a `Beacon` billboard (fixed size, shared material, blink driven from the station's `_process`) to every bridge's dock. `velocity_cross.gd` is a `Control` drawing a cross (port/starboard, dorsal/ventral) plus a forward/aft bar with logarithmic bar lengths; the cockpit HUD hosts it and the void-cruiser feeds it every frame.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests; offscreen renders through `xvfb-run`.

**Spec:** `docs/superpowers/specs/2026-09-26-docking-hud-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`). If the script is gone, recreate it: loop over `tests/*.gd`, run each with `timeout 600`, grep for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function`; a missing preload or member prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone. Always use `timeout`.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` once before the first test run, and again after creating a new script/test (for its `.uid`).
- **Worktree shell rule:** in a worktree session, Bash commands with shell variables, loops or `bash -c` are refused. Use literal paths, one command per call; put multi-step edits in a Python file in the scratchpad and run it. When a Python edit script cuts a function out of a file, check afterwards that the comment above the next function and any `static` keyword survived.
- Off-tree nodes: no `global_*`; tests set `position` directly. In-tree tests use `_initialize()` + `await process_frame` / `physics_frame`.
- The scene: `VoidCruiser` is a sibling of `PlanetSystem`; the station is `PlanetSystem/TorusStation`; `WorldOriginRebase` shifts everything when the ship passes 5000 m from the origin (so placing the ship near any port triggers a shift).
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`, `size`; prefix unused parameters with `_`; no bare integer division.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add Godot-generated `.uid` files.
- Live check: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run; renders through `xvfb-run -a`.

## Review Focus

1. **Guide pointing at a stale position after an origin shift** — the guide is top-level and rebuilt in `_process`. Test: `_test_guide_shows_near_a_dock_on_the_line_to_its_port` (Task 4, in-tree; placing the ship near a port always triggers a shift).
2. **A degenerate square frame when the ship's up is parallel to the line** (flying straight up at the dock). Test: `_test_squares_stay_square_when_up_is_along_the_line` (Task 1).
3. **Beacon size on screen** — `fixed_size` scaling is only visible with a real renderer. Task 5 renders at 3 and 30 km and looks.
4. **2000 beacons blinking** — one shared material updated once per frame, never per node. Test: `_test_every_pad_has_a_fixed_size_beacon` checks the shared material (Task 2).
5. **The cross drawn off screen or eating mouse input** — anchored bottom-left, `mouse_filter` ignore. Test: `_test_hud_hosts_the_velocity_cross_bottom_left` (Task 3).

---

### Task 1: Approach gates

**Files:**
- Create: `scripts/approach_guide.gd`, `tests/test_approach_guide.gd`

**Interfaces:**
- Produces (`static` on `approach_guide.gd`): consts `MAX_RANGE := 10000.0`, `MAX_GATES := 20`, `SPACING := Vector2(50.0, 500.0)`, `FIRST_GATE := 100.0`, `GATE_SIZE := 30.0`; `gate_distances(distance: float) -> PackedFloat64Array`; `gate_segments(ship: Vector3, port: Vector3, up_hint: Vector3) -> PackedVector3Array` (pairs of points relative to `ship`, 8 per gate, corners in order round the square).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_approach_guide.gd`:

```gdscript
extends SceneTree

const ApproachGuide = preload("res://scripts/approach_guide.gd")

func _init():
	var failures := 0
	failures += _test_gate_distances_by_range()
	failures += _test_squares_are_30_m_across_the_line()
	failures += _test_squares_stay_square_when_up_is_along_the_line()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_gate_distances_by_range() -> int:
	var result := 0
	# [distance to the dock, gate count, first gate, spacing]
	for c in [[10000.0, 20, 100.0, 500.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [5000.0, 20, 100.0, 250.0]]:
		var gates: PackedFloat64Array = ApproachGuide.gate_distances(c[0])
		var ok: bool = gates.size() == c[1] and is_equal_approx(gates[0], c[2])
		if ok and gates.size() > 1:
			ok = is_equal_approx(gates[1] - gates[0], c[3]) and gates[gates.size() - 1] < c[0]
		if not ok:
			print("FAIL _test_gate_distances_by_range: at %.0f m got %s" % [c[0], gates])
			result = 1
	for far in [10001.0, 80.0, 100.0, 0.0]:
		if ApproachGuide.gate_distances(far).size() != 0:
			print("FAIL _test_gate_distances_by_range: gates at %.0f m, expected none" % far)
			result = 1
	return result

func _check_squares(test_name: String, ship: Vector3, port: Vector3, up_hint: Vector3) -> int:
	var segments: PackedVector3Array = ApproachGuide.gate_segments(ship, port, up_hint)
	var along := (port - ship).normalized()
	var gates := ApproachGuide.gate_distances(ship.distance_to(port))
	if segments.size() != gates.size() * 8 or segments.is_empty():
		print("FAIL %s: %d points for %d gates" % [test_name, segments.size(), gates.size()])
		return 1
	for g in range(gates.size()):
		var centre := Vector3.ZERO
		for k in range(8):
			centre += segments[g * 8 + k]
		centre /= 8.0
		if not centre.is_equal_approx(along * gates[g]):
			print("FAIL %s: gate %d centred at %s, expected %s" % [test_name, g, centre, along * gates[g]])
			return 1
		for k in range(0, 8, 2):
			var a := segments[g * 8 + k]
			var b := segments[g * 8 + k + 1]
			if absf(a.distance_to(b) - ApproachGuide.GATE_SIZE) > 1e-3 or absf((a - centre).dot(along)) > 1e-3:
				print("FAIL %s: gate %d side %s-%s is not 30 m across the line" % [test_name, g, a, b])
				return 1
	return 0

func _test_squares_are_30_m_across_the_line() -> int:
	return _check_squares("_test_squares_are_30_m_across_the_line", Vector3(10.0, -20.0, 30.0), Vector3(3000.0, 400.0, -2500.0), Vector3.UP)

func _test_squares_stay_square_when_up_is_along_the_line() -> int:
	# Flying straight up at the dock: the ship's up is the line itself.
	return _check_squares("_test_squares_stay_square_when_up_is_along_the_line", Vector3.ZERO, Vector3(0.0, 4000.0, 0.0), Vector3.UP)
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `Parse Error` (preload of `approach_guide.gd` fails).

- [ ] **Step 3: Implement**

Create `scripts/approach_guide.gd`:

```gdscript
extends RefCounted

# The docking approach guide: square gates on the straight line from the
# ship to the nearest dock's port, recomputed every frame. Far gates look
# small in perspective, so the row reads as a path into the dock.

const MAX_RANGE := 10000.0
const MAX_GATES := 20
# Metres between gates: distance / MAX_GATES, kept within these.
const SPACING := Vector2(50.0, 500.0)
const FIRST_GATE := 100.0
const GATE_SIZE := 30.0

# Distances from the ship of the gates toward a dock `distance` away: none
# past MAX_RANGE, none closer than FIRST_GATE, none at or past the dock.
static func gate_distances(distance: float) -> PackedFloat64Array:
	var gates := PackedFloat64Array()
	if distance > MAX_RANGE:
		return gates
	var spacing: float = clampf(distance / MAX_GATES, SPACING.x, SPACING.y)
	var d := FIRST_GATE
	while d < distance and gates.size() < MAX_GATES:
		gates.append(d)
		d += spacing
	return gates

# The gates' outlines as line segments (pairs of points, relative to the
# ship): GATE_SIZE squares facing along the line, their "up" from up_hint
# (the ship's own up) unless that runs along the line.
static func gate_segments(ship: Vector3, port: Vector3, up_hint: Vector3) -> PackedVector3Array:
	var segments := PackedVector3Array()
	var to_port := port - ship
	var distance := to_port.length()
	if distance <= 0.0:
		return segments
	var along := to_port / distance
	var right := along.cross(up_hint)
	if right.length() < 1e-6:
		right = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.BACK)
	right = right.normalized() * GATE_SIZE * 0.5
	var up := right.cross(along).normalized() * GATE_SIZE * 0.5
	for d in gate_distances(distance):
		var centre := along * d
		var corners := [centre - right - up, centre + right - up, centre + right + up, centre - right + up]
		for k in range(4):
			segments.append(corners[k])
			segments.append(corners[(k + 1) % 4])
	return segments
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only. Run `--import` for the `.uid` files.

- [ ] **Step 5: Commit**

```bash
git add scripts/approach_guide.gd scripts/approach_guide.gd.uid tests/test_approach_guide.gd tests/test_approach_guide.gd.uid
git commit -m "Add the approach gates: squares on the line from the ship to the dock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: A beacon on every pad

**Files:**
- Modify: `scripts/torus_station.gd` (constants, `_process`, `build_station`, `_add_dock`)
- Test: `tests/test_torus_station.gd`

**Interfaces:**
- Produces on `torus_station.gd`: consts `BEACON_COLOR`, `BEACON_LIFT_RATIO := 1.0 / 30.0`, `BEACON_SIZE := 0.02`, `BEACON_RANGE := 50000.0`, `BEACON_PERIOD := 1.5`, `BEACON_ON_TIME := 0.5`; `static func beacon_lit(time: float) -> bool`; node `Bridge<i>/Beacon` (`MeshInstance3D`, shared `QuadMesh` and material).

- [ ] **Step 1: Write the failing tests**

In `tests/test_torus_station.gd`, add after `failures += _test_bridge_radius_and_length_helpers()`:

```gdscript
	failures += _test_every_pad_has_a_fixed_size_beacon()
	failures += _test_beacon_blinks_half_a_second_in_one_and_a_half()
```

and append:

```gdscript
func _test_every_pad_has_a_fixed_size_beacon() -> int:
	# Small station: bridge radius 9, beacon 0.3 m above the pad centre.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var first: MeshInstance3D = null
	for i in range(4):
		var bridge: Node3D = station.get_node("Bridge%d" % i)
		var beacon := bridge.get_node_or_null("Beacon") as MeshInstance3D
		var pad: MeshInstance3D = bridge.get_node("DockPad")
		if beacon == null:
			print("FAIL _test_every_pad_has_a_fixed_size_beacon: Bridge%d has no Beacon" % i)
			result = 1
			continue
		if first == null:
			first = beacon
		var material := beacon.material_override as StandardMaterial3D
		var expected: Vector3 = pad.position + pad.transform.basis.y.normalized() * 9.0 * TorusStationScript.BEACON_LIFT_RATIO
		if beacon.mesh != first.mesh or material == null or material != first.material_override:
			print("FAIL _test_every_pad_has_a_fixed_size_beacon: Bridge%d beacon does not share the mesh and material" % i)
			result = 1
		elif not material.fixed_size or material.billboard_mode != BaseMaterial3D.BILLBOARD_ENABLED or material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			print("FAIL _test_every_pad_has_a_fixed_size_beacon: beacon material is not a fixed-size unshaded billboard")
			result = 1
		if not beacon.position.is_equal_approx(expected) or not is_equal_approx(beacon.visibility_range_end, TorusStationScript.BEACON_RANGE):
			print("FAIL _test_every_pad_has_a_fixed_size_beacon: Bridge%d beacon at %s (expected %s), drawn to %f m" % [i, beacon.position, expected, beacon.visibility_range_end])
			result = 1
	station.free()
	return result

func _test_beacon_blinks_half_a_second_in_one_and_a_half() -> int:
	var result := 0
	for c in [[0.0, true], [0.49, true], [0.5, false], [1.49, false], [1.5, true], [3.2, true], [3.6, false]]:
		if TorusStationScript.beacon_lit(c[0]) != c[1]:
			print("FAIL _test_beacon_blinks_half_a_second_in_one_and_a_half: at %.2f s lit %s, expected %s" % [c[0], TorusStationScript.beacon_lit(c[0]), c[1]])
			result = 1
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -4`
Expected: `Parse Error` naming `BEACON_LIFT_RATIO` / `beacon_lit`.

- [ ] **Step 3: Implement**

In `scripts/torus_station.gd`:
- add after `const PAD_VISIBLE_RATIO := 5.0`:

```gdscript
# A blinking green beacon above every pad, the same few pixels on screen at
# any distance (fixed size), so docks can be picked out from far away; the
# pad itself is only drawn up close. BEACON_SIZE in fixed-size units is
# about 13 px on a 1280 px wide, 90 degree view.
const BEACON_COLOR := Color(0.3, 1.0, 0.4)
const BEACON_LIFT_RATIO := 1.0 / 30.0
const BEACON_SIZE := 0.02
const BEACON_RANGE := 50000.0
const BEACON_PERIOD := 1.5
const BEACON_ON_TIME := 0.5

# One mesh and one material for every beacon: blinking them is one change
# per frame, not one per bridge.
var _beacon_mesh: QuadMesh
var _beacon_material: StandardMaterial3D
var _beacon_time := 0.0

static func beacon_lit(time: float) -> bool:
	return fmod(time, BEACON_PERIOD) < BEACON_ON_TIME
```

- replace `_process` with:

```gdscript
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_rotate_sections(delta)
	_beacon_time += delta
	if _beacon_material != null:
		_beacon_material.albedo_color = Color(BEACON_COLOR, 1.0 if beacon_lit(_beacon_time) else 0.0)
```

- in `build_station`, after the `pad_mesh.size = ...` line add:

```gdscript
	_beacon_mesh = QuadMesh.new()
	_beacon_mesh.size = Vector2.ONE * BEACON_SIZE
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon_material.fixed_size = true
	_beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_material.albedo_color = BEACON_COLOR
```

- at the end of `_add_dock` (after `bridge.add_child(port)`) add:

```gdscript
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = _beacon_mesh
	beacon.material_override = _beacon_material
	beacon.position = centre + normal * get_bridge_radius() * BEACON_LIFT_RATIO
	beacon.visibility_range_end = BEACON_RANGE
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bridge.add_child(beacon)
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only. Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/torus_station.gd tests/test_torus_station.gd
git commit -m "Put a blinking fixed-size beacon above every dock pad

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Velocity cross on the HUD

**Files:**
- Create: `scripts/velocity_cross.gd`, `tests/test_velocity_cross.gd`
- Modify: `scripts/cockpit.gd` (preload, `_build_hud`, new `update_velocity`)
- Test: `tests/test_cockpit.gd`

**Interfaces:**
- Produces on `velocity_cross.gd` (extends `Control`): consts `TOP_SPEED := 100000.0`, `MIN_SPEED := 0.5`, `PANEL_SIZE := Vector2(260.0, 200.0)`; vars `components: Vector3` (starboard, dorsal, forward), `cruise: bool`; `static func ship_components(ship_basis: Basis, velocity: Vector3) -> Vector3`; `static func bar_fraction(speed: float) -> float`; `func set_velocity(new_components: Vector3, cruise_locked: bool)`.
- Produces on `cockpit.gd`: node `Hud/VelocityCross`; `func update_velocity(components: Vector3, cruise: bool)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_velocity_cross.gd`:

```gdscript
extends SceneTree

const VelocityCross = preload("res://scripts/velocity_cross.gd")

func _init():
	var failures := 0
	failures += _test_components_along_the_ship_axes()
	failures += _test_bars_are_logarithmic()
	failures += _test_set_velocity_keeps_values()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_components_along_the_ship_axes() -> int:
	var result := 0
	# Not turned: starboard = +x, dorsal = +y, forward = -z.
	var still: Vector3 = VelocityCross.ship_components(Basis(), Vector3(3.0, -4.0, -5.0))
	if not still.is_equal_approx(Vector3(3.0, -4.0, 5.0)):
		print("FAIL _test_components_along_the_ship_axes: %s, expected (3, -4, 5)" % still)
		result = 1
	# Yawed 90 degrees left: the ship's forward is world -x.
	var yawed: Vector3 = VelocityCross.ship_components(Basis(Vector3.UP, PI / 2.0), Vector3(-10.0, 0.0, 0.0))
	if not yawed.is_equal_approx(Vector3(0.0, 0.0, 10.0)):
		print("FAIL _test_components_along_the_ship_axes: yawed %s, expected (0, 0, 10)" % yawed)
		result = 1
	return result

func _test_bars_are_logarithmic() -> int:
	var result := 0
	if VelocityCross.bar_fraction(0.4) != 0.0 or VelocityCross.bar_fraction(-0.4) != 0.0:
		print("FAIL _test_bars_are_logarithmic: bars under 0.5 m/s")
		result = 1
	if not is_equal_approx(VelocityCross.bar_fraction(100000.0), 1.0) or not is_equal_approx(VelocityCross.bar_fraction(250000.0), 1.0):
		print("FAIL _test_bars_are_logarithmic: not full at 100 km/s and beyond")
		result = 1
	var docking: float = VelocityCross.bar_fraction(20.0)
	var ramp: float = VelocityCross.bar_fraction(45000.0)
	if not is_equal_approx(docking, log(21.0) / log(100001.0)) or not is_equal_approx(VelocityCross.bar_fraction(-20.0), docking) or ramp <= docking or ramp >= 1.0:
		print("FAIL _test_bars_are_logarithmic: 20 m/s -> %f, 45 km/s -> %f" % [docking, ramp])
		result = 1
	return result

func _test_set_velocity_keeps_values() -> int:
	var cross: Control = VelocityCross.new()
	var result := 0
	cross.set_velocity(Vector3(1.0, 2.0, 3.0), true)
	if not cross.components.is_equal_approx(Vector3(1.0, 2.0, 3.0)) or not cross.cruise or cross.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("FAIL _test_set_velocity_keeps_values: %s cruise %s mouse %d" % [cross.components, cross.cruise, cross.mouse_filter])
		result = 1
	cross.free()
	return result
```

In `tests/test_cockpit.gd`, add after `failures += _test_cruise_line_shown_only_while_cruising()`:

```gdscript
	failures += _test_hud_hosts_the_velocity_cross_bottom_left()
```

and append:

```gdscript
func _test_hud_hosts_the_velocity_cross_bottom_left() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var cross := cockpit.get_node_or_null("Hud/VelocityCross") as Control
	if cross == null:
		print("FAIL _test_hud_hosts_the_velocity_cross_bottom_left: no Hud/VelocityCross")
		cockpit.free()
		return 1
	if not is_equal_approx(cross.anchor_left, 0.0) or not is_equal_approx(cross.anchor_top, 1.0) or cross.offset_bottom > 0.0 or cross.offset_left < 0.0:
		print("FAIL _test_hud_hosts_the_velocity_cross_bottom_left: anchors %f/%f offsets %f/%f" % [cross.anchor_left, cross.anchor_top, cross.offset_left, cross.offset_bottom])
		result = 1
	cockpit.update_velocity(Vector3(-5.0, 0.0, 120.0), true)
	if not cross.components.is_equal_approx(Vector3(-5.0, 0.0, 120.0)) or not cross.cruise:
		print("FAIL _test_hud_hosts_the_velocity_cross_bottom_left: update_velocity did not reach the cross")
		result = 1
	cockpit.free()
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_velocity_cross.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `Parse Error` (preload fails).
Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `FAIL _test_hud_hosts_the_velocity_cross_bottom_left: no Hud/VelocityCross`.

- [ ] **Step 3: Implement**

Create `scripts/velocity_cross.gd`:

```gdscript
extends Control

# The ship's velocity (relative to the ring, like SPEED) split along its own
# axes: a cross for port / starboard across and dorsal / ventral up and
# down, and a separate bar for forward / aft. Bar lengths are logarithmic
# from 1 m/s to 100 km/s, so docking speeds and full-ramp speeds both read.

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

const TOP_SPEED := 100000.0
const MIN_SPEED := 0.5
const PANEL_SIZE := Vector2(260.0, 200.0)
# Pixels from a bar's centre to its full length.
const ARM := 80.0
const CROSS_CENTRE := Vector2(100.0, 100.0)
const FORWARD_CENTRE := Vector2(225.0, 100.0)
const BAR_WIDTH := 4.0
const FONT_SIZE := 14
const BAR_COLOR := Color(0.4, 0.95, 1.0)
const AXIS_COLOR := Color(0.4, 0.95, 1.0, 0.3)
const CRUISE_COLOR := Color(1.0, 0.8, 0.3)

# (starboard, dorsal, forward) in m/s.
var components := Vector3.ZERO
var cruise := false

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Velocity along the ship's own axes: +x starboard, +y dorsal, -z forward.
static func ship_components(ship_basis: Basis, velocity: Vector3) -> Vector3:
	var local := ship_basis.inverse() * velocity
	return Vector3(local.x, local.y, -local.z)

# How far a bar reaches, 0..1: nothing under MIN_SPEED, full at TOP_SPEED.
static func bar_fraction(speed: float) -> float:
	var magnitude := absf(speed)
	if magnitude < MIN_SPEED:
		return 0.0
	return clampf(log(1.0 + magnitude) / log(1.0 + TOP_SPEED), 0.0, 1.0)

func set_velocity(new_components: Vector3, cruise_locked: bool) -> void:
	components = new_components
	cruise = cruise_locked
	queue_redraw()

func _draw() -> void:
	draw_line(CROSS_CENTRE + Vector2(-ARM, 0.0), CROSS_CENTRE + Vector2(ARM, 0.0), AXIS_COLOR, 1.0)
	draw_line(CROSS_CENTRE + Vector2(0.0, -ARM), CROSS_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	draw_line(FORWARD_CENTRE + Vector2(0.0, -ARM), FORWARD_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	_label(CROSS_CENTRE + Vector2(-ARM - 36.0, 5.0), "PORT", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(ARM + 4.0, 5.0), "STBD", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(-14.0, -ARM - 6.0), "DOR", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(-14.0, ARM + 16.0), "VEN", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, -ARM - 6.0), "FWD", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, ARM + 16.0), "AFT", AXIS_COLOR)
	_bar(CROSS_CENTRE, Vector2(signf(components.x), 0.0), components.x, BAR_COLOR)
	_bar(CROSS_CENTRE, Vector2(0.0, -signf(components.y)), components.y, BAR_COLOR)
	_bar(FORWARD_CENTRE, Vector2(0.0, -signf(components.z)), components.z, CRUISE_COLOR if cruise else BAR_COLOR)

func _bar(origin: Vector2, direction: Vector2, speed: float, color: Color) -> void:
	var reach := bar_fraction(speed)
	if reach <= 0.0:
		return
	var tip := origin + direction * ARM * reach
	draw_line(origin, tip, color, BAR_WIDTH)
	_label(tip + direction * 6.0 + Vector2(4.0, 4.0), CockpitHudFormat.format_speed(absf(speed)), color)

func _label(at: Vector2, text: String, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
```

In `scripts/cockpit.gd`:
- add below `const CockpitHudFormat = ...`:

```gdscript
const VelocityCrossScript = preload("res://scripts/velocity_cross.gd")
```

- add after `set_cruise`:

```gdscript
# Velocity along the ship's axes (starboard, dorsal, forward), in m/s.
func update_velocity(components: Vector3, cruise: bool) -> void:
	(get_node("Hud/VelocityCross") as Control).set_velocity(components, cruise)
```

- in `_build_hud`, before the final `update_hud(0.0, {})`, add:

```gdscript
	# Bottom-left corner, clear of the text panel at the top.
	var cross: Control = VelocityCrossScript.new()
	cross.name = "VelocityCross"
	cross.anchor_left = 0.0
	cross.anchor_right = 0.0
	cross.anchor_top = 1.0
	cross.anchor_bottom = 1.0
	cross.offset_left = HUD_MARGIN
	cross.offset_right = HUD_MARGIN + VelocityCrossScript.PANEL_SIZE.x
	cross.offset_top = -HUD_MARGIN - VelocityCrossScript.PANEL_SIZE.y
	cross.offset_bottom = -HUD_MARGIN
	hud.add_child(cross)
```

- [ ] **Step 4: Run to verify it passes**

Run the two Step 2 commands. Expected: `ALL TESTS PASSED` only, for each. Run `--import` for the `.uid` files. Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/velocity_cross.gd scripts/velocity_cross.gd.uid scripts/cockpit.gd tests/test_velocity_cross.gd tests/test_velocity_cross.gd.uid tests/test_cockpit.gd
git commit -m "Add a HUD cross showing the velocity along the ship's axes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The void-cruiser draws the guide and feeds the cross

**Files:**
- Modify: `scripts/void_cruiser.gd`
- Test: `tests/test_void_cruiser.gd`; create `tests/test_docking_hud_in_tree.gd`

**Interfaces:**
- Consumes: Task 1 `ApproachGuide.gate_segments`; Task 3 `VelocityCross.ship_components`, `cockpit.update_velocity`; station `nearest_bridge_index`, `get_docking_port`.
- Produces on `void_cruiser.gd`: `@export var station_path := NodePath("../PlanetSystem/TorusStation")`; const `APPROACH_COLOR`; `func build_approach_guide()` (node `ApproachGuide`, top-level `MeshInstance3D`, `ArrayMesh` of `PRIMITIVE_LINES`); `_update_approach_guide()` and the cross feed in `_process`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser.gd`, add after `failures += _test_void_cruiser_flies_with_the_shared_flying_craft()`:

```gdscript
	failures += _test_approach_guide_hidden_without_a_station()
	failures += _test_process_feeds_the_velocity_cross()
```

and append:

```gdscript
func _test_approach_guide_hidden_without_a_station() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_approach_guide()
	cruiser._process(0.016)
	var guide := cruiser.get_node_or_null("ApproachGuide") as MeshInstance3D
	var result := 0
	if guide == null or not guide.top_level or guide.visible or not (guide.mesh is ArrayMesh):
		print("FAIL _test_approach_guide_hidden_without_a_station: guide missing, not top-level, not a mesh, or shown with no station")
		result = 1
	cruiser.free()
	return result

func _test_process_feeds_the_velocity_cross() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser.velocity = Vector3(2.0, 0.0, -50.0)
	cruiser._process(0.016)
	var cross = cruiser.get_node("Cockpit/Hud/VelocityCross")
	var result := 0
	if not cross.components.is_equal_approx(Vector3(2.0, 0.0, 50.0)):
		print("FAIL _test_process_feeds_the_velocity_cross: cross got %s, expected (2, 0, 50)" % cross.components)
		result = 1
	cruiser.free()
	return result
```

Create `tests/test_docking_hud_in_tree.gd`:

```gdscript
extends SceneTree

# The approach guide on the real scene (station, ports, origin shift).

const ApproachGuide = preload("res://scripts/approach_guide.gd")

var _failures := 0
var _scene: Node3D
var _cruiser: CharacterBody3D
var _station: Node3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_cruiser = _scene.get_node("VoidCruiser")
	_station = _scene.get_node("PlanetSystem/TorusStation")
	_cruiser.set_physics_process(false)
	_station.set_process(false)

	_failures += await _test_guide_shows_near_a_dock_on_the_line_to_its_port()
	_failures += await _test_guide_hides_far_from_every_dock()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis. Being far
# from the origin, this always makes the world shift on the next tick.
func _park(distance: float) -> void:
	var port: Node3D = _station.get_docking_port(0)
	_cruiser.global_position = port.global_position + port.global_transform.basis.x.normalized() * distance
	_cruiser.velocity = Vector3.ZERO
	for i in range(3):
		await physics_frame
		await process_frame

func _test_guide_shows_near_a_dock_on_the_line_to_its_port() -> int:
	await _park(5000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	var result := 0
	if not guide.visible or not guide.global_position.is_equal_approx(_cruiser.global_position):
		print("FAIL _test_guide_shows_near_a_dock_on_the_line_to_its_port: visible %s, at %s (ship at %s)" % [guide.visible, guide.global_position, _cruiser.global_position])
		return 1
	var points: PackedVector3Array = (guide.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var port: Vector3 = _station.get_docking_port(0).global_position
	var gates := ApproachGuide.gate_distances(_cruiser.global_position.distance_to(port))
	if points.size() != gates.size() * 8 or gates.is_empty():
		print("FAIL _test_guide_shows_near_a_dock_on_the_line_to_its_port: %d points for %d gates" % [points.size(), gates.size()])
		return 1
	var centre := Vector3.ZERO
	for k in range(8):
		centre += points[k]
	centre = guide.global_position + centre / 8.0
	var expected: Vector3 = _cruiser.global_position + (port - _cruiser.global_position).normalized() * gates[0]
	if centre.distance_to(expected) > 1.0:
		print("FAIL _test_guide_shows_near_a_dock_on_the_line_to_its_port: first gate at %s, expected %s" % [centre, expected])
		result = 1
	return result

func _test_guide_hides_far_from_every_dock() -> int:
	await _park(15000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if guide.visible:
		print("FAIL _test_guide_hides_far_from_every_dock: shown 15 km from the nearest dock")
		return 1
	return 0
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -4`
Expected: `SCRIPT ERROR` naming `build_approach_guide` and `FAIL _test_process_feeds_the_velocity_cross`.
Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED|ERROR" | head -4`
Expected: `Node not found: "ApproachGuide"` errors.

- [ ] **Step 3: Implement**

In `scripts/void_cruiser.gd`:
- add below `const OrbitalFrame = ...`:

```gdscript
const ApproachGuide = preload("res://scripts/approach_guide.gd")
const VelocityCross = preload("res://scripts/velocity_cross.gd")
```

- add after `@export var ring_radius: float = 6949600.0`:

```gdscript
# The station whose nearest dock the approach guide points at.
@export var station_path: NodePath = NodePath("../PlanetSystem/TorusStation")
const APPROACH_COLOR := Color(0.3, 1.0, 0.4, 0.7)
```

- in `_ready`, add `build_approach_guide()` after `build_cockpit()`;
- in `_process`, add after `cockpit.set_cruise(cruise_locked)`:

```gdscript
		cockpit.update_velocity(VelocityCross.ship_components(_world_basis(), velocity), cruise_locked)
```

  and as the last line of `_process`:

```gdscript
	_update_approach_guide()
```

- add after `build_cockpit`:

```gdscript
# Square gates on the line to the nearest dock (see approach_guide.gd). Not
# moved by the ship (top_level): _update_approach_guide places and redraws
# it every frame.
func build_approach_guide() -> void:
	var guide := MeshInstance3D.new()
	guide.name = "ApproachGuide"
	guide.top_level = true
	guide.mesh = ArrayMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = APPROACH_COLOR
	guide.material_override = material
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	guide.visible = false
	add_child(guide)

func _update_approach_guide() -> void:
	var guide := get_node_or_null("ApproachGuide") as MeshInstance3D
	if guide == null:
		return
	var segments := PackedVector3Array()
	var station: Node3D = null
	if is_inside_tree():
		station = get_node_or_null(station_path) as Node3D
	if station != null and station.is_inside_tree():
		var port: Node3D = station.get_docking_port(station.nearest_bridge_index(global_position))
		segments = ApproachGuide.gate_segments(global_position, port.global_position, global_transform.basis.y)
	guide.visible = not segments.is_empty()
	if segments.is_empty():
		return
	guide.global_transform = Transform3D(Basis(), global_position)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = segments
	var mesh := guide.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

func _world_basis() -> Basis:
	return global_transform.basis if is_inside_tree() else transform.basis
```

- [ ] **Step 4: Run to verify it passes**

Run the two Step 2 commands. Expected: `ALL TESTS PASSED` only, for each. Run `--import` for the new test's `.uid`. Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd tests/test_docking_hud_in_tree.gd tests/test_docking_hud_in_tree.gd.uid
git commit -m "Draw the approach gates to the nearest dock and feed the velocity cross

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Verification

**Files:**
- Create (scratchpad only): `/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_docking_hud.gd`

- [ ] **Step 1: Live check**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"`
Expected: no output.

- [ ] **Step 2: Offscreen renders**

Create the scratchpad script:

```gdscript
extends SceneTree

# The pilot's view toward dock 0 from 3 km (gates, beacon, pad) and 30 km
# (beacon only), with some sideways drift so the cross shows bars.
const SCRATCH := "/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/"

func _initialize():
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	var station: Node3D = scene.get_node("PlanetSystem/TorusStation")
	var cruiser: CharacterBody3D = scene.get_node("VoidCruiser")
	cruiser.set_physics_process(false)
	for view in [["dock_3km", 3000.0], ["dock_30km", 30000.0]]:
		var port: Node3D = station.get_docking_port(0)
		var out: Vector3 = port.global_transform.basis.x.normalized()
		var along: Vector3 = port.global_transform.basis.y.normalized()
		var eye: Vector3 = port.global_position + out * view[1] * 0.8 + along * view[1] * 0.6
		cruiser.global_transform = Transform3D(Basis.looking_at(port.global_position - eye, out), eye)
		cruiser.velocity = cruiser.global_transform.basis * Vector3(12.0, -3.0, -250.0)
		for i in range(8):
			await process_frame
		root.get_texture().get_image().save_png(SCRATCH + "%s.png" % view[0])
		print("saved ", view[0])
	quit()
```

Run: `timeout 300 xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . --script /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_docking_hud.gd 2>&1 | grep -iE "saved|error" | grep -v XSetIOErrorExitHandler`
Expected: `saved dock_3km`, `saved dock_30km`, no errors.

- [ ] **Step 3: Look at the renders**

Open both PNGs with the Read tool. Expected:
- 3 km: a row of green squares shrinking toward the dock, the pad on the bridge, the beacon above it (if the blink caught it lit), the velocity cross bottom-left with a starboard bar, a ventral bar and a long forward bar.
- 30 km: the beacon as a small green square (a dozen pixels) on the bridge; no gates (past 10 km); no pad.

If the beacon is not a dozen pixels (fixed-size scale differs from the estimate), adjust `BEACON_SIZE` and ledger it as a ruling with the measured pixel size. Other visual-only issues go to the final message as observations.

- [ ] **Step 4: Full suite**

Run the full suite. Expected: every file `ALL TESTS PASSED`.
