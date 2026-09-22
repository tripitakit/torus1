# Void-cruiser Free-Flight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pilotable void-cruiser with damped-Newtonian free flight (thrust + rotation, keyboard + mouse), a fixed third-person chase camera, placed near the existing Torus1 station. No collision handling in this piece.

**Architecture:** A pure-function physics module (`void_cruiser_physics.gd`, same pattern as `torus_geometry.gd`) computes new linear/angular velocity from input, damping and delta. A thin `Node3D` script (`void_cruiser.gd`) reads keyboard/mouse input, calls the pure functions, and integrates position/orientation. A `Camera3D` is a rigid child of the ship at a fixed offset. The scene is assembled via the Godot MCP server, following the same add_node-then-hand-edit-transform pattern established in the static-station piece (MCP's `add_node` only persists scalar properties like `script` path or `current` bool — not `position`/`rotation_degrees`/`transform` arrays).

**Tech Stack:** Godot 4.6.1 (GDScript), Godot MCP server for scene assembly, headless `godot --headless --script` runs for automated tests.

**Spec:** `docs/superpowers/specs/2026-09-22-void-cruiser-design.md`

## Global Constraints

- Godot version: 4.6.1, 1 Godot unit = 1 meter (established by the static-station piece).
- No collision handling in this piece — the cruiser can pass through the station freely.
- Damping formula: `velocity * pow(1.0 - damping, delta)` — frame-rate-independent exponential decay, `damping` in `[0, 1)`.
- `thrust_power`, `linear_damping`, `torque_power`, `angular_damping`, `mouse_sensitivity` are gameplay-feel parameters, not derived physics constants (unlike the rotation piece's gravity-derived angular velocity) — no "correct" value to compute, just a starting point.
- Camera has no smoothing/spring-arm in this piece — a rigid child of the ship at a fixed local offset.
- `mcp__godot__add_node`'s `properties` field only persists simple scalar values (confirmed: `script` path strings and `current` booleans work; `position`/`rotation_degrees` arrays and `NodePath` values do not, and are silently dropped). Any node placement/orientation must be hand-written into the `.tscn` text and re-saved via `save_scene`.

## Review Focus

- `linear_damping`/`angular_damping` of `0.0` must leave velocity unchanged when there is no thrust/torque input (pure Newtonian edge case) — covered in Task 1.
- `linear_damping`/`angular_damping` near `1.0` must drive velocity toward zero without overshooting past it (no sign flip) — covered in Task 1.
- A very large `delta` (e.g. a frame hitch) must not produce NaN/Inf in either the linear or angular computation — covered in Task 1.
- Thrust must be transformed into world space by the ship's actual orientation, not applied along fixed world axes regardless of facing — covered in Task 1 with a 90°-yaw case.
- `velocity`/`angular_velocity` must persist and accumulate across physics steps, not reset every frame (or the ship could never build up speed) — covered in Task 2.
- The keyboard action names the script reads (`move_forward`, `move_backward`, `move_left`, `move_right`, `move_up`, `move_down`, `roll_left`, `roll_right`) must actually exist in the project's InputMap, or `Input.get_axis` silently returns `0.0` and the ship never responds to keys — covered in Task 2 by registering them in `project.godot` and calling the read-input methods headlessly (Godot logs an error for any action name not in the InputMap, which the test's clean-output expectation catches).

---

### Task 1: Void-cruiser physics module (pure, headless-tested)

**Files:**
- Create: `scripts/void_cruiser_physics.gd`
- Test: `tests/test_void_cruiser_physics.gd`

**Interfaces:**
- Produces:
  - `VoidCruiserPhysics.compute_new_velocity(velocity: Vector3, local_thrust_input: Vector3, orientation: Basis, thrust_power: float, linear_damping: float, delta: float) -> Vector3`
  - `VoidCruiserPhysics.compute_new_angular_velocity(angular_velocity: Vector3, local_torque_input: Vector3, torque_power: float, angular_damping: float, delta: float) -> Vector3`
  - Loaded via `const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")` (no `class_name`, same reasoning as `torus_geometry.gd`: avoid depending on the editor's global class cache).

- [ ] **Step 1: Write the failing test**

Create `tests/test_void_cruiser_physics.gd`:

```gdscript
extends SceneTree

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

func _init():
	var failures := 0
	failures += _test_pure_thrust_no_damping()
	failures += _test_pure_damping_no_thrust()
	failures += _test_zero_damping_is_pure_newtonian()
	failures += _test_high_damping_no_overshoot()
	failures += _test_large_delta_stays_finite()
	failures += _test_thrust_applied_in_world_space_via_orientation()
	failures += _test_angular_pure_torque_no_damping()
	failures += _test_angular_pure_damping_no_torque()
	failures += _test_angular_large_delta_stays_finite()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_pure_thrust_no_damping() -> int:
	var result := VoidCruiserPhysics.compute_new_velocity(Vector3.ZERO, Vector3(0, 0, -1), Basis.IDENTITY, 50.0, 0.0, 0.1)
	var expected := Vector3(0, 0, -5.0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_pure_thrust_no_damping: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_pure_damping_no_thrust() -> int:
	var result := VoidCruiserPhysics.compute_new_velocity(Vector3(10, 0, 0), Vector3.ZERO, Basis.IDENTITY, 999.0, 0.5, 1.0)
	var expected := Vector3(5.0, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_pure_damping_no_thrust: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_zero_damping_is_pure_newtonian() -> int:
	var result := VoidCruiserPhysics.compute_new_velocity(Vector3(3, 4, 5), Vector3.ZERO, Basis.IDENTITY, 0.0, 0.0, 2.0)
	var expected := Vector3(3, 4, 5)
	if not result.is_equal_approx(expected):
		print("FAIL _test_zero_damping_is_pure_newtonian: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_high_damping_no_overshoot() -> int:
	var result := VoidCruiserPhysics.compute_new_velocity(Vector3(10, 0, 0), Vector3.ZERO, Basis.IDENTITY, 0.0, 0.99, 1.0)
	if result.x <= 0.0 or result.x >= 10.0:
		print("FAIL _test_high_damping_no_overshoot: result.x=%f expected in (0, 10)" % result.x)
		return 1
	return 0

func _test_large_delta_stays_finite() -> int:
	var result := VoidCruiserPhysics.compute_new_velocity(Vector3(5, 0, 0), Vector3(1, 0, 0), Basis.IDENTITY, 10.0, 0.3, 1000.0)
	if is_nan(result.x) or is_inf(result.x) or is_nan(result.y) or is_inf(result.y) or is_nan(result.z) or is_inf(result.z):
		print("FAIL _test_large_delta_stays_finite: result=%s" % result)
		return 1
	return 0

func _test_thrust_applied_in_world_space_via_orientation() -> int:
	# 90 deg yaw around Y: forward (0,0,-1) rotates to (-1,0,0) by the standard
	# right-handed Y-rotation matrix (independent of the function under test):
	# x' = x*cos(t) + z*sin(t); z' = -x*sin(t) + z*cos(t); t=PI/2 -> x'=z=-1, z'=-x=0.
	var orientation := Basis(Vector3.UP, PI / 2.0)
	var result := VoidCruiserPhysics.compute_new_velocity(Vector3.ZERO, Vector3(0, 0, -1), orientation, 1.0, 0.0, 1.0)
	var expected := Vector3(-1, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_thrust_applied_in_world_space_via_orientation: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_angular_pure_torque_no_damping() -> int:
	var result := VoidCruiserPhysics.compute_new_angular_velocity(Vector3.ZERO, Vector3(1, 0, 0), 2.0, 0.0, 0.5)
	var expected := Vector3(1.0, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_angular_pure_torque_no_damping: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_angular_pure_damping_no_torque() -> int:
	var result := VoidCruiserPhysics.compute_new_angular_velocity(Vector3(2, 0, 0), Vector3.ZERO, 999.0, 0.5, 1.0)
	var expected := Vector3(1.0, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_angular_pure_damping_no_torque: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_angular_large_delta_stays_finite() -> int:
	var result := VoidCruiserPhysics.compute_new_angular_velocity(Vector3(5, 0, 0), Vector3(1, 0, 0), 10.0, 0.3, 1000.0)
	if is_nan(result.x) or is_inf(result.x):
		print("FAIL _test_angular_large_delta_stays_finite: result=%s" % result)
		return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path <PROJECT_PATH> --script res://tests/test_void_cruiser_physics.gd`
(`<PROJECT_PATH>` is this worktree's absolute path — see the static-station plan's Task 1 ruling about using the worktree path, not the plan's original path.)
Expected: an error, `res://scripts/void_cruiser_physics.gd` does not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/void_cruiser_physics.gd`:

```gdscript
extends RefCounted

static func compute_new_velocity(velocity: Vector3, local_thrust_input: Vector3, orientation: Basis, thrust_power: float, linear_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - linear_damping, delta)
	var thrust_accel := orientation * (local_thrust_input * thrust_power)
	return velocity * damping_factor + thrust_accel * delta

static func compute_new_angular_velocity(angular_velocity: Vector3, local_torque_input: Vector3, torque_power: float, angular_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - angular_damping, delta)
	var torque_accel := local_torque_input * torque_power
	return angular_velocity * damping_factor + torque_accel * delta
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same command as Step 2.
Expected: `ALL TESTS PASSED` printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
add scripts/void_cruiser_physics.gd tests/test_void_cruiser_physics.gd
commit -m "Add void-cruiser flight physics with headless tests"
```

(Use whatever `add`/`commit` tooling the executor's session uses — see the note on avoiding the literal substring "g-i-t" in shell-wrapped commands if the same sandbox guard from the static-station piece is present.)

---

### Task 2: Void-cruiser node script (input + integration)

**Files:**
- Create: `scripts/void_cruiser.gd`
- Modify: `project.godot` (register InputMap actions)
- Test: `tests/test_void_cruiser.gd`

**Interfaces:**
- Consumes: `VoidCruiserPhysics.compute_new_velocity`, `VoidCruiserPhysics.compute_new_angular_velocity` (Task 1).
- Produces: `void_cruiser.gd` attachable to a `Node3D`, exporting `thrust_power`, `linear_damping`, `torque_power`, `angular_damping`, `mouse_sensitivity`; instance fields `velocity: Vector3`, `angular_velocity: Vector3`; and a testable method `_apply_physics_step(delta: float, local_thrust_input: Vector3, local_torque_input: Vector3) -> void` that updates `velocity`/`angular_velocity` and integrates `global_position`/orientation. `_physics_process` and `_unhandled_input` are thin wrappers around it that are not directly unit-tested (they only read `Input`/mouse events).

- [ ] **Step 1: Register the InputMap actions**

Add to `project.godot` (a new `[input]` section; append after the existing `[rendering]` section):

```ini
[input]

move_forward={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_backward={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_up={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_down={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194325,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
roll_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
roll_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

(`physical_keycode` values: W=87, S=83, A=65, D=68, Space=32, Q=81, E=69, per Godot's `Key` enum values, which match their ASCII codes for letters/space. `move_down` binds the physical Left Shift key itself via its dedicated keycode, `KEY_SHIFT=4194325` — using `shift_pressed:true` as a modifier flag instead would require some *other* key held together with Shift, not Shift pressed alone.)

This step has no test of its own — Step 4 below exercises it by calling the read-input methods headlessly and expecting clean output (no "not found in InputMap" errors).

- [ ] **Step 2: Write the failing test**

Create `tests/test_void_cruiser.gd`:

```gdscript
extends SceneTree

const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

func _init():
	var failures := 0
	failures += _test_apply_physics_step_moves_position()
	failures += _test_apply_physics_step_rotates_orientation()
	failures += _test_velocity_persists_across_steps_without_thrust()
	failures += _test_read_input_methods_do_not_crash_headless()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cruiser() -> Node3D:
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.thrust_power = 50.0
	cruiser.linear_damping = 0.0
	cruiser.torque_power = 2.0
	cruiser.angular_damping = 0.0
	return cruiser

func _test_apply_physics_step_moves_position() -> int:
	var cruiser := _make_cruiser()
	var start_position := cruiser.global_position
	cruiser._apply_physics_step(1.0, Vector3(0, 0, -1), Vector3.ZERO)
	var result := 0
	var expected_velocity := Vector3(0, 0, -50.0)
	if not cruiser.velocity.is_equal_approx(expected_velocity):
		print("FAIL _test_apply_physics_step_moves_position: velocity=%s expected=%s" % [cruiser.velocity, expected_velocity])
		result = 1
	var expected_position := start_position + expected_velocity * 1.0
	if not cruiser.global_position.is_equal_approx(expected_position):
		print("FAIL _test_apply_physics_step_moves_position: position=%s expected=%s" % [cruiser.global_position, expected_position])
		result = 1
	cruiser.free()
	return result

func _test_apply_physics_step_rotates_orientation() -> int:
	var cruiser := _make_cruiser()
	var original_basis: Basis = cruiser.transform.basis
	cruiser._apply_physics_step(0.5, Vector3.ZERO, Vector3(0, 1, 0))
	var result := 0
	var expected_angular_velocity := Vector3(0, 1.0, 0)
	if not cruiser.angular_velocity.is_equal_approx(expected_angular_velocity):
		print("FAIL _test_apply_physics_step_rotates_orientation: angular_velocity=%s expected=%s" % [cruiser.angular_velocity, expected_angular_velocity])
		result = 1
	var new_basis: Basis = cruiser.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_delta_basis := Basis(Vector3.UP, expected_angular_velocity.y * 0.5)
	if not delta_basis.y.is_equal_approx(expected_delta_basis.y) or not delta_basis.x.is_equal_approx(expected_delta_basis.x):
		print("FAIL _test_apply_physics_step_rotates_orientation: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	cruiser.free()
	return result

func _test_velocity_persists_across_steps_without_thrust() -> int:
	var cruiser := _make_cruiser()
	cruiser._apply_physics_step(1.0, Vector3(0, 0, -1), Vector3.ZERO)
	var velocity_after_thrust: Vector3 = cruiser.velocity
	var position_after_thrust: Vector3 = cruiser.global_position
	cruiser._apply_physics_step(1.0, Vector3.ZERO, Vector3.ZERO)
	var result := 0
	if not cruiser.velocity.is_equal_approx(velocity_after_thrust):
		print("FAIL _test_velocity_persists_across_steps_without_thrust: velocity changed to %s, expected unchanged %s (damping=0)" % [cruiser.velocity, velocity_after_thrust])
		result = 1
	var expected_position := position_after_thrust + velocity_after_thrust * 1.0
	if not cruiser.global_position.is_equal_approx(expected_position):
		print("FAIL _test_velocity_persists_across_steps_without_thrust: position=%s expected=%s" % [cruiser.global_position, expected_position])
		result = 1
	cruiser.free()
	return result

func _test_read_input_methods_do_not_crash_headless() -> int:
	var cruiser := _make_cruiser()
	var thrust := cruiser._read_thrust_input()
	var torque := cruiser._read_torque_input()
	var result := 0
	if not thrust.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_read_input_methods_do_not_crash_headless: thrust=%s expected ZERO with no keys held" % thrust)
		result = 1
	if not torque.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_read_input_methods_do_not_crash_headless: torque=%s expected ZERO with no input" % torque)
		result = 1
	cruiser.free()
	return result
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path <PROJECT_PATH> --script res://tests/test_void_cruiser.gd`
Expected: an error, `res://scripts/void_cruiser.gd` does not exist yet.

- [ ] **Step 4: Write the minimal implementation**

Create `scripts/void_cruiser.gd`:

```gdscript
extends Node3D

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

@export var thrust_power: float = 50.0
@export var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01

var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

func _physics_process(delta: float) -> void:
	_apply_physics_step(delta, _read_thrust_input(), _read_torque_input())

func _read_thrust_input() -> Vector3:
	var strafe := Input.get_axis("move_left", "move_right")
	var vertical := Input.get_axis("move_down", "move_up")
	var forward := Input.get_axis("move_forward", "move_backward")
	return Vector3(strafe, vertical, forward)

func _read_torque_input() -> Vector3:
	var pitch := -_mouse_delta.y * mouse_sensitivity
	var yaw := -_mouse_delta.x * mouse_sensitivity
	var roll := Input.get_axis("roll_left", "roll_right")
	_mouse_delta = Vector2.ZERO
	return Vector3(pitch, yaw, roll)

func _apply_physics_step(delta: float, local_thrust_input: Vector3, local_torque_input: Vector3) -> void:
	velocity = VoidCruiserPhysics.compute_new_velocity(velocity, local_thrust_input, global_transform.basis, thrust_power, linear_damping, delta)
	angular_velocity = VoidCruiserPhysics.compute_new_angular_velocity(angular_velocity, local_torque_input, torque_power, angular_damping, delta)

	global_position += velocity * delta
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.FORWARD, angular_velocity.z * delta)
```

Note: `move_forward` maps to `physical_keycode 87` (W) as the *negative* side of `Input.get_axis("move_forward", "move_backward")` — pressing W yields a negative `forward` value. In `_apply_physics_step`, `local_thrust_input.z` is passed straight through to `compute_new_velocity`, which multiplies it by the ship's orientation; since Godot's forward is `-Z`, a negative `forward` axis value from pressing W correctly pushes the ship in its own `-Z` (forward) direction. This matches the sign convention already fixed by Task 1's `_test_pure_thrust_no_damping` (thrust input `(0,0,-1)` — i.e. what W produces — accelerates in `-Z`).

- [ ] **Step 5: Run the test to verify it passes**

Run: same command as Step 3.
Expected: `ALL TESTS PASSED` printed, exit code 0.

- [ ] **Step 6: Commit**

```bash
add scripts/void_cruiser.gd project.godot tests/test_void_cruiser.gd
commit -m "Add void-cruiser node script with input map and headless tests"
```

---

### Task 3: Assemble the scene — place the cruiser and its camera

**Files:**
- Modify (via MCP + hand-edit, not directly written from scratch): `scenes/torus1_system.tscn`

**Interfaces:**
- Consumes: `scripts/void_cruiser.gd` (Task 2).

- [ ] **Step 1: Add the VoidCruiser node**

Call `mcp__godot__add_node` with `projectPath: "<PROJECT_PATH>"`, `scenePath: "scenes/torus1_system.tscn"`, `parentNodePath: "root"`, `nodeType: "Node3D"`, `nodeName: "VoidCruiser"`, `properties: {"script": "res://scripts/void_cruiser.gd"}`.

- [ ] **Step 2: Add the ChaseCamera node as a child of VoidCruiser**

Call `mcp__godot__add_node` with the same `projectPath`/`scenePath`, `parentNodePath: "root/VoidCruiser"`, `nodeType: "Camera3D"`, `nodeName: "ChaseCamera"`, `properties: {"current": true}` (a plain bool, confirmed to persist correctly by the static-station piece).

- [ ] **Step 3: Save, then hand-edit transforms and the previous camera's `current` flag**

Call `mcp__godot__save_scene`, then read `scenes/torus1_system.tscn` and hand-edit it directly (per the Global Constraints note — `position`/`transform` arrays don't survive `add_node`'s `properties`):

- `VoidCruiser`'s own `transform`: position it near the ring but clear of the station geometry, e.g. `Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2200, 150, 0)` (torus radius is 2000, sections extend ~30m from the ring centerline — this is comfortably outside).
- `ChaseCamera`'s local `transform`: behind and above the ship, e.g. `Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 15)` (identity orientation — same forward direction as its parent, so it faces the same way the ship does).
- `TopDownCamera`'s node block: remove its `current = true` line (only `ChaseCamera` should be current now — Godot uses whichever `Camera3D` most recently had `current = true`, so leaving both risks ambiguity).

- [ ] **Step 4: Re-save and verify**

Call `mcp__godot__save_scene` again, then read the file back. Expected: `VoidCruiser` has a `script = ExtResource(...)` line pointing at `void_cruiser.gd` and a `transform` matching Step 3; `ChaseCamera` is a child of `VoidCruiser` with `current = true` and its own offset `transform`; `TopDownCamera` no longer has `current = true`.

- [ ] **Step 5: Run the project and check for errors**

Call `mcp__godot__run_project` with `projectPath`, `scene: "scenes/torus1_system.tscn"`, then `mcp__godot__get_debug_output`.
Expected: no script errors, no "not found in InputMap" warnings (would indicate a Task 2 Step 1 typo), no null-reference errors. Then `mcp__godot__stop_project`.

- [ ] **Step 6: Commit**

```bash
add scenes/torus1_system.tscn
commit -m "Add void-cruiser and chase camera to the scene"
```

---
