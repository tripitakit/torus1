# Curved Docking Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the docking guide a smooth path that leaves along the ship's nose, never crosses the station and meets the pad square on; show it from 100 m to 20 km; add a motion marker, cyan inside the first gate and red outside.

**Architecture:** `approach_guide.gd` (pure) builds the path in the frame of the pad's bridge, in round coordinates (distance from the axis, angle around it, height along it): one Hermite curve from the ship to the pad, or, when that would dip into a section, a curve to a point above the nearer section's rim plus a quarter ellipse down to the pad; samples still inside the station are lifted away from the axis, with the lift sloped and averaged. `void_cruiser.gd` converts to and from the bridge frame, applies the range and draws two top-level line meshes: `ApproachGuide` (gates) and `HeadingMarker` (motion marker).

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests; offscreen renders through `xvfb-run`.

**Spec:** `docs/superpowers/specs/2026-09-27-curved-docking-guide-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` (the `godot` on PATH is single precision: the pilot camera renders black and logs `prepare_camera` errors). One test file: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`). If the script is gone, recreate it: loop over `tests/*.gd`, run each with `timeout 600` and the binary above, grep for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** parse errors go to stderr (`SCRIPT ERROR: Parse Error: ...`); run with `2>&1`. RED is those lines or `FAIL` lines, never the summary alone.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` once before the first test run.
- **Worktree shell rule:** in a worktree session, Bash commands with shell variables, loops or `bash -c` are refused. Use literal paths, one command per call; put multi-step edits in a Python file in the scratchpad and run it. After a Python edit that cuts code, check that the comment above the next function and any `static` keyword survived.
- Numbers (from the spec): range 100 m – 20 km (straight line, ship to pad); up to 40 gates, spacing length/40 within 50–500 m, first at 100 m, 30 m squares; sections kept 300 m off (radius and rim), bridge 100 m off, pad window 0.05 rad; marker 20 m, hidden under 1 m/s, cyan `(0.3, 0.85, 1, 0.9)` when within 5 m of the first gate's centre along both sides of the gate, red `(1, 0.25, 0.2, 0.9)` otherwise.
- The code in this plan was run before writing it: every RED and GREEN below is the output it gave.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`, `size` (parameters named `size` inside static helpers are fine); prefix unused parameters with `_`.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`.
- Live check: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run; renders through `xvfb-run -a`.

## Review Focus

1. **The path at station positions the tests do not list** (e.g. just outside the gap at the pad's height, or the ship almost on the axis far out along the ring): it must stay outside the sections and the bridge. The pure tests sample 12 ships; the reviewer should try others against `_in_station` in `tests/test_approach_guide.gd`.
2. **Frame-to-frame jumps**: the two-piece path switches on when the single curve would dip into a section; near that switch the path can change shape between frames. Judge in the Task 3 render and say whether it needs hysteresis.
3. **Cost per frame**: about 0.6–0.9 ms in the headless debug build (160 samples, three running means). It runs every frame the guide shows.
4. **Nose into the station, or ship inside a margin**: the path turns at once; tests check only that it stays out and ends right (`_awkward_ships`).
5. **Marker reference**: the marker uses velocity relative to the port (`get_docking_port_velocity`), not the ring-relative velocity the HUD's SPEED shows. Near the dock the two differ by up to about 35 m/s.

---

### Task 1: The curved path from the nose

**Files:**
- Modify: `scripts/approach_guide.gd` (whole file below)
- Modify: `scripts/void_cruiser.gd` (`_approach_path`)
- Test: `tests/test_approach_guide.gd` (whole file below), `tests/test_docking_hud_in_tree.gd` (whole file below)

**Interfaces:**
- Produces: `ApproachGuide.approach_path(ship: Vector3, forward: Vector3, pad: Vector3, section_radius: float, half_gap: float, bridge_radius: float) -> PackedVector3Array` (bridge frame, first point = ship, last = pad); constants `SECTION_MARGIN`, `BRIDGE_MARGIN`, `PAD_WINDOW`, `PATH_SAMPLES`, `SHOULDER_SAMPLES`, `RAMP_SLOPE`, `SMOOTH_REACH`, `SMOOTH_PASSES`, `QUARTER`. `ENTRY_MARGIN` and `CURVE_SAMPLES` are gone. `gate_distances`, `gates_along`, `MAX_RANGE` (10000), `MAX_GATES` (20) unchanged.
- Consumes: `station.section_radius`, `station.get_bridge_length()`, `station.get_bridge_radius()`, `port.transform.origin` (pad centre in the bridge frame).

- [ ] **Step 1: Write the failing tests**

Replace `tests/test_approach_guide.gd` with:

```gdscript
extends SceneTree

const ApproachGuide = preload("res://scripts/approach_guide.gd")

# A bridge like the real one, in its own frame (axis = Y): sections of
# 2000 m radius begin 917 m either side of the pad; the bridge is a 64-sided
# prism of 600 m radius and the pad lies on its face 15.
const SECTION_RADIUS := 2000.0
const HALF_GAP := 917.0
const BRIDGE_RADIUS := 600.0
var PAD_ANGLE := 15.5 * TAU / 64.0
var PAD_RADIUS := BRIDGE_RADIUS * cos(PI / 64.0) + 0.3

func _init():
	var failures := 0
	failures += _test_gate_distances_by_length()
	failures += _test_squares_are_30_m_across_the_line()
	failures += _test_squares_stay_square_when_up_is_along_the_line()
	failures += _test_squares_follow_a_bent_path()
	failures += _test_path_runs_from_the_ship_to_the_pad()
	failures += _test_path_leaves_along_the_nose()
	failures += _test_path_meets_the_pad_square_on()
	failures += _test_path_never_enters_the_station()
	failures += _test_path_has_no_sharp_bends()
	failures += _test_path_is_straight_when_lined_up()
	failures += _test_path_curves_down_into_the_gap()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_gate_distances_by_length() -> int:
	var result := 0
	# [path length, gate count, first gate, spacing]. The 10 km range is the
	# ship's business: a path longer than that still gets its first gates.
	for c in [[10000.0, 20, 100.0, 500.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [5000.0, 20, 100.0, 250.0], [15000.0, 20, 100.0, 500.0]]:
		var gates: PackedFloat64Array = ApproachGuide.gate_distances(c[0])
		var ok: bool = gates.size() == c[1] and is_equal_approx(gates[0], c[2])
		if ok and gates.size() > 1:
			ok = is_equal_approx(gates[1] - gates[0], c[3]) and gates[gates.size() - 1] < c[0]
		if not ok:
			print("FAIL _test_gate_distances_by_length: at %.0f m got %s" % [c[0], gates])
			result = 1
	for short in [80.0, 100.0, 0.0]:
		if ApproachGuide.gate_distances(short).size() != 0:
			print("FAIL _test_gate_distances_by_length: gates at %.0f m, expected none" % short)
			result = 1
	return result

func _check_squares(test_name: String, ship: Vector3, port: Vector3, up_hint: Vector3) -> int:
	var path := PackedVector3Array([ship, port])
	var segments: PackedVector3Array = ApproachGuide.gates_along(path, up_hint)
	var along := (port - ship).normalized()
	var gates := ApproachGuide.gate_distances(ship.distance_to(port))
	if segments.size() != gates.size() * 8 or segments.is_empty():
		print("FAIL %s: %d points for %d gates" % [test_name, segments.size(), gates.size()])
		return 1
	for g in range(gates.size()):
		var centre := _square_centre(segments, g)
		if not centre.is_equal_approx(ship + along * gates[g]):
			print("FAIL %s: gate %d centred at %s, expected %s" % [test_name, g, centre, ship + along * gates[g]])
			return 1
		if not _is_square_across(segments, g, along, ApproachGuide.GATE_SIZE):
			print("FAIL %s: gate %d is not a 30 m square across the line" % [test_name, g])
			return 1
	return 0

func _square_centre(segments: PackedVector3Array, g: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += segments[g * 8 + k]
	return centre / 8.0

func _is_square_across(segments: PackedVector3Array, g: int, along: Vector3, size: float) -> bool:
	var centre := _square_centre(segments, g)
	for k in range(0, 8, 2):
		var a := segments[g * 8 + k]
		var b := segments[g * 8 + k + 1]
		if absf(a.distance_to(b) - size) > 1e-3 or absf((a - centre).dot(along)) > 1e-3:
			return false
	return true

func _test_squares_are_30_m_across_the_line() -> int:
	return _check_squares("_test_squares_are_30_m_across_the_line", Vector3(10.0, -20.0, 30.0), Vector3(3000.0, 400.0, -2500.0), Vector3.UP)

func _test_squares_stay_square_when_up_is_along_the_line() -> int:
	# Flying straight up at the dock: the ship's up is the line itself.
	return _check_squares("_test_squares_stay_square_when_up_is_along_the_line", Vector3.ZERO, Vector3(0.0, 4000.0, 0.0), Vector3.UP)

func _test_squares_follow_a_bent_path() -> int:
	# 1000 m east, then 1000 m north: gates measured along the bend, each
	# facing along its own leg.
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1000.0, 0.0, 0.0), Vector3(1000.0, 0.0, -1000.0)])
	var segments: PackedVector3Array = ApproachGuide.gates_along(path, Vector3.UP)
	var gates := ApproachGuide.gate_distances(2000.0)
	if segments.size() != gates.size() * 8:
		print("FAIL _test_squares_follow_a_bent_path: %d points for %d gates" % [segments.size(), gates.size()])
		return 1
	for g in range(gates.size()):
		var d: float = gates[g]
		var expected := Vector3(d, 0.0, 0.0) if d <= 1000.0 else Vector3(1000.0, 0.0, 1000.0 - d)
		var along := Vector3.RIGHT if d <= 1000.0 else Vector3.FORWARD
		if not _square_centre(segments, g).is_equal_approx(expected) or not _is_square_across(segments, g, along, ApproachGuide.GATE_SIZE):
			print("FAIL _test_squares_follow_a_bent_path: gate %d at %s, expected %s across %s" % [g, _square_centre(segments, g), expected, along])
			return 1
	return 0

func _pad() -> Vector3:
	return Vector3(sin(PAD_ANGLE), 0.0, cos(PAD_ANGLE)) * PAD_RADIUS

func _at(radius: float, turn: float, y: float) -> Vector3:
	return Vector3(sin(PAD_ANGLE + turn) * radius, y, cos(PAD_ANGLE + turn) * radius)

func _toward_pad(ship: Vector3) -> Vector3:
	return (_pad() - ship).normalized()

func _path(c: Array) -> PackedVector3Array:
	return ApproachGuide.approach_path(c[1], c[2], _pad(), SECTION_RADIUS, HALF_GAP, BRIDGE_RADIUS)

# Ships well clear of the station, nose free: [name, ship, nose].
func _clear_ships() -> Array:
	var cases := []
	for c in [["in front, nose at the pad", _at(5000.0, 0.0, 0.0)], ["along the ring, behind a section", _at(2500.0, 0.0, 6000.0)],
			["other side of the bridge", _at(3000.0, PI, 0.0)], ["20 km out", _at(19000.0, -1.0, -6000.0)],
			["planet side", _at(12000.0, PI, 3000.0)], ["in the gap, other side", _at(1000.0, 2.5, 200.0)],
			["far along the axis", _at(3000.0, 0.2, 10500.0)], ["close in front", _at(1000.0, 0.0, 0.0)]]:
		cases.append([c[0], c[1], _toward_pad(c[1])])
	var back := _at(8000.0, 0.5, 2000.0)
	cases.append(["nose turned back", back, -_toward_pad(back)])
	return cases

# Ships whose nose points into the station, or that are already inside a
# margin: the path turns at once, but must still keep off the station.
func _awkward_ships() -> Array:
	var into := _at(2400.0, 0.3, 3000.0)
	var skim := _at(2050.0, 1.0, 4000.0)
	return [
		["nose into a section", into, -Vector3(into.x, 0.0, into.z).normalized()],
		["skimming a section", skim, _toward_pad(skim)],
		["nose at a section's end", _at(1500.0, 0.8, 800.0), Vector3.UP],
	]

func _test_path_runs_from_the_ship_to_the_pad() -> int:
	for c in _clear_ships() + _awkward_ships():
		var path := _path(c)
		if path.size() < 3 or not path[0].is_equal_approx(c[1]) or not path[path.size() - 1].is_equal_approx(_pad()):
			print("FAIL _test_path_runs_from_the_ship_to_the_pad (%s): %d points" % [c[0], path.size()])
			return 1
	return 0

func _test_path_leaves_along_the_nose() -> int:
	# The first gates sit in the middle of the pilot's view.
	for c in _clear_ships():
		var path := _path(c)
		var leaving := (path[1] - path[0]).normalized()
		if leaving.dot(c[2]) < 0.99:
			print("FAIL _test_path_leaves_along_the_nose (%s): leaves along %s, nose %s" % [c[0], leaving, c[2]])
			return 1
	return 0

func _test_path_meets_the_pad_square_on() -> int:
	var inward := -_pad().normalized()
	for c in _clear_ships() + _awkward_ships():
		var path := _path(c)
		var arriving := (path[path.size() - 1] - path[path.size() - 2]).normalized()
		if arriving.dot(inward) < 0.99:
			print("FAIL _test_path_meets_the_pad_square_on (%s): arrives along %s" % [c[0], arriving])
			return 1
	return 0

# Inside a section, or inside the bridge's prism (its faces are
# cos(pi/64) of the radius from the axis).
func _in_station(p: Vector3) -> bool:
	var r := Vector2(p.x, p.z).length()
	if absf(p.y) > HALF_GAP:
		return r < SECTION_RADIUS
	return r < BRIDGE_RADIUS * cos(PI / 64.0) - 0.5

func _test_path_never_enters_the_station() -> int:
	for c in _clear_ships() + _awkward_ships():
		var path := _path(c)
		for i in range(1, path.size()):
			for k in range(21):
				var p: Vector3 = path[i - 1].lerp(path[i], k / 20.0)
				if _in_station(p):
					print("FAIL _test_path_never_enters_the_station (%s): %s is inside" % [c[0], p])
					return 1
	return 0

func _test_path_has_no_sharp_bends() -> int:
	for c in _clear_ships():
		var path := _path(c)
		for i in range(2, path.size()):
			var bend := rad_to_deg((path[i - 1] - path[i - 2]).angle_to(path[i] - path[i - 1]))
			if bend > 15.0:
				print("FAIL _test_path_has_no_sharp_bends (%s): %.1f degrees at point %d" % [c[0], bend, i - 1])
				return 1
	return 0

func _test_path_is_straight_when_lined_up() -> int:
	# Straight out in front of the pad, nose on it: nothing to go round.
	var c: Array = _clear_ships()[0]
	var path := _path(c)
	var line: Vector3 = _toward_pad(c[1])
	for p in path:
		var off: Vector3 = (p - c[1]) - line * (p - c[1]).dot(line)
		if off.length() > 1.0:
			print("FAIL _test_path_is_straight_when_lined_up: %s is %.1f m off the line" % [p, off.length()])
			return 1
	return 0

func _test_path_curves_down_into_the_gap() -> int:
	# Behind a section there is no long straight run down to the pad: a
	# kilometre out along the path it is still turning toward the normal.
	var path := _path(_clear_ships()[1])
	var inward := -_pad().normalized()
	var walked := 0.0
	var i := path.size() - 1
	while i > 1 and walked < 1000.0:
		walked += path[i].distance_to(path[i - 1])
		i -= 1
	var there := (path[i + 1] - path[i]).normalized()
	if there.dot(inward) > cos(deg_to_rad(10.0)):
		print("FAIL _test_path_curves_down_into_the_gap: straight along the normal for the last kilometre")
		return 1
	return 0
```

Replace `tests/test_docking_hud_in_tree.gd` with:

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

	_failures += await _test_guide_leaves_along_the_nose()
	_failures += await _test_guide_hides_far_from_every_dock()
	_failures += await _test_guide_curves_around_a_section()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis and
# `along` metres along the bridge's axis, nose on a point `aside` metres
# across the bridge from the port, at rest with the port. Being far from
# the origin, this always makes the world shift on the next tick.
func _park(distance: float, along: float = 0.0, aside: float = 0.0) -> void:
	var port: Node3D = _station.get_docking_port(0)
	var at: Vector3 = port.global_position + port.global_transform.basis.x.normalized() * distance + port.global_transform.basis.y.normalized() * along
	var aim: Vector3 = port.global_position + port.global_transform.basis.z.normalized() * aside
	_cruiser.global_transform = Transform3D(Basis.looking_at(aim - at, port.global_transform.basis.y), at)
	_cruiser.velocity = _station.get_docking_port_velocity(0)
	for i in range(3):
		await physics_frame
		await process_frame

func _points(node_name: String) -> PackedVector3Array:
	var lines: MeshInstance3D = _cruiser.get_node(node_name)
	return (lines.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _centre(points: PackedVector3Array, square: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += points[square * 8 + k]
	return centre / 8.0

func _test_guide_leaves_along_the_nose() -> int:
	# Nose 2 km to the side of the dock: the gates still start dead ahead.
	await _park(5000.0, 0.0, 2000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible or not guide.global_position.is_equal_approx(_cruiser.global_position):
		print("FAIL _test_guide_leaves_along_the_nose: visible %s, at %s (ship at %s)" % [guide.visible, guide.global_position, _cruiser.global_position])
		return 1
	# The path bends toward the dock from the start, so the first gate sits
	# a little off the nose line: within 2 degrees is the middle of the view.
	var nose: Vector3 = -_cruiser.global_transform.basis.z.normalized()
	var first := _centre(_points("ApproachGuide"), 0)
	if rad_to_deg(first.angle_to(nose)) > 2.0:
		print("FAIL _test_guide_leaves_along_the_nose: first gate at %s, %.1f degrees off the nose %s" % [first, rad_to_deg(first.angle_to(nose)), nose])
		return 1
	return 0

func _test_guide_hides_far_from_every_dock() -> int:
	await _park(15000.0)
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_far_from_every_dock: shown 15 km from the nearest dock")
		return 1
	return 0

func _test_guide_curves_around_a_section() -> int:
	# 6 km along the ring and 2.5 km out: the straight line to the pad would
	# cut through the neighbouring section.
	await _park(2500.0, 6000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible:
		print("FAIL _test_guide_curves_around_a_section: guide hidden")
		return 1
	var points := _points("ApproachGuide")
	var to_bridge: Transform3D = _station.get_node("Bridge0").global_transform.affine_inverse()
	var half_gap: float = _station.get_bridge_length() * 0.5
	for g in range(points.size() / 8):
		var local: Vector3 = to_bridge * (guide.global_position + _centre(points, g))
		if absf(local.y) > half_gap and Vector2(local.x, local.z).length() < _station.section_radius:
			print("FAIL _test_guide_curves_around_a_section: gate %d inside a section (%s in the bridge's frame)" % [g, local])
			return 1
	return 0
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Parse Error: Too many arguments for "approach_path()" call. Expected at most 4 but received 6.`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_guide_leaves_along_the_nose: first gate at (...), 21.8 degrees off the nose (...)` and `1 TEST(S) FAILED`.

- [ ] **Step 3: Write the path**

Replace `scripts/approach_guide.gd` with:

```gdscript
extends RefCounted

# The docking approach guide: square gates along a curved path from the
# ship to the nearest dock's pad, recomputed every frame. Far gates look
# small in perspective, so the row reads as a path into the dock.
#
# The path leaves along the ship's nose (the centre of the pilot's view)
# and meets the pad square on. It is worked out in the frame of the pad's
# bridge (axis = Y, pad at y = 0), where the station near the dock is round
# about the axis: the two sections either side, from half_gap on, and the
# bridge between them. It keeps SECTION_MARGIN off the sections and
# BRIDGE_MARGIN off the bridge.

const MAX_RANGE := 10000.0
const MAX_GATES := 20
# Metres between gates: length / MAX_GATES, kept within these.
const SPACING := Vector2(50.0, 500.0)
const FIRST_GATE := 100.0
const GATE_SIZE := 30.0
const SECTION_MARGIN := 300.0
const BRIDGE_MARGIN := 100.0
# Within this angle of the pad (about half its face) the path may come down
# to the pad's height.
const PAD_WINDOW := 0.05
const PATH_SAMPLES := 128
const SHOULDER_SAMPLES := 32
# Rounding of the lifts that keep the path off the station: ramps rising
# RAMP_SLOPE metres per metre of path, then running means over
# 2 * SMOOTH_REACH + 1 samples, SMOOTH_PASSES times.
const RAMP_SLOPE := 0.5
const SMOOTH_REACH := 4
const SMOOTH_PASSES := 3
# Hermite tangents of pi/2 times the half-axes draw about a quarter ellipse.
const QUARTER := PI / 2.0

# A stretch of path in the bridge's round coordinates: distance from the
# axis, angle around it (atan2(x, z)) and height along it.
class Leg:
	var radius := PackedFloat64Array()
	var angle := PackedFloat64Array()
	var height := PackedFloat64Array()

# Distances along a path `length` long of its gates: none closer than
# FIRST_GATE, none at or past the end, at most MAX_GATES.
static func gate_distances(length: float) -> PackedFloat64Array:
	var gates := PackedFloat64Array()
	var spacing: float = clampf(length / MAX_GATES, SPACING.x, SPACING.y)
	var d := FIRST_GATE
	while d < length and gates.size() < MAX_GATES:
		gates.append(d)
		d += spacing
	return gates

# The path from `ship` to `pad` in the bridge's frame, leaving along the
# unit vector `forward` and arriving along the pad's normal.
# - One smooth curve when that clears the sections.
# - Otherwise over the rim of the nearer section (SECTION_MARGIN above it
#   and short of its end), then down into the gap on a quarter ellipse.
# Where either would still touch the station, it is lifted away from the
# axis, with the lift rounded off (see _lift).
static func approach_path(ship: Vector3, forward: Vector3, pad: Vector3, section_radius: float, half_gap: float, bridge_radius: float) -> PackedVector3Array:
	var ship_radius := Vector2(ship.x, ship.z).length()
	var ship_angle := atan2(ship.x, ship.z)
	var pad_radius := Vector2(pad.x, pad.z).length()
	var pad_angle := ship_angle + wrapf(atan2(pad.x, pad.z) - ship_angle, -PI, PI)
	var outward := Vector3(sin(ship_angle), 0.0, cos(ship_angle))
	var around := Vector3(cos(ship_angle), 0.0, -sin(ship_angle))
	var start := Vector3(ship_radius, ship_angle, ship.y)
	var shelf := section_radius + SECTION_MARGIN
	var gap := half_gap - SECTION_MARGIN
	var reach := maxf(ship.distance_to(pad), (ship_radius + pad_radius) * 0.5 * absf(pad_angle - ship_angle))
	var start_rate := Vector3(forward.dot(outward), forward.dot(around) / maxf(ship_radius, 1.0), forward.y) * reach
	var leg := _leg(start, start_rate, Vector3(pad_radius, pad_angle, pad.y), Vector3(-reach, 0.0, 0.0), PATH_SAMPLES)
	var over_sections := false
	for i in range(leg.radius.size()):
		if absf(leg.height[i]) > gap and leg.radius[i] < shelf:
			over_sections = true
	if over_sections:
		var side := signf(ship.y) if ship.y != 0.0 else 1.0
		var rim := Vector3(shelf, pad_angle, side * gap)
		var rim_reach := maxf(Vector2(ship_radius - shelf, ship.y - rim.z).length(), (ship_radius + shelf) * 0.5 * absf(pad_angle - ship_angle))
		leg = _leg(start, start_rate, rim, Vector3(0.0, 0.0, -side * rim_reach), PATH_SAMPLES)
		var shoulder := _leg(rim, Vector3(0.0, 0.0, -side * gap * QUARTER), Vector3(pad_radius, pad_angle, pad.y), Vector3(-(shelf - pad_radius) * QUARTER, 0.0, 0.0), SHOULDER_SAMPLES)
		for i in range(1, shoulder.radius.size()):
			leg.radius.append(shoulder.radius[i])
			leg.angle.append(shoulder.angle[i])
			leg.height.append(shoulder.height[i])
	_lift(leg, pad_angle, pad_radius, shelf, gap, bridge_radius + BRIDGE_MARGIN)
	var path := PackedVector3Array()
	for i in range(leg.radius.size()):
		path.append(Vector3(sin(leg.angle[i]) * leg.radius[i], leg.height[i], cos(leg.angle[i]) * leg.radius[i]))
	path[0] = ship
	path[path.size() - 1] = pad
	return path

static func _hermite(t: float, p0: float, m0: float, p1: float, m1: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1

# `samples` + 1 points from `start` to `end` (radius, angle, height), with
# the given rates of change at either end.
static func _leg(start: Vector3, start_rate: Vector3, end: Vector3, end_rate: Vector3, samples: int) -> Leg:
	var leg := Leg.new()
	for i in range(samples + 1):
		var t := float(i) / samples
		leg.radius.append(_hermite(t, start.x, start_rate.x, end.x, end_rate.x))
		leg.angle.append(_hermite(t, start.y, start_rate.y, end.y, end_rate.y))
		leg.height.append(_hermite(t, start.z, start_rate.z, end.z, end_rate.z))
	return leg

# Raises the samples that come closer to the axis than the station allows:
# `shelf` past `gap` either side (the sections), the pad's own radius over
# the pad, `bridge_floor` elsewhere. The lift slopes off either side and is
# averaged, so the path rounds what it clears; near the ship and the pad it
# grows from nothing, so the ends stay put.
static func _lift(leg: Leg, pad_angle: float, pad_radius: float, shelf: float, gap: float, bridge_floor: float) -> void:
	var n := leg.radius.size() - 1
	var need := PackedFloat64Array()
	need.resize(n + 1)
	var length := 0.0
	for i in range(1, n + 1):
		length += Vector2(leg.radius[i] - leg.radius[i - 1], leg.height[i] - leg.height[i - 1]).length() + absf(leg.angle[i] - leg.angle[i - 1]) * leg.radius[i]
		var floor_radius := bridge_floor
		if absf(leg.height[i]) > gap:
			floor_radius = shelf
		elif absf(leg.angle[i] - pad_angle) < PAD_WINDOW:
			floor_radius = pad_radius
		if i < n:
			need[i] = maxf(0.0, floor_radius - leg.radius[i])
	var step := RAMP_SLOPE * length / n
	var lift := need.duplicate()
	for i in range(1, n + 1):
		lift[i] = maxf(lift[i], lift[i - 1] - step)
	for i in range(n - 1, -1, -1):
		lift[i] = maxf(lift[i], lift[i + 1] - step)
	lift[0] = 0.0
	lift[n] = 0.0
	for p in range(SMOOTH_PASSES):
		var next := lift.duplicate()
		var total := 0.0
		for k in range(0, mini(n, SMOOTH_REACH) + 1):
			total += lift[k]
		for i in range(1, n):
			if i + SMOOTH_REACH <= n:
				total += lift[i + SMOOTH_REACH]
			if i - SMOOTH_REACH - 1 >= 0:
				total -= lift[i - SMOOTH_REACH - 1]
			var count := mini(n, i + SMOOTH_REACH) - maxi(0, i - SMOOTH_REACH) + 1
			next[i] = maxf(need[i], minf(total / count, mini(i, n - i) * step))
		lift = next
	for i in range(n + 1):
		leg.radius[i] += lift[i]

# The gates' outlines along `path` as line segments (pairs of points, in the
# path's frame): GATE_SIZE squares facing along the path where they sit,
# their "up" from up_hint (the ship's own up) unless that runs along it.
static func gates_along(path: PackedVector3Array, up_hint: Vector3) -> PackedVector3Array:
	var segments := PackedVector3Array()
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var i := 1
	var start := 0.0
	for d in gate_distances(length):
		while i < path.size() - 1 and start + path[i - 1].distance_to(path[i]) < d:
			start += path[i - 1].distance_to(path[i])
			i += 1
		var leg := path[i] - path[i - 1]
		if leg.length() <= 0.0:
			continue
		var along := leg.normalized()
		_append_square(segments, path[i - 1] + along * (d - start), along, up_hint)
	return segments

static func _append_square(segments: PackedVector3Array, centre: Vector3, along: Vector3, up_hint: Vector3) -> void:
	var right := along.cross(up_hint)
	if right.length() < 1e-6:
		right = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.BACK)
	right = right.normalized() * GATE_SIZE * 0.5
	var up := right.cross(along).normalized() * GATE_SIZE * 0.5
	var corners := [centre - right - up, centre + right - up, centre + right + up, centre - right + up]
	for k in range(4):
		segments.append(corners[k])
		segments.append(corners[(k + 1) % 4])
```

In `scripts/void_cruiser.gd` replace:

```gdscript
# The approach path to `port`, relative to the ship: worked out in the frame
# of the port's bridge (see approach_guide.gd), where the sections either
# side are round about the axis.
func _approach_path(station: Node3D, port: Node3D) -> PackedVector3Array:
	var bridge_frame: Transform3D = (port.get_parent() as Node3D).global_transform
	var local_path := ApproachGuide.approach_path(bridge_frame.affine_inverse() * global_position, port.transform.origin, station.section_radius, station.get_bridge_length() * 0.5)
	var path := PackedVector3Array()
	for point in local_path:
		path.append(bridge_frame * point - global_position)
	return path
```

with:

```gdscript
# The approach path to `port`, relative to the ship: worked out in the frame
# of the port's bridge (see approach_guide.gd), where the station near the
# dock is round about the axis. It leaves along the nose (-Z).
func _approach_path(station: Node3D, port: Node3D) -> PackedVector3Array:
	var bridge_frame: Transform3D = (port.get_parent() as Node3D).global_transform
	var to_bridge := bridge_frame.affine_inverse()
	var nose: Vector3 = (to_bridge.basis * -global_transform.basis.z).normalized()
	var local_path := ApproachGuide.approach_path(to_bridge * global_position, nose, port.transform.origin, station.section_radius, station.get_bridge_length() * 0.5, station.get_bridge_radius())
	var path := PackedVector3Array()
	for point in local_path:
		path.append(bridge_frame * point - global_position)
	return path
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add scripts/approach_guide.gd scripts/void_cruiser.gd tests/test_approach_guide.gd tests/test_docking_hud_in_tree.gd
git commit -m "Curve the approach path from the nose to the pad, round the sections and the bridge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Show the guide from 100 m to 20 km, with up to 40 gates

**Files:**
- Modify: `scripts/approach_guide.gd` (constants), `scripts/void_cruiser.gd` (range check)
- Test: `tests/test_approach_guide.gd` (`_test_gate_distances_by_length`), `tests/test_docking_hud_in_tree.gd` (whole file below)

**Interfaces:**
- Produces: `ApproachGuide.MIN_RANGE` (100), `MAX_RANGE` (20000), `MAX_GATES` (40).
- Consumes: Task 1's path and `_park(distance, along, aside)` test helper.

- [ ] **Step 1: Write the failing tests**

In `tests/test_approach_guide.gd` replace:

```gdscript
	# [path length, gate count, first gate, spacing]. The 10 km range is the
	# ship's business: a path longer than that still gets its first gates.
	for c in [[10000.0, 20, 100.0, 500.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [5000.0, 20, 100.0, 250.0], [15000.0, 20, 100.0, 500.0]]:
```

with:

```gdscript
	# [path length, gate count, first gate, spacing]. The range is the
	# ship's business: a path longer than it still gets its first gates.
	for c in [[20000.0, 40, 100.0, 500.0], [10000.0, 40, 100.0, 250.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [30000.0, 40, 100.0, 500.0]]:
```

Replace `tests/test_docking_hud_in_tree.gd` with:

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

	_failures += await _test_guide_leaves_along_the_nose()
	_failures += await _test_guide_shows_15_km_out()
	_failures += await _test_guide_hides_far_from_every_dock()
	_failures += await _test_guide_hides_on_the_last_100_m()
	_failures += await _test_guide_curves_around_a_section()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis and
# `along` metres along the bridge's axis, nose on a point `aside` metres
# across the bridge from the port, at rest with the port. Being far from
# the origin, this always makes the world shift on the next tick.
func _park(distance: float, along: float = 0.0, aside: float = 0.0) -> void:
	var port: Node3D = _station.get_docking_port(0)
	var at: Vector3 = port.global_position + port.global_transform.basis.x.normalized() * distance + port.global_transform.basis.y.normalized() * along
	var aim: Vector3 = port.global_position + port.global_transform.basis.z.normalized() * aside
	_cruiser.global_transform = Transform3D(Basis.looking_at(aim - at, port.global_transform.basis.y), at)
	_cruiser.velocity = _station.get_docking_port_velocity(0)
	for i in range(3):
		await physics_frame
		await process_frame

func _points(node_name: String) -> PackedVector3Array:
	var lines: MeshInstance3D = _cruiser.get_node(node_name)
	return (lines.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _centre(points: PackedVector3Array, square: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += points[square * 8 + k]
	return centre / 8.0

func _test_guide_leaves_along_the_nose() -> int:
	# Nose 2 km to the side of the dock: the gates still start dead ahead.
	await _park(5000.0, 0.0, 2000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible or not guide.global_position.is_equal_approx(_cruiser.global_position):
		print("FAIL _test_guide_leaves_along_the_nose: visible %s, at %s (ship at %s)" % [guide.visible, guide.global_position, _cruiser.global_position])
		return 1
	# The path bends toward the dock from the start, so the first gate sits
	# a little off the nose line: within 2 degrees is the middle of the view.
	var nose: Vector3 = -_cruiser.global_transform.basis.z.normalized()
	var first := _centre(_points("ApproachGuide"), 0)
	if rad_to_deg(first.angle_to(nose)) > 2.0:
		print("FAIL _test_guide_leaves_along_the_nose: first gate at %s, %.1f degrees off the nose %s" % [first, rad_to_deg(first.angle_to(nose)), nose])
		return 1
	return 0

func _test_guide_shows_15_km_out() -> int:
	await _park(15000.0)
	if not (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible:
		print("FAIL _test_guide_shows_15_km_out: hidden 15 km from a dock")
		return 1
	return 0

func _test_guide_hides_far_from_every_dock() -> int:
	await _park(25000.0)
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_far_from_every_dock: shown 25 km from the nearest dock")
		return 1
	return 0

func _test_guide_hides_on_the_last_100_m() -> int:
	# 95 m out with the nose turned away: the path out and back is over
	# 100 m long, enough for a gate, but the dock itself is too close.
	await _park(95.0)
	var port: Node3D = _station.get_docking_port(0)
	_cruiser.global_transform = Transform3D(Basis.looking_at(port.global_transform.basis.x, port.global_transform.basis.y), _cruiser.global_position)
	_cruiser.velocity = _station.get_docking_port_velocity(0) - _cruiser.global_transform.basis.z * 5.0
	await process_frame
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_on_the_last_100_m: shown 95 m from the dock")
		return 1
	return 0

func _test_guide_curves_around_a_section() -> int:
	# 6 km along the ring and 2.5 km out: the straight line to the pad would
	# cut through the neighbouring section.
	await _park(2500.0, 6000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible:
		print("FAIL _test_guide_curves_around_a_section: guide hidden")
		return 1
	var points := _points("ApproachGuide")
	var to_bridge: Transform3D = _station.get_node("Bridge0").global_transform.affine_inverse()
	var half_gap: float = _station.get_bridge_length() * 0.5
	for g in range(points.size() / 8):
		var local: Vector3 = to_bridge * (guide.global_position + _centre(points, g))
		if absf(local.y) > half_gap and Vector2(local.x, local.z).length() < _station.section_radius:
			print("FAIL _test_guide_curves_around_a_section: gate %d inside a section (%s in the bridge's frame)" % [g, local])
			return 1
	return 0
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: three `FAIL _test_gate_distances_by_length: at 20000 m got [...]` lines (at 20000, 10000 and 30000 m, 20 gates each) and `1 TEST(S) FAILED`.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_guide_shows_15_km_out: hidden 15 km from a dock`, `FAIL _test_guide_hides_on_the_last_100_m: shown 95 m from the dock`, `2 TEST(S) FAILED`.

- [ ] **Step 3: Change the range and the gate count**

In `scripts/approach_guide.gd` replace:

```gdscript
const MAX_RANGE := 10000.0
const MAX_GATES := 20
```

with:

```gdscript
# The guide shows between these distances (straight line, ship to pad).
const MIN_RANGE := 100.0
const MAX_RANGE := 20000.0
const MAX_GATES := 40
```

In `scripts/void_cruiser.gd` replace:

```gdscript
		if global_position.distance_to(port.global_position) <= ApproachGuide.MAX_RANGE:
```

with:

```gdscript
		var distance := global_position.distance_to(port.global_position)
		if distance >= ApproachGuide.MIN_RANGE and distance <= ApproachGuide.MAX_RANGE:
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add scripts/approach_guide.gd scripts/void_cruiser.gd tests/test_approach_guide.gd tests/test_docking_hud_in_tree.gd
git commit -m "Show the approach guide from 100 m to 20 km, with up to 40 gates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: The motion marker

**Files:**
- Modify: `scripts/approach_guide.gd` (header, constants, gate helpers), `scripts/void_cruiser.gd` (colours, guide nodes and update)
- Test: `tests/test_approach_guide.gd`, `tests/test_void_cruiser.gd` (`_test_approach_guide_hidden_without_a_station`), `tests/test_docking_hud_in_tree.gd` (whole file below)

**Interfaces:**
- Produces: `ApproachGuide.MARKER_SIZE` (20), `MARKER_MIN_SPEED` (1), `gate_centres(path) -> Array` (each `[centre: Vector3, along: Vector3]`), `marker_segments(centre, along, up_hint) -> PackedVector3Array`, `marker_on_path(gate_centre, gate_along, up_hint, marker_centre) -> bool`; void-cruiser constants `MARKER_ON_PATH_COLOR`, `MARKER_OFF_PATH_COLOR`; node `HeadingMarker` (top-level `MeshInstance3D`, `ArrayMesh` lines).
- Consumes: Tasks 1–2 (`approach_path`, `MIN_RANGE`, `MAX_RANGE`, `_approach_path`), `station.get_docking_port_velocity(index)`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_approach_guide.gd`, after the line `	failures += _test_path_curves_down_into_the_gap()` add:

```gdscript
	failures += _test_marker_is_a_20_m_square_across_the_motion()
	failures += _test_marker_on_path_only_inside_the_gate()
```

and append at the end of the file:

```gdscript
func _test_marker_is_a_20_m_square_across_the_motion() -> int:
	var along := Vector3(0.3, 0.1, -1.0).normalized()
	var segments: PackedVector3Array = ApproachGuide.marker_segments(along * 100.0, along, Vector3.UP)
	if segments.size() != 8 or not _square_centre(segments, 0).is_equal_approx(along * 100.0) or not _is_square_across(segments, 0, along, ApproachGuide.MARKER_SIZE):
		print("FAIL _test_marker_is_a_20_m_square_across_the_motion: got %s" % [segments])
		return 1
	return 0

func _test_marker_on_path_only_inside_the_gate() -> int:
	var result := 0
	var gate := Vector3(0.0, 0.0, -100.0)
	# [marker offset from the gate's centre, expected]: 5 m of room each way.
	for c in [[Vector3.ZERO, true], [Vector3(4.0, 0.0, 0.0), true], [Vector3(-4.0, 4.0, 0.0), true], [Vector3(6.0, 0.0, 0.0), false], [Vector3(0.0, -6.0, 0.0), false], [Vector3(0.0, 0.0, 20.0), true]]:
		if ApproachGuide.marker_on_path(gate, Vector3.FORWARD, Vector3.UP, gate + c[0]) != c[1]:
			print("FAIL _test_marker_on_path_only_inside_the_gate: offset %s, expected %s" % [c[0], c[1]])
			result = 1
	return result
```

In `tests/test_void_cruiser.gd` replace the whole function `_test_approach_guide_hidden_without_a_station` with:

```gdscript
func _test_approach_guide_hidden_without_a_station() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_approach_guide()
	cruiser._process(0.016)
	var result := 0
	for node_name in ["ApproachGuide", "HeadingMarker"]:
		var lines := cruiser.get_node_or_null(node_name) as MeshInstance3D
		if lines == null or not lines.top_level or lines.visible or not (lines.mesh is ArrayMesh):
			print("FAIL _test_approach_guide_hidden_without_a_station: %s missing, not top-level, not a mesh, or shown with no station" % node_name)
			result = 1
	cruiser.free()
	return result
```

Replace `tests/test_docking_hud_in_tree.gd` with:

```gdscript
extends SceneTree

# The approach guide on the real scene (station, ports, origin shift).

const ApproachGuide = preload("res://scripts/approach_guide.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

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

	_failures += await _test_guide_leaves_along_the_nose()
	_failures += await _test_guide_shows_15_km_out()
	_failures += await _test_guide_hides_far_from_every_dock()
	_failures += await _test_guide_hides_on_the_last_100_m()
	_failures += await _test_guide_curves_around_a_section()
	_failures += await _test_marker_turns_cyan_inside_the_first_gate()
	_failures += await _test_marker_hides_when_still()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis and
# `along` metres along the bridge's axis, nose on a point `aside` metres
# across the bridge from the port, at rest with the port. Being far from
# the origin, this always makes the world shift on the next tick.
func _park(distance: float, along: float = 0.0, aside: float = 0.0) -> void:
	var port: Node3D = _station.get_docking_port(0)
	var at: Vector3 = port.global_position + port.global_transform.basis.x.normalized() * distance + port.global_transform.basis.y.normalized() * along
	var aim: Vector3 = port.global_position + port.global_transform.basis.z.normalized() * aside
	_cruiser.global_transform = Transform3D(Basis.looking_at(aim - at, port.global_transform.basis.y), at)
	_cruiser.velocity = _station.get_docking_port_velocity(0)
	for i in range(3):
		await physics_frame
		await process_frame

func _points(node_name: String) -> PackedVector3Array:
	var lines: MeshInstance3D = _cruiser.get_node(node_name)
	return (lines.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _centre(points: PackedVector3Array, square: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += points[square * 8 + k]
	return centre / 8.0

func _test_guide_leaves_along_the_nose() -> int:
	# Nose 2 km to the side of the dock: the gates still start dead ahead.
	await _park(5000.0, 0.0, 2000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible or not guide.global_position.is_equal_approx(_cruiser.global_position):
		print("FAIL _test_guide_leaves_along_the_nose: visible %s, at %s (ship at %s)" % [guide.visible, guide.global_position, _cruiser.global_position])
		return 1
	# The path bends toward the dock from the start, so the first gate sits
	# a little off the nose line: within 2 degrees is the middle of the view.
	var nose: Vector3 = -_cruiser.global_transform.basis.z.normalized()
	var first := _centre(_points("ApproachGuide"), 0)
	if rad_to_deg(first.angle_to(nose)) > 2.0:
		print("FAIL _test_guide_leaves_along_the_nose: first gate at %s, %.1f degrees off the nose %s" % [first, rad_to_deg(first.angle_to(nose)), nose])
		return 1
	return 0

func _test_guide_shows_15_km_out() -> int:
	await _park(15000.0)
	if not (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible:
		print("FAIL _test_guide_shows_15_km_out: hidden 15 km from a dock")
		return 1
	return 0

func _test_guide_hides_far_from_every_dock() -> int:
	await _park(25000.0)
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible or (_cruiser.get_node("HeadingMarker") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_far_from_every_dock: shown 25 km from the nearest dock")
		return 1
	return 0

func _test_guide_hides_on_the_last_100_m() -> int:
	# 95 m out with the nose turned away: the path out and back is over
	# 100 m long, enough for a gate, but the dock itself is too close.
	await _park(95.0)
	var port: Node3D = _station.get_docking_port(0)
	_cruiser.global_transform = Transform3D(Basis.looking_at(port.global_transform.basis.x, port.global_transform.basis.y), _cruiser.global_position)
	_cruiser.velocity = _station.get_docking_port_velocity(0) - _cruiser.global_transform.basis.z * 5.0
	await process_frame
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible or (_cruiser.get_node("HeadingMarker") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_on_the_last_100_m: shown 95 m from the dock")
		return 1
	return 0

func _test_guide_curves_around_a_section() -> int:
	# 6 km along the ring and 2.5 km out: the straight line to the pad would
	# cut through the neighbouring section.
	await _park(2500.0, 6000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible:
		print("FAIL _test_guide_curves_around_a_section: guide hidden")
		return 1
	var points := _points("ApproachGuide")
	var to_bridge: Transform3D = _station.get_node("Bridge0").global_transform.affine_inverse()
	var half_gap: float = _station.get_bridge_length() * 0.5
	for g in range(points.size() / 8):
		var local: Vector3 = to_bridge * (guide.global_position + _centre(points, g))
		if absf(local.y) > half_gap and Vector2(local.x, local.z).length() < _station.section_radius:
			print("FAIL _test_guide_curves_around_a_section: gate %d inside a section (%s in the bridge's frame)" % [g, local])
			return 1
	return 0

func _test_marker_turns_cyan_inside_the_first_gate() -> int:
	var result := 0
	await _park(5000.0)
	var marker: MeshInstance3D = _cruiser.get_node("HeadingMarker")
	var nose: Vector3 = -_cruiser.global_transform.basis.z.normalized()
	var side: Vector3 = _cruiser.global_transform.basis.x.normalized()
	# [velocity relative to the dock, expected colour]: 2 m/s sideways in 50
	# puts the marker 4 m off the first gate's centre, 10 m/s puts it 20 m.
	for c in [[nose * 50.0, VoidCruiserScript.MARKER_ON_PATH_COLOR], [nose * 50.0 + side * 2.0, VoidCruiserScript.MARKER_ON_PATH_COLOR], [nose * 50.0 + side * 10.0, VoidCruiserScript.MARKER_OFF_PATH_COLOR]]:
		_cruiser.velocity = _station.get_docking_port_velocity(0) + c[0]
		await process_frame
		var colour: Color = (marker.material_override as StandardMaterial3D).albedo_color
		if not marker.visible or not colour.is_equal_approx(c[1]):
			print("FAIL _test_marker_turns_cyan_inside_the_first_gate: moving %s, visible %s, colour %s" % [c[0], marker.visible, colour])
			result = 1
			continue
		var centre := _centre(_points("HeadingMarker"), 0)
		var expected: Vector3 = c[0].normalized() * ApproachGuide.FIRST_GATE
		if centre.distance_to(expected) > 1.0:
			print("FAIL _test_marker_turns_cyan_inside_the_first_gate: marker at %s, expected %s" % [centre, expected])
			result = 1
	return result

func _test_marker_hides_when_still() -> int:
	await _park(5000.0)
	if (_cruiser.get_node("HeadingMarker") as MeshInstance3D).visible:
		print("FAIL _test_marker_hides_when_still: shown at rest with the dock")
		return 1
	return 0
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Parse Error: Static function "marker_segments()" not found in base "res://scripts/approach_guide.gd".` (and the same for `MARKER_SIZE`, `marker_on_path()`).

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_approach_guide_hidden_without_a_station: HeadingMarker missing, not top-level, not a mesh, or shown with no station`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Parse Error: Cannot find member "MARKER_ON_PATH_COLOR" in base "res://scripts/void_cruiser.gd".`

- [ ] **Step 3: Write the marker**

In `scripts/approach_guide.gd` replace:

```gdscript
# The docking approach guide: square gates along a curved path from the
# ship to the nearest dock's pad, recomputed every frame. Far gates look
# small in perspective, so the row reads as a path into the dock.
```

with:

```gdscript
# The docking approach guide: square gates along a curved path from the
# ship to the nearest dock's pad, recomputed every frame, plus a smaller
# square on the ship's line of motion. Far gates look small in perspective,
# so the row reads as a path into the dock.
```

replace:

```gdscript
const GATE_SIZE := 30.0
const SECTION_MARGIN := 300.0
```

with:

```gdscript
const GATE_SIZE := 30.0
# The motion marker: smaller than a gate, so it can sit inside one.
const MARKER_SIZE := 20.0
const MARKER_MIN_SPEED := 1.0
const SECTION_MARGIN := 300.0
```

and replace everything from the comment line starting `# The gates' outlines along` to the end of the file with:

```gdscript
# The gates along `path`: [centre, unit direction of the path there] each,
# in the path's frame.
static func gate_centres(path: PackedVector3Array) -> Array:
	var gates := []
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var i := 1
	var start := 0.0
	for d in gate_distances(length):
		while i < path.size() - 1 and start + path[i - 1].distance_to(path[i]) < d:
			start += path[i - 1].distance_to(path[i])
			i += 1
		var leg := path[i] - path[i - 1]
		if leg.length() <= 0.0:
			continue
		var along := leg.normalized()
		gates.append([path[i - 1] + along * (d - start), along])
	return gates

# The gates' outlines along `path` as line segments (pairs of points, in the
# path's frame): GATE_SIZE squares facing along the path where they sit,
# their "up" from up_hint (the ship's own up) unless that runs along it.
static func gates_along(path: PackedVector3Array, up_hint: Vector3) -> PackedVector3Array:
	var segments := PackedVector3Array()
	for gate in gate_centres(path):
		_append_square(segments, gate[0], gate[1], up_hint, GATE_SIZE)
	return segments

# The motion marker's outline: a MARKER_SIZE square at `centre`, facing
# along `along` (the direction of motion).
static func marker_segments(centre: Vector3, along: Vector3, up_hint: Vector3) -> PackedVector3Array:
	var segments := PackedVector3Array()
	_append_square(segments, centre, along, up_hint, MARKER_SIZE)
	return segments

# Whether the marker at `marker_centre` sits wholly inside the gate at
# `gate_centre` facing `gate_along`, measured across the gate.
static func marker_on_path(gate_centre: Vector3, gate_along: Vector3, up_hint: Vector3, marker_centre: Vector3) -> bool:
	var axes := _square_axes(gate_along, up_hint)
	var offset := marker_centre - gate_centre
	var room := (GATE_SIZE - MARKER_SIZE) * 0.5
	return absf(offset.dot(axes[0])) <= room and absf(offset.dot(axes[1])) <= room

# Unit right and up of a square facing along `along`, up from up_hint.
static func _square_axes(along: Vector3, up_hint: Vector3) -> Array:
	var right := along.cross(up_hint)
	if right.length() < 1e-6:
		right = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.BACK)
	right = right.normalized()
	return [right, right.cross(along).normalized()]

static func _append_square(segments: PackedVector3Array, centre: Vector3, along: Vector3, up_hint: Vector3, size: float) -> void:
	var axes := _square_axes(along, up_hint)
	var right: Vector3 = axes[0] * size * 0.5
	var up: Vector3 = axes[1] * size * 0.5
	var corners := [centre - right - up, centre + right - up, centre + right + up, centre - right + up]
	for k in range(4):
		segments.append(corners[k])
		segments.append(corners[(k + 1) % 4])
```

In `scripts/void_cruiser.gd` replace:

```gdscript
const APPROACH_COLOR := Color(0.3, 1.0, 0.4, 0.7)
```

with:

```gdscript
const APPROACH_COLOR := Color(0.3, 1.0, 0.4, 0.7)
# The motion marker: cyan inside the first gate, red outside it.
const MARKER_ON_PATH_COLOR := Color(0.3, 0.85, 1.0, 0.9)
const MARKER_OFF_PATH_COLOR := Color(1.0, 0.25, 0.2, 0.9)
```

and replace:

```gdscript
# Square gates on the path to the nearest dock (see approach_guide.gd). Not
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
		var distance := global_position.distance_to(port.global_position)
		if distance >= ApproachGuide.MIN_RANGE and distance <= ApproachGuide.MAX_RANGE:
			segments = ApproachGuide.gates_along(_approach_path(station, port), global_transform.basis.y)
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
```

with:

```gdscript
# Square gates on the path to the nearest dock, and a smaller square on the
# line of motion (see approach_guide.gd). Neither moves with the ship
# (top_level): _update_approach_guide places and redraws them every frame.
func build_approach_guide() -> void:
	add_child(_line_mesh("ApproachGuide", APPROACH_COLOR))
	add_child(_line_mesh("HeadingMarker", MARKER_OFF_PATH_COLOR))

func _line_mesh(node_name: String, color: Color) -> MeshInstance3D:
	var lines := MeshInstance3D.new()
	lines.name = node_name
	lines.top_level = true
	lines.mesh = ArrayMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	lines.material_override = material
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.visible = false
	return lines

# Shown between MIN_RANGE and MAX_RANGE (straight line) from the nearest
# dock. The marker sits on the motion relative to the dock, as far out as
# the first gate: cyan when wholly inside it, red otherwise; hidden under
# MARKER_MIN_SPEED.
func _update_approach_guide() -> void:
	var guide := get_node_or_null("ApproachGuide") as MeshInstance3D
	var marker := get_node_or_null("HeadingMarker") as MeshInstance3D
	if guide == null or marker == null:
		return
	var gate_lines := PackedVector3Array()
	var marker_lines := PackedVector3Array()
	var on_path := false
	var station: Node3D = null
	if is_inside_tree():
		station = get_node_or_null(station_path) as Node3D
	if station != null and station.is_inside_tree():
		var index: int = station.nearest_bridge_index(global_position)
		var port: Node3D = station.get_docking_port(index)
		var distance := global_position.distance_to(port.global_position)
		if distance >= ApproachGuide.MIN_RANGE and distance <= ApproachGuide.MAX_RANGE:
			var up := global_transform.basis.y
			var path := _approach_path(station, port)
			gate_lines = ApproachGuide.gates_along(path, up)
			var gates := ApproachGuide.gate_centres(path)
			var motion: Vector3 = velocity - station.get_docking_port_velocity(index)
			if not gates.is_empty() and motion.length() >= ApproachGuide.MARKER_MIN_SPEED:
				var first: Vector3 = gates[0][0]
				var centre := motion.normalized() * first.length()
				marker_lines = ApproachGuide.marker_segments(centre, motion.normalized(), up)
				on_path = ApproachGuide.marker_on_path(first, gates[0][1], up, centre)
	_show_lines(guide, gate_lines)
	(marker.material_override as StandardMaterial3D).albedo_color = MARKER_ON_PATH_COLOR if on_path else MARKER_OFF_PATH_COLOR
	_show_lines(marker, marker_lines)

# Draws `segments` (relative to the ship) on `lines`, or hides it.
func _show_lines(lines: MeshInstance3D, segments: PackedVector3Array) -> void:
	lines.visible = not segments.is_empty()
	if segments.is_empty():
		return
	lines.global_transform = Transform3D(Basis(), global_position)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = segments
	var mesh := lines.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_approach_guide.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Run the suite and the live check**

Run: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh`
Expected: exit 0, every file `ALL TESTS PASSED` (32 files).

Run the live check from Global Constraints. Expected: no output.

- [ ] **Step 6: Render and look**

Write this probe to the scratchpad as `probe_guide.gd` (replace `SCRATCH` with the scratchpad path) and run `xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . -s <scratchpad>/probe_guide.gd`:

```gdscript
extends SceneTree

func _initialize():
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	var station: Node3D = scene.get_node("PlanetSystem/TorusStation")
	station.set_process(false)
	var cruiser: CharacterBody3D = scene.get_node("VoidCruiser")
	cruiser.set_physics_process(false)
	var port: Node3D = station.get_docking_port(0)
	var out: Vector3 = port.global_transform.basis.x.normalized()
	var axis: Vector3 = port.global_transform.basis.y.normalized()
	var eye: Vector3 = port.global_position + out * 2500.0 + axis * 6000.0
	var look: Vector3 = port.global_position + out * 2300.0 + axis * 3000.0
	cruiser.global_transform = Transform3D(Basis.looking_at(look - eye, out), eye)
	# 4 m/s off the nose line in 60: the marker sits ~7 m off, so red.
	cruiser.velocity = station.get_docking_port_velocity(0) + (look - eye).normalized() * 60.0 + out * 4.0
	for i in range(6):
		await physics_frame
		await process_frame
	root.get_texture().get_image().save_png("SCRATCH/guide_cockpit.png")
	port = station.get_docking_port(0)
	out = port.global_transform.basis.x.normalized()
	axis = port.global_transform.basis.y.normalized()
	var side: Vector3 = port.global_transform.basis.z.normalized()
	var cam := Camera3D.new()
	cam.far = 100000.0
	root.add_child(cam)
	var mid: Vector3 = port.global_position + out * 1500.0 + axis * 3000.0
	var cam_pos: Vector3 = mid + side * 9000.0 + out * 1000.0
	cam.global_transform = Transform3D(Basis.looking_at(mid - cam_pos, out), cam_pos)
	cam.current = true
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png("SCRATCH/guide_side.png")
	quit()
```

Expected, read with the Read tool:
- `guide_cockpit.png`: the gates start at the centre of the view and run along the section's top toward the gap; a red square a little off the first gate.
- `guide_side.png`: the dotted path runs over the section, then curves down into the gap to the pad with no long straight run.

- [ ] **Step 7: Commit**

```bash
git add scripts/approach_guide.gd scripts/void_cruiser.gd tests/test_approach_guide.gd tests/test_void_cruiser.gd tests/test_docking_hud_in_tree.gd
git commit -m "Add the motion marker: cyan inside the first gate, red outside it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
