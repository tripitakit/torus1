# First-Person Cockpit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the external chase view of the void-cruiser with a first-person procedural cockpit: three screens (center + two side screens tilted 30°) showing a continuous 3-camera panorama, and a dashboard HUD panel with speed and six hull-to-surface distances.

**Architecture:** Two pure static-function files (`cockpit_layout.gd` for screen/camera geometry, `cockpit_hud_format.gd` for HUD strings) plus one node script (`cockpit.gd`) that builds the cockpit in code. Exterior cameras live in `SubViewport`s whose textures are shown on unshaded 3D quads; `RemoteTransform3D` mounts make those cameras follow the ship (a `SubViewport` breaks the 3D transform chain). Six `RayCast3D` sensors on the ship's hull faces feed the HUD. Visual layers keep the cockpit visible only to the pilot camera and the ship's exterior markers invisible to all on-board cameras. The ship model and the `ChaseCamera` are removed.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Tests are headless `extends SceneTree` scripts.

**Spec:** `docs/superpowers/specs/2026-09-23-cockpit-first-person-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. Run one test file with `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite command (used by every task's final check):
  `for f in tests/*.gd; do echo "=== $f ==="; /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script "$f" 2>&1 | grep -E "ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error"; done`
  Expected when green: every file prints exactly `ALL TESTS PASSED` and nothing else from the grep.
- **Reading RED correctly:** in this project a call to a missing method prints `SCRIPT ERROR: ... Nonexistent function ...`, aborts that test function, and the file may still end with `ALL TESTS PASSED`. RED is confirmed by the `SCRIPT ERROR`/`Parse Error`/`FAIL` lines, never by the summary line alone.
- **Fresh worktree:** before the first test run in a new worktree, run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import` once (the `.godot/` import cache is git-ignored; without it textures and the `.glb` fail to load).
- GDScript typing footgun: `var x := some_builtin(...)` can fail with "type inferred from Variant, warning treated as error". Write the type explicitly: `var x: float = ...`.
- Off-tree unit tests use `_init()` and never add nodes to the tree. In-tree tests use `_initialize()` and `await process_frame` / `await physics_frame` (see `tests/test_torus_station_physics.gd`); disable the node's own `_process`/`_physics_process` there when they would interfere.
- Code and code comments in English (as the existing code). Docs in Italian.
- Ship axes (fixed): forward/nose = -Z, tail = +Z, left/port = -X, right/starboard = +X, up/dorsal = +Y. Hull box `15 (X) × 7.5 (Y) × 30 (Z)`.
- Visual layers (bit values): world = `1`, `COCKPIT_LAYER = 2`, `SHIP_EXTERIOR_LAYER = 4`. Full mask `0xFFFFF`.
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never stage anything under `.claude/worktrees/`.
- **Prerequisite, outside this plan:** `master` currently has uncommitted changes (headlight tuning in `scripts/void_cruiser.gd` / `tests/test_void_cruiser.gd`, temporary `[DEBUG ...]` prints in `scripts/void_cruiser.gd` and `scripts/world_origin_rebase.gd`). They are not part of this plan. The worktree is created from the committed `HEAD`, so they do not appear there; do not recreate or commit them.

## Review Focus

1. **Ship not at identity orientation** — a rotated ship must still measure distances along its own bow/stern/side axes, not world axes. Test: `_test_sensors_follow_ship_rotation` (Task 3).
2. **Ship moved/rotated (including a world-origin rebase, which moves the ship's `position`)** — exterior cameras must stay at the pilot's eye and keep their 0/±60° yaw. Tests: `_test_exterior_cameras_follow_the_pilot_eye`, `_test_side_cameras_look_sixty_degrees_off_the_bow` (Task 4).
3. **HUD before any sensor reading / missing keys** — the first frame, or a distances dictionary without some key, must show `—`, not crash. Test: `_test_update_hud_missing_distances_show_no_reading` (Task 4).
4. **Rounding at the metre/kilometre boundary** — 999.6 m must read `1.0 km`, not `1000 m`. Test: `_test_format_distance_rounds_up_into_kilometres` (Task 2).
5. **Which camera is live at scene load** — with `ChaseCamera` gone, `TopDownCamera` must not be current, so the cockpit's `PilotCamera` wins. Test: extra check in `_test_scene_wiring` (Task 5).

---

### Task 1: Cockpit layout pure functions

**Files:**
- Create: `scripts/cockpit_layout.gd`
- Test: `tests/test_cockpit_layout.gd` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `static func compute_side_screen_transform(center_width: float, side_width: float, screen_distance: float, tilt_degrees: float, side: float) -> Transform3D` — `side = -1.0` left, `+1.0` right. Transform is relative to the pilot's eye (origin), screens face +Z (toward the eye).
  - `static func compute_side_camera_yaw_degrees(horizontal_fov_degrees: float, side: float) -> float` — returns `-side * horizontal_fov_degrees` (left `+60`, right `-60` for a 60° FOV).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_cockpit_layout.gd`:

```gdscript
extends SceneTree

const CockpitLayout = preload("res://scripts/cockpit_layout.gd")

const CENTER_WIDTH := 1.6
const SIDE_WIDTH := 0.9
const SCREEN_DISTANCE := 1.6
const TILT := 30.0

func _init():
	var failures := 0
	failures += _test_left_screen_inner_edge_touches_center_screen_left_edge()
	failures += _test_right_screen_inner_edge_touches_center_screen_right_edge()
	failures += _test_side_screens_face_the_pilot()
	failures += _test_side_screens_are_tilted_toward_the_center_by_tilt_angle()
	failures += _test_left_camera_yaws_left_by_one_fov()
	failures += _test_right_camera_yaws_right_by_one_fov()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_left_screen_inner_edge_touches_center_screen_left_edge() -> int:
	var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, -1.0)
	# The left screen's inner edge is its local +X edge.
	var inner_edge: Vector3 = t * Vector3(SIDE_WIDTH * 0.5, 0.0, 0.0)
	var center_left_edge := Vector3(-CENTER_WIDTH * 0.5, 0.0, -SCREEN_DISTANCE)
	if not inner_edge.is_equal_approx(center_left_edge):
		print("FAIL _test_left_screen_inner_edge_touches_center_screen_left_edge: inner_edge=%s expected=%s" % [inner_edge, center_left_edge])
		return 1
	return 0

func _test_right_screen_inner_edge_touches_center_screen_right_edge() -> int:
	var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, 1.0)
	# The right screen's inner edge is its local -X edge.
	var inner_edge: Vector3 = t * Vector3(-SIDE_WIDTH * 0.5, 0.0, 0.0)
	var center_right_edge := Vector3(CENTER_WIDTH * 0.5, 0.0, -SCREEN_DISTANCE)
	if not inner_edge.is_equal_approx(center_right_edge):
		print("FAIL _test_right_screen_inner_edge_touches_center_screen_right_edge: inner_edge=%s expected=%s" % [inner_edge, center_right_edge])
		return 1
	return 0

func _test_side_screens_face_the_pilot() -> int:
	var result := 0
	for side in [-1.0, 1.0]:
		var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, side)
		# A QuadMesh shows its front face along local +Z; the eye is at the origin.
		var to_eye: Vector3 = Vector3.ZERO - t.origin
		if t.basis.z.dot(to_eye) <= 0.0:
			print("FAIL _test_side_screens_face_the_pilot: side=%s normal=%s to_eye=%s" % [side, t.basis.z, to_eye])
			result = 1
	return result

func _test_side_screens_are_tilted_toward_the_center_by_tilt_angle() -> int:
	var result := 0
	for side in [-1.0, 1.0]:
		var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, side)
		var angle: float = rad_to_deg(t.basis.z.angle_to(Vector3(0.0, 0.0, 1.0)))
		if not is_equal_approx(angle, TILT):
			print("FAIL _test_side_screens_are_tilted_toward_the_center_by_tilt_angle: side=%s angle=%f expected=%f" % [side, angle, TILT])
			result = 1
		# Turned toward the center: the left screen's normal points to +X, the right one's to -X.
		if sign(t.basis.z.x) != -side:
			print("FAIL _test_side_screens_are_tilted_toward_the_center_by_tilt_angle: side=%s normal=%s turned away from the center" % [side, t.basis.z])
			result = 1
	return result

func _test_left_camera_yaws_left_by_one_fov() -> int:
	var yaw: float = CockpitLayout.compute_side_camera_yaw_degrees(60.0, -1.0)
	var result := 0
	if not is_equal_approx(yaw, 60.0):
		print("FAIL _test_left_camera_yaws_left_by_one_fov: yaw=%f expected=60.0" % yaw)
		result = 1
	var looks: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.0, 0.0, -1.0)
	if looks.x >= 0.0:
		print("FAIL _test_left_camera_yaws_left_by_one_fov: camera looks toward %s, expected negative X (left)" % looks)
		result = 1
	return result

func _test_right_camera_yaws_right_by_one_fov() -> int:
	var yaw: float = CockpitLayout.compute_side_camera_yaw_degrees(60.0, 1.0)
	var result := 0
	if not is_equal_approx(yaw, -60.0):
		print("FAIL _test_right_camera_yaws_right_by_one_fov: yaw=%f expected=-60.0" % yaw)
		result = 1
	var looks: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.0, 0.0, -1.0)
	if looks.x <= 0.0:
		print("FAIL _test_right_camera_yaws_right_by_one_fov: camera looks toward %s, expected positive X (right)" % looks)
		result = 1
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit_layout.gd`
Expected: a load/parse error for `res://scripts/cockpit_layout.gd` (file does not exist).

- [ ] **Step 3: Implement**

Create `scripts/cockpit_layout.gd`:

```gdscript
extends RefCounted

# Side screens hinge on the center screen's outer edge and turn toward the
# pilot by tilt_degrees. side: -1 = left, +1 = right. Eye at the origin,
# screens face +Z.
static func compute_side_screen_transform(center_width: float, side_width: float, screen_distance: float, tilt_degrees: float, side: float) -> Transform3D:
	var hinge := Vector3(side * center_width * 0.5, 0.0, -screen_distance)
	var screen_basis := Basis(Vector3.UP, deg_to_rad(-side * tilt_degrees))
	var screen_origin: Vector3 = hinge + screen_basis * Vector3(side * side_width * 0.5, 0.0, 0.0)
	return Transform3D(screen_basis, screen_origin)

# A side camera turned by one full horizontal FOV starts exactly where the
# front camera's image ends: a continuous panorama with no blind wedge.
static func compute_side_camera_yaw_degrees(horizontal_fov_degrees: float, side: float) -> float:
	return -side * horizontal_fov_degrees
```

- [ ] **Step 4: Run to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit_layout.gd`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/cockpit_layout.gd tests/test_cockpit_layout.gd
git commit -m "$(cat <<'EOF'
Add pure cockpit layout: hinged side screens and panorama camera yaw

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(Godot may create `scripts/cockpit_layout.gd.uid` / `tests/test_cockpit_layout.gd.uid` on first load; `.uid` files are tracked in this repo — add them too if present.)

---

### Task 2: HUD formatting pure functions

**Files:**
- Create: `scripts/cockpit_hud_format.gd`
- Test: `tests/test_cockpit_hud_format.gd` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `const NO_READING := "—"`
  - `static func format_speed(speed: float) -> String` → e.g. `"1240 m/s"`.
  - `static func format_distance(distance: float) -> String` → `"—"` if `distance < 0`, `"%d m"` if the rounded metres are `< 1000`, else `"%.1f km"`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_cockpit_hud_format.gd`:

```gdscript
extends SceneTree

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

func _init():
	var failures := 0
	failures += _test_format_speed_rounds_to_whole_metres_per_second()
	failures += _test_format_speed_zero()
	failures += _test_format_distance_negative_means_no_reading()
	failures += _test_format_distance_below_a_kilometre_in_metres()
	failures += _test_format_distance_zero_metres()
	failures += _test_format_distance_rounds_up_into_kilometres()
	failures += _test_format_distance_kilometres_one_decimal()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _check(test_name: String, actual: String, expected: String) -> int:
	if actual != expected:
		print("FAIL %s: got '%s' expected '%s'" % [test_name, actual, expected])
		return 1
	return 0

func _test_format_speed_rounds_to_whole_metres_per_second() -> int:
	return _check("_test_format_speed_rounds_to_whole_metres_per_second", CockpitHudFormat.format_speed(1240.4), "1240 m/s")

func _test_format_speed_zero() -> int:
	return _check("_test_format_speed_zero", CockpitHudFormat.format_speed(0.0), "0 m/s")

func _test_format_distance_negative_means_no_reading() -> int:
	return _check("_test_format_distance_negative_means_no_reading", CockpitHudFormat.format_distance(-1.0), "—")

func _test_format_distance_below_a_kilometre_in_metres() -> int:
	return _check("_test_format_distance_below_a_kilometre_in_metres", CockpitHudFormat.format_distance(819.6), "820 m")

func _test_format_distance_zero_metres() -> int:
	return _check("_test_format_distance_zero_metres", CockpitHudFormat.format_distance(0.0), "0 m")

func _test_format_distance_rounds_up_into_kilometres() -> int:
	# 999.6 m rounds to 1000 m: must switch to km, never print "1000 m".
	var failures := 0
	failures += _check("_test_format_distance_rounds_up_into_kilometres(999.4)", CockpitHudFormat.format_distance(999.4), "999 m")
	failures += _check("_test_format_distance_rounds_up_into_kilometres(999.6)", CockpitHudFormat.format_distance(999.6), "1.0 km")
	failures += _check("_test_format_distance_rounds_up_into_kilometres(1000)", CockpitHudFormat.format_distance(1000.0), "1.0 km")
	return 1 if failures > 0 else 0

func _test_format_distance_kilometres_one_decimal() -> int:
	return _check("_test_format_distance_kilometres_one_decimal", CockpitHudFormat.format_distance(3140.0), "3.1 km")
```

- [ ] **Step 2: Run to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit_hud_format.gd`
Expected: a load/parse error for `res://scripts/cockpit_hud_format.gd`.

- [ ] **Step 3: Implement**

Create `scripts/cockpit_hud_format.gd`:

```gdscript
extends RefCounted

const NO_READING := "—"

static func format_speed(speed: float) -> String:
	return "%d m/s" % roundi(speed)

static func format_distance(distance: float) -> String:
	if distance < 0.0:
		return NO_READING
	# Decide the unit on the rounded value, so 999.6 m never shows as "1000 m".
	var metres: int = roundi(distance)
	if metres < 1000:
		return "%d m" % metres
	return "%.1f km" % (distance / 1000.0)
```

- [ ] **Step 4: Run to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit_hud_format.gd`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/cockpit_hud_format.gd tests/test_cockpit_hud_format.gd
git commit -m "$(cat <<'EOF'
Add pure HUD formatting for speed and hull-to-surface distances

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(Add the matching `.uid` files if Godot created them.)

---

### Task 3: Proximity sensors on the ship

**Files:**
- Modify: `scripts/void_cruiser.gd` (constants block, `_ready`, `build_collision_shape`, new methods after `build_collision_shape`)
- Modify: `tests/test_void_cruiser.gd` (failures list + two new test functions at the end)
- Test: `tests/test_proximity_sensors_physics.gd` (create; in-tree)

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces (on the `VoidCruiser` node):
  - `const HULL_SIZE := Vector3(15.0, 7.5, 30.0)`
  - `const SENSOR_RANGE := 20000.0`
  - `const SENSOR_DIRECTIONS` — keys `"bow", "stern", "port", "starboard", "dorsal", "ventral"`.
  - `func build_proximity_sensors() -> void` — children `SensorBow`, `SensorStern`, `SensorPort`, `SensorStarboard`, `SensorDorsal`, `SensorVentral` (`RayCast3D`).
  - `func read_proximity_distances() -> Dictionary` — the six keys above → `float` distance from the hull face to the hit point, or `-1.0` for no hit. Requires `build_proximity_sensors()` first.

- [ ] **Step 1: Write the failing off-tree tests**

In `tests/test_void_cruiser.gd`, add to the `_init()` failures list, right after `failures += _test_build_headlights_adds_two_spotlights_near_the_nose()`:

```gdscript
	failures += _test_build_proximity_sensors_adds_six_rays_on_hull_faces()
	failures += _test_read_proximity_distances_off_tree_reports_no_hit()
```

Append at the end of the file:

```gdscript
func _test_build_proximity_sensors_adds_six_rays_on_hull_faces() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	var result := 0
	# name: [position on the hull face, target_position (20 km outward)]
	var expected := {
		"SensorBow": [Vector3(0.0, 0.0, -15.0), Vector3(0.0, 0.0, -20000.0)],
		"SensorStern": [Vector3(0.0, 0.0, 15.0), Vector3(0.0, 0.0, 20000.0)],
		"SensorPort": [Vector3(-7.5, 0.0, 0.0), Vector3(-20000.0, 0.0, 0.0)],
		"SensorStarboard": [Vector3(7.5, 0.0, 0.0), Vector3(20000.0, 0.0, 0.0)],
		"SensorDorsal": [Vector3(0.0, 3.75, 0.0), Vector3(0.0, 20000.0, 0.0)],
		"SensorVentral": [Vector3(0.0, -3.75, 0.0), Vector3(0.0, -20000.0, 0.0)],
	}
	for sensor_name in expected:
		var node := cruiser.get_node_or_null(sensor_name)
		if node == null or not (node is RayCast3D):
			print("FAIL _test_build_proximity_sensors_adds_six_rays_on_hull_faces: no %s RayCast3D child" % sensor_name)
			result = 1
			continue
		var ray: RayCast3D = node
		var expected_position: Vector3 = expected[sensor_name][0]
		var expected_target: Vector3 = expected[sensor_name][1]
		if not ray.position.is_equal_approx(expected_position):
			print("FAIL _test_build_proximity_sensors_adds_six_rays_on_hull_faces: %s position=%s expected=%s" % [sensor_name, ray.position, expected_position])
			result = 1
		if not ray.target_position.is_equal_approx(expected_target):
			print("FAIL _test_build_proximity_sensors_adds_six_rays_on_hull_faces: %s target_position=%s expected=%s" % [sensor_name, ray.target_position, expected_target])
			result = 1
	cruiser.free()
	return result

func _test_read_proximity_distances_off_tree_reports_no_hit() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	for key in ["bow", "stern", "port", "starboard", "dorsal", "ventral"]:
		if not distances.has(key):
			print("FAIL _test_read_proximity_distances_off_tree_reports_no_hit: missing key %s" % key)
			result = 1
		elif not is_equal_approx(distances[key], -1.0):
			print("FAIL _test_read_proximity_distances_off_tree_reports_no_hit: %s=%s expected -1.0 (no physics frame, no hit)" % [key, distances[key]])
			result = 1
	if distances.size() != 6:
		print("FAIL _test_read_proximity_distances_off_tree_reports_no_hit: %d keys, expected 6" % distances.size())
		result = 1
	cruiser.free()
	return result
```

- [ ] **Step 2: Write the failing in-tree test**

Create `tests/test_proximity_sensors_physics.gd`:

```gdscript
extends SceneTree

# RayCast3D only reports hits after real physics frames, which the off-tree
# tests in test_void_cruiser.gd never process. Same in-tree technique as
# test_torus_station_physics.gd.

const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

var _failures := 0

func _initialize():
	await process_frame
	await physics_frame

	_failures += await _test_bow_sensor_measures_gap_from_hull_to_obstacle()
	_failures += await _test_sensor_with_nothing_in_range_reports_no_hit()
	_failures += await _test_sensors_follow_ship_rotation()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_cruiser_in_tree() -> CharacterBody3D:
	var cruiser: CharacterBody3D = VoidCruiserScript.new()
	root.add_child(cruiser)
	# Keep the ship still and skip per-frame work unrelated to the sensors.
	cruiser.set_physics_process(false)
	cruiser.set_process(false)
	return cruiser

func _make_obstacle(center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 10.0)
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = center
	root.add_child(body)
	return body

func _test_bow_sensor_measures_gap_from_hull_to_obstacle() -> int:
	var cruiser := _make_cruiser_in_tree()
	# Obstacle's near face at z = -115; bow hull face at z = -15: 100 m gap.
	var obstacle := _make_obstacle(Vector3(0.0, 0.0, -120.0))
	await physics_frame
	await physics_frame
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	if not is_equal_approx(distances["bow"], 100.0):
		print("FAIL _test_bow_sensor_measures_gap_from_hull_to_obstacle: bow=%s expected 100.0" % distances["bow"])
		result = 1
	cruiser.free()
	obstacle.free()
	return result

func _test_sensor_with_nothing_in_range_reports_no_hit() -> int:
	var cruiser := _make_cruiser_in_tree()
	var obstacle := _make_obstacle(Vector3(0.0, 0.0, -120.0))
	await physics_frame
	await physics_frame
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	if not is_equal_approx(distances["stern"], -1.0):
		print("FAIL _test_sensor_with_nothing_in_range_reports_no_hit: stern=%s expected -1.0" % distances["stern"])
		result = 1
	cruiser.free()
	obstacle.free()
	return result

func _test_sensors_follow_ship_rotation() -> int:
	var cruiser := _make_cruiser_in_tree()
	# Yaw +90°: the bow (-Z local) now points to world -X.
	cruiser.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	var obstacle := _make_obstacle(Vector3(-120.0, 0.0, 0.0))
	await physics_frame
	await physics_frame
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	if not is_equal_approx(distances["bow"], 100.0):
		print("FAIL _test_sensors_follow_ship_rotation: bow=%s expected 100.0 (sensors must use the ship's axes, not world axes)" % distances["bow"])
		result = 1
	cruiser.free()
	obstacle.free()
	return result
```

- [ ] **Step 3: Run both to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd`
Expected: `SCRIPT ERROR: ... Nonexistent function 'build_proximity_sensors'` (twice).

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_proximity_sensors_physics.gd`
Expected: `SCRIPT ERROR: ... Nonexistent function 'read_proximity_distances'` (three times).

- [ ] **Step 4: Implement**

In `scripts/void_cruiser.gd`, add after the line `const HEADLIGHT_ANGLE := ...` (keep whatever value is there):

```gdscript
const HULL_SIZE := Vector3(15.0, 7.5, 30.0)
const SENSOR_RANGE := 20000.0
const SENSOR_DIRECTIONS := {
	"bow": Vector3(0.0, 0.0, -1.0),
	"stern": Vector3(0.0, 0.0, 1.0),
	"port": Vector3(-1.0, 0.0, 0.0),
	"starboard": Vector3(1.0, 0.0, 0.0),
	"dorsal": Vector3(0.0, 1.0, 0.0),
	"ventral": Vector3(0.0, -1.0, 0.0),
}
```

In `build_collision_shape()`, replace `box.size = Vector3(15.0, 7.5, 30.0)` with `box.size = HULL_SIZE`.

In `_ready()`, add `build_proximity_sensors()` right after `build_collision_shape()`.

Add after the `build_collision_shape()` function:

```gdscript
func build_proximity_sensors() -> void:
	# One ray per hull face, starting on the face itself, so the reading is
	# the gap between the hull and the surface, not the ship's center.
	# exclude_parent (on by default) keeps the rays from hitting the ship.
	for key in SENSOR_DIRECTIONS:
		var direction: Vector3 = SENSOR_DIRECTIONS[key]
		var ray := RayCast3D.new()
		ray.name = "Sensor" + String(key).capitalize()
		ray.position = direction * HULL_SIZE * 0.5
		ray.target_position = direction * SENSOR_RANGE
		add_child(ray)

func read_proximity_distances() -> Dictionary:
	var distances := {}
	for key in SENSOR_DIRECTIONS:
		var ray: RayCast3D = get_node("Sensor" + String(key).capitalize())
		if ray.is_colliding():
			distances[key] = ray.global_position.distance_to(ray.get_collision_point())
		else:
			distances[key] = -1.0
	return distances
```

- [ ] **Step 5: Run to verify they pass**

Run the two commands from Step 3.
Expected: `ALL TESTS PASSED` for both (the in-tree file may also print engine leak warnings at exit; they are pre-existing and harmless).

- [ ] **Step 6: Full suite**

Run the full suite command (Global Constraints). Expected: every file `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd tests/test_proximity_sensors_physics.gd
git commit -m "$(cat <<'EOF'
Add six hull-face proximity sensors to the void cruiser

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(Add `tests/test_proximity_sensors_physics.gd.uid` if created.)

---

### Task 4: Cockpit node

**Files:**
- Create: `scripts/cockpit.gd`
- Test: `tests/test_cockpit.gd` (create; off-tree)
- Test: `tests/test_cockpit_in_tree.gd` (create; in-tree)

**Interfaces:**
- Consumes: `CockpitLayout.compute_side_screen_transform(...)`, `CockpitLayout.compute_side_camera_yaw_degrees(...)` (Task 1); `CockpitHudFormat.format_speed(...)`, `CockpitHudFormat.format_distance(...)` (Task 2). Distances dictionary keys from Task 3: `"bow", "stern", "port", "starboard", "dorsal", "ventral"`.
- Produces:
  - `const COCKPIT_LAYER := 2`, `const SHIP_EXTERIOR_LAYER := 4`
  - `func build() -> void` — builds the node tree below. Works off-tree.
  - `func update_hud(speed: float, distances: Dictionary) -> void`
  - Node tree:
    ```
    Cockpit
      PilotCamera (Camera3D)
      CockpitLight (OmniLight3D)
      FrontViewport / LeftViewport / RightViewport (SubViewport) → Camera (Camera3D)
      FrontCameraMount / LeftCameraMount / RightCameraMount (RemoteTransform3D)
      FrontScreen / LeftScreen / RightScreen (MeshInstance3D) → Bezel (MeshInstance3D)
      Dashboard (MeshInstance3D)
      HudViewport (SubViewport) → Background (ColorRect), Lines (VBoxContainer) →
          SpeedLabel, BowLabel, SternLabel, PortLabel, StarboardLabel, DorsalLabel, VentralLabel
      HudScreen (MeshInstance3D)
    ```

- [ ] **Step 1: Write the failing off-tree tests**

Create `tests/test_cockpit.gd`:

```gdscript
extends SceneTree

const CockpitScript = preload("res://scripts/cockpit.gd")

func _init():
	var failures := 0
	failures += _test_pilot_camera_sees_only_the_cockpit()
	failures += _test_exterior_cameras_form_a_continuous_panorama()
	failures += _test_camera_mounts_drive_their_cameras()
	failures += _test_screens_show_their_viewport_textures()
	failures += _test_cockpit_meshes_are_on_cockpit_layer_without_shadows()
	failures += _test_side_screens_touch_the_front_screen_edges()
	failures += _test_hud_screen_sits_below_and_faces_the_pilot()
	failures += _test_hud_lines_in_display_order()
	failures += _test_update_hud_writes_speed_and_distances()
	failures += _test_update_hud_missing_distances_show_no_reading()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cockpit() -> Node3D:
	var cockpit: Node3D = CockpitScript.new()
	cockpit.build()
	return cockpit

func _test_pilot_camera_sees_only_the_cockpit() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var camera := cockpit.get_node_or_null("PilotCamera")
	if camera == null or not (camera is Camera3D):
		print("FAIL _test_pilot_camera_sees_only_the_cockpit: no PilotCamera Camera3D")
		result = 1
	else:
		var pilot: Camera3D = camera
		if pilot.cull_mask != 2:
			print("FAIL _test_pilot_camera_sees_only_the_cockpit: cull_mask=%d expected 2 (COCKPIT_LAYER only)" % pilot.cull_mask)
			result = 1
		if not pilot.current:
			print("FAIL _test_pilot_camera_sees_only_the_cockpit: PilotCamera is not current")
			result = 1
	cockpit.free()
	return result

func _test_exterior_cameras_form_a_continuous_panorama() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var expected_yaw := {"Front": 0.0, "Left": 60.0, "Right": -60.0}
	for prefix in expected_yaw:
		var camera := cockpit.get_node_or_null("%sViewport/Camera" % prefix)
		if camera == null or not (camera is Camera3D):
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: no %sViewport/Camera" % prefix)
			result = 1
			continue
		var cam: Camera3D = camera
		if cam.keep_aspect != Camera3D.KEEP_WIDTH or not is_equal_approx(cam.fov, 60.0):
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: %s keep_aspect=%d fov=%f expected KEEP_WIDTH and 60 (horizontal FOV)" % [prefix, cam.keep_aspect, cam.fov])
			result = 1
		if (cam.cull_mask & 1) == 0 or (cam.cull_mask & 2) != 0 or (cam.cull_mask & 4) != 0:
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: %s cull_mask=%d must include world (1) and exclude cockpit (2) and ship exterior (4)" % [prefix, cam.cull_mask])
			result = 1
		var mount := cockpit.get_node_or_null("%sCameraMount" % prefix)
		if mount == null or not (mount is RemoteTransform3D):
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: no %sCameraMount RemoteTransform3D" % prefix)
			result = 1
		elif not is_equal_approx((mount as Node3D).rotation_degrees.y, expected_yaw[prefix]):
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: %sCameraMount yaw=%f expected=%f" % [prefix, (mount as Node3D).rotation_degrees.y, expected_yaw[prefix]])
			result = 1
	cockpit.free()
	return result

func _test_camera_mounts_drive_their_cameras() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	for prefix in ["Front", "Left", "Right"]:
		var mount: RemoteTransform3D = cockpit.get_node("%sCameraMount" % prefix)
		var camera: Node = cockpit.get_node("%sViewport/Camera" % prefix)
		if mount.get_node_or_null(mount.remote_path) != camera:
			print("FAIL _test_camera_mounts_drive_their_cameras: %sCameraMount.remote_path=%s does not resolve to %sViewport/Camera" % [prefix, mount.remote_path, prefix])
			result = 1
	cockpit.free()
	return result

func _test_screens_show_their_viewport_textures() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var pairs := {"FrontScreen": "FrontViewport", "LeftScreen": "LeftViewport", "RightScreen": "RightViewport", "HudScreen": "HudViewport"}
	for screen_name in pairs:
		var screen := cockpit.get_node_or_null(screen_name)
		var viewport := cockpit.get_node_or_null(pairs[screen_name])
		if screen == null or viewport == null:
			print("FAIL _test_screens_show_their_viewport_textures: missing %s or %s" % [screen_name, pairs[screen_name]])
			result = 1
			continue
		var material := (screen as MeshInstance3D).material_override as StandardMaterial3D
		if material == null or material.albedo_texture != (viewport as SubViewport).get_texture():
			print("FAIL _test_screens_show_their_viewport_textures: %s does not show %s's texture" % [screen_name, pairs[screen_name]])
			result = 1
		elif material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			print("FAIL _test_screens_show_their_viewport_textures: %s material is not unshaded" % screen_name)
			result = 1
		if (viewport as SubViewport).render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			print("FAIL _test_screens_show_their_viewport_textures: %s does not update always" % pairs[screen_name])
			result = 1
	cockpit.free()
	return result

func _test_cockpit_meshes_are_on_cockpit_layer_without_shadows() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var meshes := cockpit.find_children("*", "MeshInstance3D", true, false)
	# 4 screens + 3 bezels + dashboard
	if meshes.size() < 8:
		print("FAIL _test_cockpit_meshes_are_on_cockpit_layer_without_shadows: only %d meshes, expected at least 8" % meshes.size())
		result = 1
	for mesh in meshes:
		var instance: MeshInstance3D = mesh
		if instance.layers != 2:
			print("FAIL _test_cockpit_meshes_are_on_cockpit_layer_without_shadows: %s layers=%d expected 2" % [instance.name, instance.layers])
			result = 1
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			print("FAIL _test_cockpit_meshes_are_on_cockpit_layer_without_shadows: %s casts shadows" % instance.name)
			result = 1
	cockpit.free()
	return result

func _test_side_screens_touch_the_front_screen_edges() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var front: MeshInstance3D = cockpit.get_node("FrontScreen")
	var front_half_width: float = (front.mesh as QuadMesh).size.x * 0.5
	for side in [-1.0, 1.0]:
		var screen: MeshInstance3D = cockpit.get_node("LeftScreen" if side < 0.0 else "RightScreen")
		var half_width: float = (screen.mesh as QuadMesh).size.x * 0.5
		var inner_edge: Vector3 = screen.transform * Vector3(-side * half_width, 0.0, 0.0)
		var front_edge: Vector3 = front.transform * Vector3(side * front_half_width, 0.0, 0.0)
		if not inner_edge.is_equal_approx(front_edge):
			print("FAIL _test_side_screens_touch_the_front_screen_edges: %s inner edge=%s front edge=%s" % [screen.name, inner_edge, front_edge])
			result = 1
	cockpit.free()
	return result

func _test_hud_screen_sits_below_and_faces_the_pilot() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var hud: MeshInstance3D = cockpit.get_node("HudScreen")
	var to_eye: Vector3 = Vector3.ZERO - hud.position
	if hud.position.y >= 0.0:
		print("FAIL _test_hud_screen_sits_below_and_faces_the_pilot: position=%s expected below eye level" % hud.position)
		result = 1
	if hud.transform.basis.z.dot(to_eye) <= 0.0 or hud.transform.basis.z.y <= 0.0:
		print("FAIL _test_hud_screen_sits_below_and_faces_the_pilot: normal=%s must face the eye and tilt up" % hud.transform.basis.z)
		result = 1
	cockpit.free()
	return result

func _test_hud_lines_in_display_order() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var lines := cockpit.get_node("HudViewport/Lines")
	var names: Array = []
	for child in lines.get_children():
		names.append(String(child.name))
	var expected := ["SpeedLabel", "BowLabel", "SternLabel", "PortLabel", "StarboardLabel", "DorsalLabel", "VentralLabel"]
	if names != expected:
		print("FAIL _test_hud_lines_in_display_order: %s expected %s" % [names, expected])
		result = 1
	cockpit.free()
	return result

func _test_update_hud_writes_speed_and_distances() -> int:
	var cockpit := _make_cockpit()
	cockpit.update_hud(1240.4, {"bow": 819.6, "stern": -1.0, "port": 3140.0, "starboard": -1.0, "dorsal": 410.0, "ventral": -1.0})
	var result := 0
	var expected := {
		"SpeedLabel": "VEL  1240 m/s",
		"BowLabel": "PRUA  820 m",
		"SternLabel": "POPPA  —",
		"PortLabel": "SX  3.1 km",
		"StarboardLabel": "DX  —",
		"DorsalLabel": "DORSO  410 m",
		"VentralLabel": "VENTRE  —",
	}
	for label_name in expected:
		var label: Label = cockpit.get_node("HudViewport/Lines/" + label_name)
		if label.text != expected[label_name]:
			print("FAIL _test_update_hud_writes_speed_and_distances: %s='%s' expected '%s'" % [label_name, label.text, expected[label_name]])
			result = 1
	cockpit.free()
	return result

func _test_update_hud_missing_distances_show_no_reading() -> int:
	var cockpit := _make_cockpit()
	cockpit.update_hud(0.0, {})
	var result := 0
	var label: Label = cockpit.get_node("HudViewport/Lines/BowLabel")
	if label.text != "PRUA  —":
		print("FAIL _test_update_hud_missing_distances_show_no_reading: BowLabel='%s' expected 'PRUA  —'" % label.text)
		result = 1
	cockpit.free()
	return result
```

- [ ] **Step 2: Write the failing in-tree tests**

Create `tests/test_cockpit_in_tree.gd`:

```gdscript
extends SceneTree

# A SubViewport breaks the 3D transform chain, so the exterior cameras only
# follow the ship through their RemoteTransform3D mounts, which update only
# inside a processed tree. Off-tree tests cannot see this.

const CockpitScript = preload("res://scripts/cockpit.gd")

var _failures := 0

func _initialize():
	await process_frame

	_failures += await _test_exterior_cameras_follow_the_pilot_eye()
	_failures += await _test_side_cameras_look_sixty_degrees_off_the_bow()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_moved_ship_with_cockpit() -> Array:
	var ship := Node3D.new()
	root.add_child(ship)
	var cockpit: Node3D = CockpitScript.new()
	cockpit.position = Vector3(0.0, 0.5, -8.0)
	ship.add_child(cockpit)
	cockpit.build()
	# Move and turn the ship after the cockpit is built, as flight (and a
	# world-origin rebase) does.
	ship.position = Vector3(100.0, 20.0, -300.0)
	ship.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	return [ship, cockpit]

func _test_exterior_cameras_follow_the_pilot_eye() -> int:
	var nodes := _make_moved_ship_with_cockpit()
	var ship: Node3D = nodes[0]
	var cockpit: Node3D = nodes[1]
	await process_frame
	await physics_frame
	var result := 0
	for prefix in ["Front", "Left", "Right"]:
		var camera: Camera3D = cockpit.get_node("%sViewport/Camera" % prefix)
		if not camera.global_transform.origin.is_equal_approx(cockpit.global_transform.origin):
			print("FAIL _test_exterior_cameras_follow_the_pilot_eye: %s camera at %s, eye at %s" % [prefix, camera.global_transform.origin, cockpit.global_transform.origin])
			result = 1
	ship.free()
	return result

func _test_side_cameras_look_sixty_degrees_off_the_bow() -> int:
	var nodes := _make_moved_ship_with_cockpit()
	var ship: Node3D = nodes[0]
	var cockpit: Node3D = nodes[1]
	await process_frame
	await physics_frame
	var ship_forward: Vector3 = -ship.global_transform.basis.z
	var ship_left: Vector3 = -ship.global_transform.basis.x
	var sin_60: float = sin(deg_to_rad(60.0))
	# prefix: [expected dot with ship forward, expected dot with ship left]
	var expected := {"Front": [1.0, 0.0], "Left": [0.5, sin_60], "Right": [0.5, -sin_60]}
	var result := 0
	for prefix in expected:
		var camera: Camera3D = cockpit.get_node("%sViewport/Camera" % prefix)
		var looks: Vector3 = -camera.global_transform.basis.z
		if not is_equal_approx(looks.dot(ship_forward), expected[prefix][0]) or not is_equal_approx(looks.dot(ship_left), expected[prefix][1]):
			print("FAIL _test_side_cameras_look_sixty_degrees_off_the_bow: %s looks %s (forward·=%f left·=%f) expected forward·=%f left·=%f" % [prefix, looks, looks.dot(ship_forward), looks.dot(ship_left), expected[prefix][0], expected[prefix][1]])
			result = 1
	ship.free()
	return result
```

- [ ] **Step 3: Run both to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd`
Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit_in_tree.gd`
Expected (both): a load/parse error for `res://scripts/cockpit.gd`.

- [ ] **Step 4: Implement**

Create `scripts/cockpit.gd`:

```gdscript
extends Node3D

const CockpitLayout = preload("res://scripts/cockpit_layout.gd")
const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

# Visual layers (bit values). The pilot camera sees only the cockpit; the
# exterior cameras see the world but neither the cockpit nor the ship's own
# exterior markers.
const COCKPIT_LAYER := 2
const SHIP_EXTERIOR_LAYER := 4
const ALL_LAYERS := 0xFFFFF
const EXTERIOR_CAMERA_CULL_MASK := ALL_LAYERS & ~(COCKPIT_LAYER | SHIP_EXTERIOR_LAYER)

const SCREEN_DISTANCE := 1.6
const CENTER_SCREEN_SIZE := Vector2(1.6, 0.9)
const SIDE_SCREEN_SIZE := Vector2(0.9, 0.50625)
const SIDE_SCREEN_TILT := 30.0
const CENTER_VIEWPORT_SIZE := Vector2i(1280, 720)
const SIDE_VIEWPORT_SIZE := Vector2i(960, 540)
const BEZEL_MARGIN := 0.03
const BEZEL_DEPTH := 0.04

const HUD_SCREEN_SIZE := Vector2(0.8, 0.5)
const HUD_SCREEN_POSITION := Vector3(0.0, -0.72, -1.3)
const HUD_SCREEN_PITCH := -30.0
const HUD_VIEWPORT_SIZE := Vector2i(512, 320)
const HUD_FONT_SIZE := 28
const HUD_TEXT_COLOR := Color(0.4, 0.95, 1.0)
const HUD_BACKGROUND_COLOR := Color(0.02, 0.05, 0.08)

const DASHBOARD_SIZE := Vector3(2.4, 0.06, 0.8)
const DASHBOARD_POSITION := Vector3(0.0, -1.02, -1.3)
const FRAME_COLOR := Color(0.08, 0.09, 0.1)

const PILOT_FOV := 80.0
const PILOT_NEAR := 0.05
const PILOT_FAR := 10.0
# Horizontal FOV (keep_aspect = KEEP_WIDTH): the side cameras turn by exactly
# this much, so the three images join into one panorama.
const EXTERIOR_CAMERA_HFOV := 60.0
# The eye sits 7 m behind the bow face: a larger near plane would clip a
# surface touching the bow.
const EXTERIOR_CAMERA_NEAR := 2.0
const EXTERIOR_CAMERA_FAR := 69496000.0

# distance key -> [label node name, HUD prefix], in display order.
const DISTANCE_LABELS := {
	"bow": ["BowLabel", "PRUA"],
	"stern": ["SternLabel", "POPPA"],
	"port": ["PortLabel", "SX"],
	"starboard": ["StarboardLabel", "DX"],
	"dorsal": ["DorsalLabel", "DORSO"],
	"ventral": ["VentralLabel", "VENTRE"],
}

var _frame_material: StandardMaterial3D

func build() -> void:
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = FRAME_COLOR
	_frame_material.roughness = 0.6
	_frame_material.metallic = 0.3

	_build_pilot_camera()
	_build_cockpit_light()
	_build_exterior_screen("Front", CENTER_SCREEN_SIZE, CENTER_VIEWPORT_SIZE,
		Transform3D(Basis(), Vector3(0.0, 0.0, -SCREEN_DISTANCE)), 0.0)
	for side in [-1.0, 1.0]:
		_build_exterior_screen("Left" if side < 0.0 else "Right", SIDE_SCREEN_SIZE, SIDE_VIEWPORT_SIZE,
			CockpitLayout.compute_side_screen_transform(CENTER_SCREEN_SIZE.x, SIDE_SCREEN_SIZE.x, SCREEN_DISTANCE, SIDE_SCREEN_TILT, side),
			CockpitLayout.compute_side_camera_yaw_degrees(EXTERIOR_CAMERA_HFOV, side))
	_build_dashboard()
	_build_hud()

func update_hud(speed: float, distances: Dictionary) -> void:
	var lines := get_node("HudViewport/Lines")
	(lines.get_node("SpeedLabel") as Label).text = "VEL  " + CockpitHudFormat.format_speed(speed)
	for key in DISTANCE_LABELS:
		var entry: Array = DISTANCE_LABELS[key]
		var distance: float = distances.get(key, -1.0)
		(lines.get_node(entry[0]) as Label).text = "%s  %s" % [entry[1], CockpitHudFormat.format_distance(distance)]

func _build_pilot_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "PilotCamera"
	camera.fov = PILOT_FOV
	camera.near = PILOT_NEAR
	camera.far = PILOT_FAR
	camera.cull_mask = COCKPIT_LAYER
	camera.current = true
	add_child(camera)

func _build_cockpit_light() -> void:
	var light := OmniLight3D.new()
	light.name = "CockpitLight"
	light.light_cull_mask = COCKPIT_LAYER
	light.light_color = Color(1.0, 0.85, 0.7)
	light.light_energy = 0.6
	light.omni_range = 4.0
	light.position = Vector3(0.0, 0.6, -0.8)
	add_child(light)

func _build_exterior_screen(prefix: String, screen_size: Vector2, viewport_size: Vector2i, screen_transform: Transform3D, camera_yaw_degrees: float) -> void:
	var viewport := SubViewport.new()
	viewport.name = prefix + "Viewport"
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = EXTERIOR_CAMERA_HFOV
	camera.near = EXTERIOR_CAMERA_NEAR
	camera.far = EXTERIOR_CAMERA_FAR
	camera.cull_mask = EXTERIOR_CAMERA_CULL_MASK
	camera.current = true
	viewport.add_child(camera)

	# A camera under a SubViewport does not inherit the ship's transform;
	# the mount (a child of the cockpit, so of the ship) pushes it.
	var mount := RemoteTransform3D.new()
	mount.name = prefix + "CameraMount"
	mount.rotation_degrees = Vector3(0.0, camera_yaw_degrees, 0.0)
	add_child(mount)
	mount.remote_path = mount.get_path_to(camera)

	var screen := _make_screen(prefix + "Screen", screen_size, viewport)
	screen.transform = screen_transform
	add_child(screen)

	var bezel := MeshInstance3D.new()
	bezel.name = "Bezel"
	var bezel_mesh := BoxMesh.new()
	bezel_mesh.size = Vector3(screen_size.x + BEZEL_MARGIN * 2.0, screen_size.y + BEZEL_MARGIN * 2.0, BEZEL_DEPTH)
	bezel.mesh = bezel_mesh
	bezel.material_override = _frame_material
	bezel.position = Vector3(0.0, 0.0, -BEZEL_DEPTH * 0.5 - 0.005)
	_put_on_cockpit_layer(bezel)
	screen.add_child(bezel)

func _build_dashboard() -> void:
	var dashboard := MeshInstance3D.new()
	dashboard.name = "Dashboard"
	var box := BoxMesh.new()
	box.size = DASHBOARD_SIZE
	dashboard.mesh = box
	dashboard.material_override = _frame_material
	dashboard.position = DASHBOARD_POSITION
	_put_on_cockpit_layer(dashboard)
	add_child(dashboard)

func _build_hud() -> void:
	var viewport := SubViewport.new()
	viewport.name = "HudViewport"
	viewport.size = HUD_VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = HUD_BACKGROUND_COLOR
	background.size = Vector2(HUD_VIEWPORT_SIZE)
	viewport.add_child(background)

	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.position = Vector2(24.0, 12.0)
	viewport.add_child(lines)

	var label_settings := LabelSettings.new()
	label_settings.font_size = HUD_FONT_SIZE
	label_settings.font_color = HUD_TEXT_COLOR
	_add_hud_label(lines, "SpeedLabel", label_settings)
	for key in DISTANCE_LABELS:
		_add_hud_label(lines, DISTANCE_LABELS[key][0], label_settings)

	var screen := _make_screen("HudScreen", HUD_SCREEN_SIZE, viewport)
	screen.position = HUD_SCREEN_POSITION
	screen.rotation_degrees = Vector3(HUD_SCREEN_PITCH, 0.0, 0.0)
	add_child(screen)

	update_hud(0.0, {})

func _add_hud_label(parent: Node, label_name: String, label_settings: LabelSettings) -> void:
	var label := Label.new()
	label.name = label_name
	label.label_settings = label_settings
	parent.add_child(label)

func _make_screen(screen_name: String, screen_size: Vector2, viewport: SubViewport) -> MeshInstance3D:
	var screen := MeshInstance3D.new()
	screen.name = screen_name
	var quad := QuadMesh.new()
	quad.size = screen_size
	screen.mesh = quad
	# Unshaded: the screen shows the camera image as-is, unaffected by lights.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	_put_on_cockpit_layer(screen)
	return screen

func _put_on_cockpit_layer(mesh: GeometryInstance3D) -> void:
	mesh.layers = COCKPIT_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
```

- [ ] **Step 5: Run to verify they pass**

Run the two commands from Step 3. Expected: `ALL TESTS PASSED` for both.

- [ ] **Step 6: Full suite**

Run the full suite command. Expected: every file `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add scripts/cockpit.gd tests/test_cockpit.gd tests/test_cockpit_in_tree.gd
git commit -m "$(cat <<'EOF'
Add procedural cockpit: three panorama camera screens and HUD panel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(Add the new `.uid` files if created.)

---

### Task 5: Mount the cockpit on the ship, drop the chase camera

**Files:**
- Modify: `scripts/void_cruiser.gd` (preload, constant, `_ready`, `_process`, `_add_nav_light`, new `build_cockpit`)
- Modify: `tests/test_void_cruiser.gd` (failures list + three new tests)
- Modify: `scenes/torus1_system.tscn` (remove `ChaseCamera`)
- Modify: `tests/test_scene_wiring.gd`

**Interfaces:**
- Consumes: `CockpitScript` (`build()`, `update_hud(speed, distances)`, `SHIP_EXTERIOR_LAYER`) from Task 4; `read_proximity_distances()` from Task 3.
- Produces: `const COCKPIT_POSITION := Vector3(0.0, 0.5, -8.0)`, `func build_cockpit() -> void` (child named `Cockpit`).

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser.gd`, add to the failures list right after `failures += _test_read_proximity_distances_off_tree_reports_no_hit()`:

```gdscript
	failures += _test_build_cockpit_adds_cockpit_at_pilot_eye()
	failures += _test_process_shows_ship_speed_on_hud()
	failures += _test_nav_light_markers_hidden_from_onboard_cameras()
```

Append at the end of the file:

```gdscript
func _test_build_cockpit_adds_cockpit_at_pilot_eye() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_cockpit()
	var result := 0
	var cockpit := cruiser.get_node_or_null("Cockpit")
	if cockpit == null:
		print("FAIL _test_build_cockpit_adds_cockpit_at_pilot_eye: no Cockpit child")
		result = 1
	else:
		if not (cockpit as Node3D).position.is_equal_approx(Vector3(0.0, 0.5, -8.0)):
			print("FAIL _test_build_cockpit_adds_cockpit_at_pilot_eye: position=%s expected (0, 0.5, -8)" % (cockpit as Node3D).position)
			result = 1
		if cockpit.get_node_or_null("PilotCamera") == null:
			print("FAIL _test_build_cockpit_adds_cockpit_at_pilot_eye: Cockpit was not built (no PilotCamera)")
			result = 1
	cruiser.free()
	return result

func _test_process_shows_ship_speed_on_hud() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser.velocity = Vector3(30.0, 0.0, -40.0)
	cruiser._process(0.016)
	var result := 0
	var speed_label: Label = cruiser.get_node("Cockpit/HudViewport/Lines/SpeedLabel")
	if speed_label.text != "VEL  50 m/s":
		print("FAIL _test_process_shows_ship_speed_on_hud: SpeedLabel='%s' expected 'VEL  50 m/s'" % speed_label.text)
		result = 1
	var bow_label: Label = cruiser.get_node("Cockpit/HudViewport/Lines/BowLabel")
	if bow_label.text != "PRUA  —":
		print("FAIL _test_process_shows_ship_speed_on_hud: BowLabel='%s' expected 'PRUA  —' (off-tree: no hit)" % bow_label.text)
		result = 1
	cruiser.free()
	return result

func _test_nav_light_markers_hidden_from_onboard_cameras() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_navigation_lights()
	var result := 0
	for light_name in ["PortLight", "StarboardLight", "TailLight"]:
		var marker: MeshInstance3D = cruiser.get_node("%s/Marker" % light_name)
		if marker.layers != 4:
			print("FAIL _test_nav_light_markers_hidden_from_onboard_cameras: %s marker layers=%d expected 4 (SHIP_EXTERIOR_LAYER)" % [light_name, marker.layers])
			result = 1
	cruiser.free()
	return result
```

In `tests/test_scene_wiring.gd`, right after the block

```gdscript
	elif not (void_cruiser as Node3D).position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_scene_wiring: VoidCruiser position=%s" % (void_cruiser as Node3D).position)
		result = 1
```

add:

```gdscript
	if void_cruiser != null and void_cruiser.get_node_or_null("ChaseCamera") != null:
		print("FAIL _test_scene_wiring: VoidCruiser still has a ChaseCamera; the view is now the cockpit's PilotCamera, built by void_cruiser.gd")
		result = 1
```

and right after the existing `TopDownCamera missing` check (inside `if planet_system != null:`), add:

```gdscript
		var top_down := planet_system.get_node_or_null("TopDownCamera") as Camera3D
		if top_down != null and top_down.current:
			print("FAIL _test_scene_wiring: TopDownCamera is current; it would compete with the cockpit's PilotCamera")
			result = 1
```

(The `TopDownCamera` check already passes: it guards Review Focus item 5.)

- [ ] **Step 2: Run to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd`
Expected: `SCRIPT ERROR: ... Nonexistent function 'build_cockpit'` (twice) and `FAIL _test_nav_light_markers_hidden_from_onboard_cameras: ... layers=1 expected 4` (three lines).

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd`
Expected: `FAIL _test_scene_wiring: VoidCruiser still has a ChaseCamera ...`.

- [ ] **Step 3: Implement**

In `scripts/void_cruiser.gd`:

After `const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")` add:

```gdscript
const CockpitScript = preload("res://scripts/cockpit.gd")
```

After the `SENSOR_DIRECTIONS` constant add:

```gdscript
# The pilot's eye, inside the hull box, 7 m behind the bow face.
const COCKPIT_POSITION := Vector3(0.0, 0.5, -8.0)
```

In `_ready()`, add `build_cockpit()` right after `build_headlights()`.

At the end of `_process(delta)` (after the tail-light strobe lines) add:

```gdscript
	var cockpit := get_node_or_null("Cockpit")
	if cockpit:
		cockpit.update_hud(velocity.length(), read_proximity_distances())
```

In `_add_nav_light(...)`, right before `light.add_child(marker)`, add:

```gdscript
	# The markers are for outside observers; keep them out of the on-board cameras.
	marker.layers = CockpitScript.SHIP_EXTERIOR_LAYER
```

Add after `read_proximity_distances()`:

```gdscript
func build_cockpit() -> void:
	var cockpit: Node3D = CockpitScript.new()
	cockpit.name = "Cockpit"
	cockpit.position = COCKPIT_POSITION
	add_child(cockpit)
	cockpit.build()
```

In `scenes/torus1_system.tscn`, delete this node block (and the blank line after it):

```
[node name="ChaseCamera" type="Camera3D" parent="VoidCruiser" unique_id=583786054]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 37.5, 112.5)
current = true
near = 10.0
far = 69496000.0
```

- [ ] **Step 4: Run to verify they pass**

Run the two commands from Step 2. Expected: `ALL TESTS PASSED` for both.

- [ ] **Step 5: Full suite**

Run the full suite command. Expected: every file `ALL TESTS PASSED` (including `test_proximity_sensors_physics.gd`, whose in-tree cruiser now also builds a cockpit in `_ready`).

- [ ] **Step 6: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd scenes/torus1_system.tscn tests/test_scene_wiring.gd
git commit -m "$(cat <<'EOF'
Mount the cockpit on the void cruiser and drop the chase camera

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Remove the ship model

**Files:**
- Modify: `scripts/void_cruiser.gd` (remove `SHIP_MODEL_PATH`, `build_ship_mesh()` and its call)
- Modify: `tests/test_void_cruiser.gd` (remove two tests, add one)
- Delete: `assets/models/void_cruiser.glb`, `assets/models/void_cruiser.glb.import`

**Interfaces:**
- Consumes: nothing new.
- Produces: `VoidCruiser` without `build_ship_mesh`.

- [ ] **Step 1: Write the failing test and drop the obsolete ones**

In `tests/test_void_cruiser.gd`:
- Remove the lines `failures += _test_build_ship_mesh_adds_visible_mesh()` and `failures += _test_ship_model_faces_forward()` from the failures list, and delete the two functions `_test_build_ship_mesh_adds_visible_mesh` and `_test_ship_model_faces_forward`.
- Add `failures += _test_ship_model_is_gone()` after `failures += _test_nav_light_markers_hidden_from_onboard_cameras()`.
- Append:

```gdscript
func _test_ship_model_is_gone() -> int:
	# First-person cockpit: the ship has no exterior model any more.
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.has_method("build_ship_mesh"):
		print("FAIL _test_ship_model_is_gone: void_cruiser.gd still has build_ship_mesh()")
		result = 1
	for path in ["res://assets/models/void_cruiser.glb", "res://assets/models/void_cruiser.glb.import"]:
		if FileAccess.file_exists(path):
			print("FAIL _test_ship_model_is_gone: %s still exists" % path)
			result = 1
	cruiser.free()
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd`
Expected: three `FAIL _test_ship_model_is_gone` lines (method + two files).

- [ ] **Step 3: Implement**

In `scripts/void_cruiser.gd`:
- Delete the line `const SHIP_MODEL_PATH := "res://assets/models/void_cruiser.glb"`.
- Delete the line `build_ship_mesh()` from `_ready()`.
- Delete the whole `build_ship_mesh()` function including its comment block.

Then:

```bash
git rm assets/models/void_cruiser.glb assets/models/void_cruiser.glb.import
```

`_ready()` must now read:

```gdscript
func _ready() -> void:
	build_collision_shape()
	build_proximity_sensors()
	build_navigation_lights()
	build_headlights()
	build_cockpit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
```

- [ ] **Step 4: Run to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd`
Expected: `ALL TESTS PASSED`.

Also confirm nothing else references the model:
`grep -rn "void_cruiser.glb\|build_ship_mesh\|ShipModel" scripts tests scenes`
Expected: only the `_test_ship_model_is_gone` lines in `tests/test_void_cruiser.gd`.

- [ ] **Step 5: Full suite**

Run the full suite command. Expected: every file `ALL TESTS PASSED`.

- [ ] **Step 6: Live check**

Via Godot MCP: `mcp__godot__run_project` (projectPath = the worktree root), then `mcp__godot__get_debug_output`, then `mcp__godot__stop_project`.
Expected: no errors besides the three known lines (`libX11.so.6: undefined symbol: XSetIOErrorExitHandler`, two `libxkbcommon.so.0` lines).

- [ ] **Step 7: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd
git commit -m "$(cat <<'EOF'
Remove the exterior ship model: the view is now the cockpit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

(The `git rm` from Step 3 is already staged and lands in this commit.)

---

## Manual verification (user, in game)

The Godot MCP cannot take screenshots. After the final review, ask the user to check in game:

1. The three screens show the outside; the image continues across the screen edges (panorama).
2. Screen colors look like the old chase view. If washed out or too dark: set `material.albedo_texture_force_srgb = true` in `cockpit.gd`'s `_make_screen` (one line) and re-check.
3. The HUD is readable; speed changes with thrust; distances appear near the station and show `—` in open space.
4. No red/green/white marker spheres visible on the side screens.
5. Frame rate acceptable. If not: lower `SIDE_VIEWPORT_SIZE`.
