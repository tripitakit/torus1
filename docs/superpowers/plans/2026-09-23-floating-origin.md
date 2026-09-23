# Floating Origin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the GPU float32-precision jitter on the void-cruiser mesh by periodically re-centering the scene's local coordinate space on the ship (floating origin / origin shifting), instead of keeping planet and station at a fixed position millions of meters from the void-cruiser.

**Architecture:** Group `Planet`, `TorusStation`, and `TopDownCamera` under one new `PlanetSystem` node so they can be shifted as a rigid unit. Flip the scene's initial layout so `VoidCruiser` starts at local `(0,0,0)` and `PlanetSystem` carries the large offset. A new lightweight `WorldOriginRebase` node checks every physics tick whether `VoidCruiser` has drifted past a distance threshold from local origin; if so, it subtracts that offset from both `VoidCruiser.position` and `PlanetSystem.position`, which preserves every relative position exactly (rigid shift) while keeping numbers small near the camera.

**Tech Stack:** Godot 4.6.1 (double-precision build at `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`), GDScript. Headless tests run via `<godot binary> --headless --path . --script tests/<file>.gd` and are expected to print `ALL TESTS PASSED`. Live scene checks run via the `mcp__godot__run_project` / `mcp__godot__get_debug_output` / `mcp__godot__stop_project` MCP tools.

**Spec:** `docs/superpowers/specs/2026-09-23-floating-origin-design.md`

## Global Constraints

- Rebase threshold: `5000.0` (meters, local-space distance from origin that triggers a rebase)
- `VoidCruiser` initial local position: `(0, 0, 0)`
- `PlanetSystem` initial local position: `(0, -4000, -6959600)` (preserves the previously-approved ship-relative-to-planet offset of `(0, 4000, 6959600)`)
- No absolute-position accumulator is implemented — nothing in the codebase consumes a "true" world position today (per spec's YAGNI note)
- `Planet`, `TorusStation`, `TopDownCamera` become children of `PlanetSystem`; `VoidCruiser`, `SunLight`, `WorldOriginRebase` stay direct children of `root`
- New scripts follow the codebase's existing pattern: pure static functions in a `RefCounted` script, tested directly; a thin `Node`/`Node3D` wrapper that calls them, exercised via its own callable method (not only through `_process`/`_physics_process`)

## Review Focus

- Real `.tscn` wiring (node names, parent paths, exported `NodePath` strings) is never checked by any existing headless test — they all build node trees by hand in script, bypassing the scene file. A typo in `tracked_node`/`rebasing_node` would make `_check_and_rebase()` silently no-op (by design, see Task 2's missing-node test) and silently reintroduce the original jitter bug with zero diagnostic signal. Task 3 closes this with a test that loads the actual packed scene.
- `rebase_threshold` of exactly `0.0` or negative (misconfiguration) would make `should_rebase` true for almost any nonzero position, causing a rebase most ticks — not user-facing input, but worth a boundary test so behavior is defined, not accidental.
- Boundary case where `tracked_position.length()` is exactly equal to the threshold — must not rebase (`>`, not `>=`), otherwise a ship sitting exactly at the threshold could oscillate.
- `TorusStation`'s `planet_node = NodePath("../Planet")` must still resolve correctly after both `TorusStation` and `Planet` move one level deeper (from children of `root` to children of `PlanetSystem`) — the path is relative and both stay siblings, so it should be unaffected, but this is exactly the kind of reparenting change that silently breaks a relative `NodePath` if done carelessly. Covered by Task 3's scene-wiring test, which resolves `TorusStation.planet_node` against the real loaded scene and asserts it points at the real `Planet` instance.
- Existing camera `near`/`far` values were tuned against the old scene layout (ship far from origin, planet at origin). After the flip, distances between camera and rendered geometry are unchanged (rigid shift preserves relative positions), so no camera value should need to change — but Task 3 re-runs the project via MCP to confirm no new `prepare_camera` or other runtime errors appear.

---

### Task 1: `world_rebase.gd` — pure rebase math

**Files:**
- Create: `scripts/world_rebase.gd`
- Test: `tests/test_world_rebase.gd`

**Interfaces:**
- Produces: `WorldRebase.should_rebase(tracked_position: Vector3, threshold: float) -> bool`, `WorldRebase.compute_rebase_offset(tracked_position: Vector3) -> Vector3` (static methods on a `RefCounted` script at `res://scripts/world_rebase.gd`)

- [ ] **Step 1: Write the failing test**

Create `tests/test_world_rebase.gd`:

```gdscript
extends SceneTree

const WorldRebase = preload("res://scripts/world_rebase.gd")

func _init():
	var failures := 0
	failures += _test_should_rebase_false_under_threshold()
	failures += _test_should_rebase_true_over_threshold()
	failures += _test_should_rebase_boundary_is_false()
	failures += _test_should_rebase_zero_threshold()
	failures += _test_compute_rebase_offset_returns_position()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_should_rebase_false_under_threshold() -> int:
	var result := WorldRebase.should_rebase(Vector3(100.0, 0.0, 0.0), 5000.0)
	if result:
		print("FAIL _test_should_rebase_false_under_threshold: expected false, got true")
		return 1
	return 0

func _test_should_rebase_true_over_threshold() -> int:
	var result := WorldRebase.should_rebase(Vector3(6000.0, 0.0, 0.0), 5000.0)
	if not result:
		print("FAIL _test_should_rebase_true_over_threshold: expected true, got false")
		return 1
	return 0

func _test_should_rebase_boundary_is_false() -> int:
	var result := WorldRebase.should_rebase(Vector3(5000.0, 0.0, 0.0), 5000.0)
	if result:
		print("FAIL _test_should_rebase_boundary_is_false: expected false at exact threshold, got true")
		return 1
	return 0

func _test_should_rebase_zero_threshold() -> int:
	var result := WorldRebase.should_rebase(Vector3(0.001, 0.0, 0.0), 0.0)
	if not result:
		print("FAIL _test_should_rebase_zero_threshold: expected true for any nonzero position with threshold 0")
		return 1
	return 0

func _test_compute_rebase_offset_returns_position() -> int:
	var position := Vector3(123.0, -45.0, 6789.0)
	var offset := WorldRebase.compute_rebase_offset(position)
	if not offset.is_equal_approx(position):
		print("FAIL _test_compute_rebase_offset_returns_position: offset=%s expected=%s" % [offset, position])
		return 1
	return 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_world_rebase.gd`
Expected: fails to load, error mentioning `res://scripts/world_rebase.gd` not found (the `preload` fails because the file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/world_rebase.gd`:

```gdscript
extends RefCounted

static func should_rebase(tracked_position: Vector3, threshold: float) -> bool:
	return tracked_position.length() > threshold

static func compute_rebase_offset(tracked_position: Vector3) -> Vector3:
	return tracked_position
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_world_rebase.gd`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add scripts/world_rebase.gd tests/test_world_rebase.gd
git commit -m "Add pure rebase-threshold math for floating origin"
```

---

### Task 2: `world_origin_rebase.gd` — thin node wrapper

**Files:**
- Create: `scripts/world_origin_rebase.gd`
- Test: `tests/test_world_origin_rebase.gd`

**Interfaces:**
- Consumes: `WorldRebase.should_rebase(Vector3, float) -> bool`, `WorldRebase.compute_rebase_offset(Vector3) -> Vector3` from Task 1
- Produces: `WorldOriginRebase` node script at `res://scripts/world_origin_rebase.gd` (`extends Node`), exported `tracked_node: NodePath`, `rebasing_node: NodePath`, `rebase_threshold: float = 5000.0`, method `_check_and_rebase() -> void`

- [ ] **Step 1: Write the failing test**

Create `tests/test_world_origin_rebase.gd`:

```gdscript
extends SceneTree

const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

func _init():
	var failures := 0
	failures += _test_no_rebase_under_threshold()
	failures += _test_rebase_shifts_both_nodes_over_threshold()
	failures += _test_missing_nodes_does_not_crash()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_rebase_node(tracked_position: Vector3, threshold: float) -> Dictionary:
	var rebase: Node = WorldOriginRebaseScript.new()
	var tracked := Node3D.new()
	tracked.name = "Tracked"
	tracked.position = tracked_position
	var rebasing := Node3D.new()
	rebasing.name = "Rebasing"
	rebasing.position = Vector3(10.0, 20.0, 30.0)
	rebase.add_child(tracked)
	rebase.add_child(rebasing)
	rebase.tracked_node = NodePath("Tracked")
	rebase.rebasing_node = NodePath("Rebasing")
	rebase.rebase_threshold = threshold
	return {"rebase": rebase, "tracked": tracked, "rebasing": rebasing}

func _test_no_rebase_under_threshold() -> int:
	var nodes := _make_rebase_node(Vector3(100.0, 0.0, 0.0), 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var rebasing: Node3D = nodes["rebasing"]
	rebase._check_and_rebase()
	var result := 0
	if not tracked.position.is_equal_approx(Vector3(100.0, 0.0, 0.0)):
		print("FAIL _test_no_rebase_under_threshold: tracked moved to %s" % tracked.position)
		result = 1
	if not rebasing.position.is_equal_approx(Vector3(10.0, 20.0, 30.0)):
		print("FAIL _test_no_rebase_under_threshold: rebasing moved to %s" % rebasing.position)
		result = 1
	rebase.free()
	return result

func _test_rebase_shifts_both_nodes_over_threshold() -> int:
	var tracked_start := Vector3(6000.0, 0.0, 0.0)
	var rebasing_start := Vector3(10.0, 20.0, 30.0)
	var nodes := _make_rebase_node(tracked_start, 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var rebasing: Node3D = nodes["rebasing"]
	rebase._check_and_rebase()
	var result := 0
	if not tracked.position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_rebase_shifts_both_nodes_over_threshold: tracked=%s expected ZERO" % tracked.position)
		result = 1
	var expected_rebasing := rebasing_start - tracked_start
	if not rebasing.position.is_equal_approx(expected_rebasing):
		print("FAIL _test_rebase_shifts_both_nodes_over_threshold: rebasing=%s expected=%s" % [rebasing.position, expected_rebasing])
		result = 1
	rebase.free()
	return result

func _test_missing_nodes_does_not_crash() -> int:
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.tracked_node = NodePath("DoesNotExist")
	rebase.rebasing_node = NodePath("AlsoMissing")
	rebase.rebase_threshold = 5000.0
	rebase._check_and_rebase()
	rebase.free()
	return 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_world_origin_rebase.gd`
Expected: fails to load, error mentioning `res://scripts/world_origin_rebase.gd` not found.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/world_origin_rebase.gd`:

```gdscript
extends Node

const WorldRebase = preload("res://scripts/world_rebase.gd")

@export var tracked_node: NodePath
@export var rebasing_node: NodePath
@export var rebase_threshold: float = 5000.0

func _physics_process(_delta: float) -> void:
	_check_and_rebase()

func _check_and_rebase() -> void:
	var tracked := get_node_or_null(tracked_node) as Node3D
	var rebasing := get_node_or_null(rebasing_node) as Node3D
	if tracked == null or rebasing == null:
		return
	if not WorldRebase.should_rebase(tracked.position, rebase_threshold):
		return
	var offset := WorldRebase.compute_rebase_offset(tracked.position)
	tracked.position -= offset
	rebasing.position -= offset
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_world_origin_rebase.gd`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add scripts/world_origin_rebase.gd tests/test_world_origin_rebase.gd
git commit -m "Add WorldOriginRebase node that shifts tracked+rebasing nodes on drift"
```

---

### Task 3: Wire floating origin into the scene

**Files:**
- Modify: `scenes/torus1_system.tscn`
- Test: `tests/test_scene_wiring.gd`

**Interfaces:**
- Consumes: `WorldOriginRebase` script and its exported properties from Task 2

- [ ] **Step 1: Write the failing scene-wiring test**

Create `tests/test_scene_wiring.gd`:

```gdscript
extends SceneTree

func _init():
	var failures := 0
	failures += _test_scene_wiring()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_scene_wiring() -> int:
	var packed: PackedScene = load("res://scenes/torus1_system.tscn")
	var scene: Node3D = packed.instantiate()
	var result := 0

	var planet_system := scene.get_node_or_null("PlanetSystem")
	var void_cruiser := scene.get_node_or_null("VoidCruiser")
	var rebase := scene.get_node_or_null("WorldOriginRebase")

	if planet_system == null:
		print("FAIL _test_scene_wiring: PlanetSystem node missing")
		result = 1
	elif not (planet_system as Node3D).position.is_equal_approx(Vector3(0.0, -4000.0, -6959600.0)):
		print("FAIL _test_scene_wiring: PlanetSystem position=%s" % (planet_system as Node3D).position)
		result = 1

	if void_cruiser == null:
		print("FAIL _test_scene_wiring: VoidCruiser node missing")
		result = 1
	elif not (void_cruiser as Node3D).position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_scene_wiring: VoidCruiser position=%s" % (void_cruiser as Node3D).position)
		result = 1

	if planet_system != null:
		var planet := planet_system.get_node_or_null("Planet")
		var torus_station := planet_system.get_node_or_null("TorusStation")
		if planet == null:
			print("FAIL _test_scene_wiring: PlanetSystem/Planet missing")
			result = 1
		if torus_station == null:
			print("FAIL _test_scene_wiring: PlanetSystem/TorusStation missing")
			result = 1
		if planet_system.get_node_or_null("TopDownCamera") == null:
			print("FAIL _test_scene_wiring: PlanetSystem/TopDownCamera missing")
			result = 1
		if torus_station != null and planet != null:
			var resolved_planet: Node = torus_station.get_node_or_null(torus_station.planet_node)
			if resolved_planet != planet:
				print("FAIL _test_scene_wiring: TorusStation.planet_node did not resolve to Planet after reparenting")
				result = 1

	if rebase == null:
		print("FAIL _test_scene_wiring: WorldOriginRebase node missing")
		result = 1
	else:
		var resolved_tracked: Node = rebase.get_node_or_null(rebase.tracked_node)
		var resolved_rebasing: Node = rebase.get_node_or_null(rebase.rebasing_node)
		if resolved_tracked != void_cruiser:
			print("FAIL _test_scene_wiring: WorldOriginRebase.tracked_node did not resolve to VoidCruiser")
			result = 1
		if resolved_rebasing != planet_system:
			print("FAIL _test_scene_wiring: WorldOriginRebase.rebasing_node did not resolve to PlanetSystem")
			result = 1

	scene.free()
	return result
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd`
Expected: `1 TEST(S) FAILED` (`PlanetSystem node missing`, `WorldOriginRebase node missing`, `VoidCruiser position=(0, 4000, 6959600)` — the current scene doesn't have this structure yet).

- [ ] **Step 3: Rewrite the scene file**

Replace the entire contents of `scenes/torus1_system.tscn` with:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/planet.gd" id="1_planet"]
[ext_resource type="Script" path="res://scripts/torus_station.gd" id="2_station"]
[ext_resource type="Script" path="res://scripts/void_cruiser.gd" id="3_cruiser"]
[ext_resource type="Script" path="res://scripts/world_origin_rebase.gd" id="4_rebase"]

[node name="root" type="Node3D" unique_id=1858120877]

[node name="PlanetSystem" type="Node3D" parent="." unique_id=205893441]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -4000, -6959600)

[node name="Planet" type="MeshInstance3D" parent="PlanetSystem" unique_id=972318534]
script = ExtResource("1_planet")

[node name="TorusStation" type="Node3D" parent="PlanetSystem" unique_id=1706718276]
script = ExtResource("2_station")
planet_node = NodePath("../Planet")

[node name="TopDownCamera" type="Camera3D" parent="PlanetSystem" unique_id=716806475]
transform = Transform3D(1, 0, 0, 0, -4.371139e-08, 1, 0, -1, -4.371139e-08, 0, 20848800, 0)
near = 1000.0
far = 34748000.0

[node name="SunLight" type="DirectionalLight3D" parent="." unique_id=804147296]
transform = Transform3D(1, 0, 0, 0, -4.371139e-08, 1, 0, -1, -4.371139e-08, 0, 0, 0)

[node name="VoidCruiser" type="Node3D" parent="." unique_id=413410014]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
script = ExtResource("3_cruiser")

[node name="ChaseCamera" type="Camera3D" parent="VoidCruiser" unique_id=583786054]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 37.5, 112.5)
current = true
near = 10.0
far = 69496000.0

[node name="WorldOriginRebase" type="Node" parent="." unique_id=647120983]
script = ExtResource("4_rebase")
tracked_node = NodePath("../VoidCruiser")
rebasing_node = NodePath("../PlanetSystem")
```

- [ ] **Step 4: Run the wiring test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Run the full existing test suite to check for regressions**

Run each of these and confirm every one prints `ALL TESTS PASSED`:

```bash
cd /home/patrick/projects/playground/torus1/.claude/worktrees/static-station
for f in tests/test_planet.gd tests/test_torus_geometry.gd tests/test_torus_station.gd tests/test_void_cruiser.gd tests/test_void_cruiser_physics.gd tests/test_world_rebase.gd tests/test_world_origin_rebase.gd tests/test_scene_wiring.gd; do
  echo "== $f =="
  /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script "$f" 2>&1 | grep -E "PASSED|FAILED|FAIL "
done
```

Expected: every file reports `ALL TESTS PASSED`, no `FAIL` lines.

- [ ] **Step 6: Run the live project via Godot MCP and check for runtime errors**

Call `mcp__godot__run_project` with `projectPath: "/home/patrick/projects/playground/torus1/.claude/worktrees/static-station"`, then `mcp__godot__get_debug_output`, then `mcp__godot__stop_project`.

Expected: `errors` contains only the pre-existing, unrelated `libX11`/`libxkbcommon` linking warnings seen before this change — no `prepare_camera`, no node/property-not-found errors mentioning `Planet`, `TorusStation`, `VoidCruiser`, or `PlanetSystem`.

- [ ] **Step 7: Commit**

```bash
git add scenes/torus1_system.tscn tests/test_scene_wiring.gd
git commit -m "Wire floating origin into the scene: PlanetSystem carries the offset, VoidCruiser starts at local origin"
```

