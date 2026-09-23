# Station Collisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The void-cruiser bounces off station sections and bridges instead of flying through them.

**Architecture:** VoidCruiser becomes a `CharacterBody3D` and moves via `move_and_collide()` instead of hand-adding `velocity * delta` to `position`; on collision, velocity is reflected off the impact normal (`Vector3.bounce()`) scaled by a tunable restitution. Station sections (which spin continuously for artificial gravity) become `AnimatableBody3D`; bridges (which never move) become `StaticBody3D`. Every section/bridge collision shape is one shared `CylinderShape3D` resource, same sharing pattern already used for meshes and materials.

**Tech Stack:** Godot 4.6.1 (double-precision build at `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`), GDScript. Headless tests via `<godot binary> --headless --path . --script tests/<file>.gd`, expected output `ALL TESTS PASSED`. Live scene checks via `mcp__godot__run_project` / `mcp__godot__get_debug_output` / `mcp__godot__stop_project`.

**Spec:** `docs/superpowers/specs/2026-09-23-station-collisions-design.md`

## Global Constraints

- `collision_restitution`: `@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4` on `VoidCruiser`
- Ship collision shape: `BoxShape3D` with `size = Vector3(15.0, 7.5, 30.0)`, centered on the body's own origin (no offset)
- Section collision shape: `CylinderShape3D` with `radius = section_radius`, `height = section_length` — one shared resource for every section instance
- Bridge collision shape: `CylinderShape3D` with `radius = section_radius * 0.3`, `height = max(bridge_length, 0.01)` — one shared resource for every bridge instance
- Section body type: `AnimatableBody3D` (spins every frame for artificial gravity — `StaticBody3D` is for bodies that never move)
- Bridge body type: `StaticBody3D` (never moves — confirmed by the existing `_test_rotate_sections_does_not_rotate_bridges` test)
- `Stripe` stays a **direct child** of the Section body (a sibling of the new `Mesh` and `Collision` children), not nested under `Mesh` — required for `_test_sections_have_stripe_marker`'s `section.get_node_or_null("Stripe")` to keep working
- `_apply_physics_step`'s velocity/angular_velocity computation and the three `rotate_object_local` calls are unchanged. Only how position is applied changes, via a new `_move(delta)` method: off-tree (every existing headless unit test, which never adds the cruiser to a tree) → `position += velocity * delta` exactly as today; in-tree (real gameplay) → `move_and_collide(velocity * delta)`, and on a returned collision, `velocity = VoidCruiserPhysics.compute_bounce_velocity(velocity, collision.get_normal(), collision_restitution)`
- `scenes/torus1_system.tscn`: the `VoidCruiser` node's declared type changes from `Node3D` to `CharacterBody3D` (must match the script's new base class or the scene fails to load)
- **Not achievable in this codebase's test harness, by design, verified empirically:** calling any Godot physics-server-backed method (`move_and_collide`, `global_position`, etc.) on a node that is not genuinely inside a processed `SceneTree` frame fails silently (prints an engine error, returns `null`/no-ops). This project's headless tests (`extends SceneTree`, synchronous `_init()`) never process a real frame, even for nodes added to `root`. Real collision detection is therefore not unit-tested — only the pure bounce math and the structural wiring (shapes present, shared, correctly sized) are. See the spec for the verification script and its output.

## Review Focus

1. `.tscn` `VoidCruiser` node type must be updated to `CharacterBody3D` to match the script's new base class, or scene loading fails outright — covered by Task 2's scene edit and its `run_project` check.
2. `Stripe` must remain a direct child of the Section body, not nested under the new `Mesh` child, or the existing `_test_sections_have_stripe_marker` breaks — covered by Task 3's exact child-adding order (`section.add_child(stripe)`, not `section_mesh_instance.add_child(stripe)`).
3. Collision layer/mask rely on Godot's untouched defaults (both `CharacterBody3D` and `AnimatableBody3D`/`StaticBody3D` default to layer `1`, mask `1`) for the ship and station to actually collide at all. Nothing in this plan configures or tests layers/masks explicitly — if bounces don't register during play-testing, this is the first thing to check.
4. Collision shape **resources** must be shared across every section/bridge instance (assign the same `Shape3D` object to each `CollisionShape3D.shape`, never construct a fresh one per loop iteration) — covered by Task 3's sharing tests, mirroring the existing mesh/material sharing tests.
5. `move_and_collide` needs a live physics space that only exists once a node is genuinely inside a processed tree frame — verified empirically or it can silently do nothing. Covered by keeping `_apply_physics_step` off-tree-safe via `_move`'s `is_inside_tree()` branch (Task 2), and documented as a permanent, intentional gap in automated coverage rather than something a future task should try to close in this same harness.

---

### Task 1: Bounce velocity math

**Files:**
- Modify: `scripts/void_cruiser_physics.gd`
- Test: `tests/test_void_cruiser_physics.gd`

**Interfaces:**
- Produces: `VoidCruiserPhysics.compute_bounce_velocity(velocity: Vector3, normal: Vector3, restitution: float) -> Vector3`

- [ ] **Step 1: Write the failing tests**

Open `tests/test_void_cruiser_physics.gd`. Add these five calls to the `failures +=` list in `_init()`, right after the existing `_test_angular_damping_above_one_does_not_produce_nan()` line:

```gdscript
	failures += _test_bounce_reflects_perpendicular_impact()
	failures += _test_bounce_restitution_scales_result()
	failures += _test_bounce_zero_restitution_stops_dead()
	failures += _test_bounce_grazing_impact_preserves_tangential_component()
	failures += _test_bounce_oblique_impact()
```

Then append these five functions at the end of the file:

```gdscript
func _test_bounce_reflects_perpendicular_impact() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_bounce_velocity(Vector3(0, 0, -10), Vector3(0, 0, 1), 1.0)
	var expected := Vector3(0, 0, 10)
	if not result.is_equal_approx(expected):
		print("FAIL _test_bounce_reflects_perpendicular_impact: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_bounce_restitution_scales_result() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_bounce_velocity(Vector3(0, 0, -10), Vector3(0, 0, 1), 0.4)
	var expected := Vector3(0, 0, 4.0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_bounce_restitution_scales_result: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_bounce_zero_restitution_stops_dead() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_bounce_velocity(Vector3(5, -3, 2), Vector3(0, 1, 0), 0.0)
	var expected := Vector3.ZERO
	if not result.is_equal_approx(expected):
		print("FAIL _test_bounce_zero_restitution_stops_dead: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_bounce_grazing_impact_preserves_tangential_component() -> int:
	# Velocity parallel to the surface (perpendicular to the normal) has no
	# component into the surface: bounce() must leave it unchanged.
	var result: Vector3 = VoidCruiserPhysics.compute_bounce_velocity(Vector3(10, 0, 0), Vector3(0, 0, 1), 1.0)
	var expected := Vector3(10, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_bounce_grazing_impact_preserves_tangential_component: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_bounce_oblique_impact() -> int:
	# v=(1,-1,0) hitting a normal=(0,1,0) floor: v - 2*(v.n)*n
	# = (1,-1,0) - 2*(-1)*(0,1,0) = (1,-1,0) + (0,2,0) = (1,1,0)
	var result: Vector3 = VoidCruiserPhysics.compute_bounce_velocity(Vector3(1, -1, 0), Vector3(0, 1, 0), 1.0)
	var expected := Vector3(1, 1, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_bounce_oblique_impact: result=%s expected=%s" % [result, expected])
		return 1
	return 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser_physics.gd`
Expected: parse/compile error, `Invalid call. Nonexistent function 'compute_bounce_velocity'` (the function doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Open `scripts/void_cruiser_physics.gd`. Append this function at the end of the file:

```gdscript
static func compute_bounce_velocity(velocity: Vector3, normal: Vector3, restitution: float) -> Vector3:
	return velocity.bounce(normal) * restitution
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser_physics.gd`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser_physics.gd tests/test_void_cruiser_physics.gd
git commit -m "Add pure bounce-velocity reflection for station collisions"
```

---

### Task 2: VoidCruiser becomes a CharacterBody3D

**Files:**
- Modify: `scripts/void_cruiser.gd`
- Modify: `scenes/torus1_system.tscn`
- Test: `tests/test_void_cruiser.gd`

**Interfaces:**
- Consumes: `VoidCruiserPhysics.compute_bounce_velocity(Vector3, Vector3, float) -> Vector3` from Task 1
- Produces: `VoidCruiser.build_collision_shape() -> void`, `VoidCruiser._move(delta: float) -> void`, `@export var collision_restitution: float`

- [ ] **Step 1: Write the failing test**

Open `tests/test_void_cruiser.gd`. Add this call to the `failures +=` list in `_init()`, after `_test_forward_thrust_ramps_up_velocity_over_time()`:

```gdscript
	failures += _test_build_collision_shape_adds_box_shape()
```

Then append this function at the end of the file:

```gdscript
func _test_build_collision_shape_adds_box_shape() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_collision_shape()
	var result := 0
	var shape_node := cruiser.get_node_or_null("CollisionShape3D")
	if shape_node == null or not (shape_node is CollisionShape3D):
		print("FAIL _test_build_collision_shape_adds_box_shape: no CollisionShape3D child")
		result = 1
	elif (shape_node as CollisionShape3D).shape == null or not ((shape_node as CollisionShape3D).shape is BoxShape3D):
		print("FAIL _test_build_collision_shape_adds_box_shape: shape is not a BoxShape3D")
		result = 1
	else:
		var box: BoxShape3D = (shape_node as CollisionShape3D).shape
		var expected := Vector3(15.0, 7.5, 30.0)
		if not box.size.is_equal_approx(expected):
			print("FAIL _test_build_collision_shape_adds_box_shape: size=%s expected=%s" % [box.size, expected])
			result = 1
	cruiser.free()
	return result
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd`
Expected: `Invalid call. Nonexistent function 'build_collision_shape'` (also note: at this point `VoidCruiserScript.new()` still creates a `Node3D`, since the script hasn't been converted yet — that's fine, the error about the missing method is what confirms the test is wired correctly).

- [ ] **Step 3: Rewrite `scripts/void_cruiser.gd`**

Replace the entire file with:

```gdscript
extends CharacterBody3D

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")
const SHIP_MODEL_PATH := "res://assets/models/void_cruiser.glb"

@export var thrust_power: float = 150.0
@export_range(0.0, 0.999, 0.001) var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export_range(0.0, 0.999, 0.001) var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01
@export var forward_thrust_ramp_multiplier: float = 10.0
@export var forward_thrust_ramp_duration: float = 5.0
@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4

var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO
var _forward_hold_time: float = 0.0
var _forward_hold_sign: float = 0.0

func _ready() -> void:
	build_ship_mesh()
	build_collision_shape()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func build_ship_mesh() -> void:
	var packed: PackedScene = load(SHIP_MODEL_PATH)
	var model := packed.instantiate()
	model.name = "ShipModel"
	# Blender's glTF exporter does not preserve "which way is forward": this
	# ship was modeled nose-toward -Y in Blender, and the export placed the
	# nose toward +Z in Godot instead of -Z (forward), so it faced the chase
	# camera instead of away from it. Corrective yaw, not a modeling error.
	model.rotation_degrees.y = 180.0
	add_child(model)

func build_collision_shape() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(15.0, 7.5, 30.0)
	shape_node.shape = box
	add_child(shape_node)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

func _physics_process(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	var multiplier := VoidCruiserPhysics.compute_forward_thrust_multiplier(_forward_hold_time, forward_thrust_ramp_duration, forward_thrust_ramp_multiplier)
	thrust_input.z *= multiplier
	_apply_physics_step(delta, thrust_input, _read_torque_input(delta))

func _read_thrust_input() -> Vector3:
	var strafe := Input.get_axis("move_left", "move_right")
	var vertical := Input.get_axis("move_down", "move_up")
	var forward := Input.get_axis("move_forward", "move_backward")
	return Vector3(strafe, vertical, forward)

func _update_forward_hold_time(forward_input: float, delta: float) -> void:
	# Holding W/S continuously ramps forward/backward thrust up to
	# forward_thrust_ramp_multiplier over forward_thrust_ramp_duration
	# seconds. Releasing the key, or reversing direction, starts the ramp
	# over from 1x on the very next press.
	var current_sign: float = sign(forward_input)
	if current_sign == 0.0 or current_sign != _forward_hold_sign:
		_forward_hold_time = 0.0
	else:
		_forward_hold_time += delta
	_forward_hold_sign = current_sign

func _read_torque_input(delta: float) -> Vector3:
	# Mouse motion is a one-off displacement, not a continuous rate, but it
	# feeds into compute_new_angular_velocity's `torque_input * delta`
	# integration alongside continuous keyboard input. Pre-dividing by delta
	# here cancels that later multiplication, so mouse-look sensitivity stays
	# constant regardless of the physics tick rate.
	var pitch := 0.0
	var yaw := 0.0
	if delta > 0.0:
		pitch = -_mouse_delta.y * mouse_sensitivity / delta
		yaw = -_mouse_delta.x * mouse_sensitivity / delta
	var roll := Input.get_axis("roll_left", "roll_right")
	_mouse_delta = Vector2.ZERO
	return Vector3(pitch, yaw, roll)

func _apply_physics_step(delta: float, local_thrust_input: Vector3, local_torque_input: Vector3) -> void:
	velocity = VoidCruiserPhysics.compute_new_velocity(velocity, local_thrust_input, transform.basis, thrust_power, linear_damping, delta)
	angular_velocity = VoidCruiserPhysics.compute_new_angular_velocity(angular_velocity, local_torque_input, torque_power, angular_damping, delta)

	_move(delta)

	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.FORWARD, angular_velocity.z * delta)

func _move(delta: float) -> void:
	# move_and_collide needs a live physics space, which only exists once
	# this node is genuinely inside a processed scene tree frame. Off-tree
	# (every headless unit test in this project, which never adds the
	# cruiser to a tree) falls back to plain integration — see
	# docs/superpowers/specs/2026-09-23-station-collisions-design.md for the
	# empirical verification behind this.
	if not is_inside_tree():
		position += velocity * delta
		return
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = VoidCruiserPhysics.compute_bounce_velocity(velocity, collision.get_normal(), collision_restitution)
```

Note `velocity` is no longer declared locally: `CharacterBody3D` already provides a built-in `velocity: Vector3` property (verified empirically — declaring it again would conflict). `angular_velocity` has no built-in equivalent and is still declared as before.

- [ ] **Step 4: Update the scene's node type**

Open `scenes/torus1_system.tscn`. Find:

```
[node name="VoidCruiser" type="Node3D" parent="." unique_id=413410014]
```

Replace with:

```
[node name="VoidCruiser" type="CharacterBody3D" parent="." unique_id=413410014]
```

(Only the `type` attribute changes — same `unique_id`, same `transform`, same `script` line below it, unchanged.)

- [ ] **Step 5: Run test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd`
Expected: `ALL TESTS PASSED`

- [ ] **Step 6: Run the full existing suite to check for regressions**

```bash
cd /home/patrick/projects/playground/torus1
for f in tests/test_planet.gd tests/test_torus_geometry.gd tests/test_torus_station.gd tests/test_void_cruiser.gd tests/test_void_cruiser_physics.gd tests/test_world_rebase.gd tests/test_world_origin_rebase.gd tests/test_scene_wiring.gd; do
  echo "== $f =="
  /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script "$f" 2>&1 | tail -5
done
```

Expected: every file reports `ALL TESTS PASSED`. (`test_torus_station.gd` is expected to already be green here — Task 3 hasn't touched it yet.)

- [ ] **Step 7: Run the live project via Godot MCP and check for errors**

Call `mcp__godot__run_project` with `projectPath: "/home/patrick/projects/playground/torus1"`, then `mcp__godot__get_debug_output`, then `mcp__godot__stop_project`.

Expected: `errors` contains only the pre-existing `libX11`/`libxkbcommon` linking warnings — no scene-loading error about `VoidCruiser`'s type, no physics-server errors.

- [ ] **Step 8: Commit**

```bash
git add scripts/void_cruiser.gd scenes/torus1_system.tscn tests/test_void_cruiser.gd
git commit -m "Convert VoidCruiser to CharacterBody3D, add collision shape and bounce-on-impact"
```

---

### Task 3: Station sections and bridges get collision shapes

**Files:**
- Modify: `scripts/torus_station.gd`
- Test: `tests/test_torus_station.gd` (full rewrite — the change from `MeshInstance3D` bodies to `AnimatableBody3D`/`StaticBody3D` wrapping a `Mesh` child touches type hints and node lookups throughout the existing file)

**Interfaces:**
- Consumes: nothing from Task 1 or 2 (independent subsystem)
- Produces: `Section%d` nodes are now `AnimatableBody3D` with children `Mesh` (`MeshInstance3D`), `Collision` (`CollisionShape3D`), `Stripe` (`MeshInstance3D`, unchanged, direct child); `Bridge%d` nodes are now `StaticBody3D` with children `Mesh` and `Collision`

- [ ] **Step 1: Replace `tests/test_torus_station.gd` with the target version (will fail against the current script)**

Replace the entire file with:

```gdscript
extends SceneTree

const TorusStationScript = preload("res://scripts/torus_station.gd")
const PlanetScript = preload("res://scripts/planet.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

func _init():
	var failures := 0
	failures += _test_build_station_child_count()
	failures += _test_section_and_bridge_mesh_shape()
	failures += _test_rebuild_does_not_leak()
	failures += _test_build_station_preserves_unrelated_children()
	failures += _test_bridge_positions_are_distinct_and_close_the_ring()
	failures += _test_uses_planet_node_radius_when_set()
	failures += _test_sections_have_stripe_marker()
	failures += _test_rotate_sections_applies_correct_local_y_angle()
	failures += _test_rotate_sections_does_not_rotate_bridges()
	failures += _test_sections_and_bridges_share_one_hull_material()
	failures += _test_stripes_use_yellow_material_distinct_from_hull()
	failures += _test_sections_share_one_mesh_resource()
	failures += _test_stripes_share_one_mesh_resource()
	failures += _test_bridges_share_one_mesh_resource()
	failures += _test_hull_material_has_emission_and_ao()
	failures += _test_sections_are_animatable_bodies()
	failures += _test_bridges_are_static_bodies()
	failures += _test_sections_have_matching_collision_shape()
	failures += _test_bridges_have_matching_collision_shape()
	failures += _test_section_collision_shapes_are_shared()
	failures += _test_bridge_collision_shapes_are_shared()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_station(num_sections: int) -> Node3D:
	var station: Node3D = TorusStationScript.new()
	station.planet_radius = 500.0
	station.orbit_altitude = 1500.0
	station.num_sections = num_sections
	station.section_radius = 30.0
	station.section_length = 80.0
	station.target_gravity_g = 1.0
	return station

func _test_build_station_child_count() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if station.get_child_count() != 8:
		print("FAIL _test_build_station_child_count: expected 8 children, got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_section_and_bridge_mesh_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var section_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var bridge_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var failed := false
	if not (section_mesh.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Section0/Mesh.mesh is not CylinderMesh")
		failed = true
	else:
		var cyl: CylinderMesh = section_mesh.mesh
		if not is_equal_approx(cyl.top_radius, 30.0) or not is_equal_approx(cyl.height, 80.0):
			print("FAIL _test_section_and_bridge_mesh_shape: Section0/Mesh top_radius=%f height=%f" % [cyl.top_radius, cyl.height])
			failed = true
	if not (bridge_mesh.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Bridge0/Mesh.mesh is not CylinderMesh")
		failed = true
	station.free()
	return 1 if failed else 0

func _test_rebuild_does_not_leak() -> int:
	var station := _make_station(4)
	station.build_station()
	station.build_station()
	var result := 0
	if station.get_child_count() != 8:
		print("FAIL _test_rebuild_does_not_leak: expected 8 children after rebuild, got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_build_station_preserves_unrelated_children() -> int:
	var station := _make_station(4)
	var marker := Node3D.new()
	marker.name = "Marker"
	station.add_child(marker)
	station.build_station()
	var result := 0
	if station.get_node_or_null("Marker") == null:
		print("FAIL _test_build_station_preserves_unrelated_children: Marker was removed by build_station()")
		result = 1
	if station.get_child_count() != 9:
		print("FAIL _test_build_station_preserves_unrelated_children: expected 9 children (8 generated + Marker), got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_bridge_positions_are_distinct_and_close_the_ring() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var torus_radius := 500.0 + 1500.0
	var step := TAU / 4.0
	for i in range(4):
		var bridge: StaticBody3D = station.get_node("Bridge%d" % i)
		var expected_theta := i * step + step * 0.5
		var expected_pos := Vector3(cos(expected_theta), 0.0, sin(expected_theta)) * torus_radius
		if not bridge.transform.origin.is_equal_approx(expected_pos):
			print("FAIL _test_bridge_positions_are_distinct_and_close_the_ring: Bridge%d origin=%s expected=%s" % [i, bridge.transform.origin, expected_pos])
			result = 1
	station.free()
	return result

func _test_uses_planet_node_radius_when_set() -> int:
	var station := _make_station(4)
	station.planet_radius = 500.0
	var planet: MeshInstance3D = PlanetScript.new()
	planet.name = "Planet"
	planet.planet_radius = 900.0
	station.add_child(planet)
	station.planet_node = NodePath("Planet")
	station.build_station()
	var result := 0
	var section0: AnimatableBody3D = station.get_node("Section0")
	var expected_torus_radius := 900.0 + 1500.0
	if not is_equal_approx(section0.transform.origin.length(), expected_torus_radius):
		print("FAIL _test_uses_planet_node_radius_when_set: Section0 distance=%f expected=%f" % [section0.transform.origin.length(), expected_torus_radius])
		result = 1
	station.free()
	return result

func _test_sections_have_stripe_marker() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var result := 0
	var stripe := section.get_node_or_null("Stripe")
	if stripe == null or not (stripe is MeshInstance3D) or not ((stripe as MeshInstance3D).mesh is BoxMesh):
		print("FAIL _test_sections_have_stripe_marker: Section0 has no Stripe MeshInstance3D with a BoxMesh")
		result = 1
	else:
		# Offset must be along local Z (radially outward in the ring's horizontal
		# plane, visible from the top-down verification camera), not local X
		# (which maps to world UP for every section and is invisible from above).
		var expected_offset := Vector3(0.0, 0.0, 30.0)
		if not (stripe as MeshInstance3D).transform.origin.is_equal_approx(expected_offset):
			print("FAIL _test_sections_have_stripe_marker: Stripe offset=%s expected=%s" % [(stripe as MeshInstance3D).transform.origin, expected_offset])
			result = 1
	station.free()
	return result

func _test_rotate_sections_applies_correct_local_y_angle() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var original_basis: Basis = section.transform.basis
	var delta := 0.1
	station._rotate_sections(delta)
	var new_basis: Basis = section.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_omega: float = TorusGeometry.compute_section_angular_velocity(30.0, TorusGeometry.GRAVITY_1G)
	var expected_delta_basis := Basis(Vector3.UP, expected_omega * delta)
	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_rotate_sections_applies_correct_local_y_angle: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_rotate_sections_does_not_rotate_bridges() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge: StaticBody3D = station.get_node("Bridge0")
	var original_basis: Basis = bridge.transform.basis
	station._rotate_sections(0.1)
	var result := 0
	if not bridge.transform.basis.is_equal_approx(original_basis):
		print("FAIL _test_rotate_sections_does_not_rotate_bridges: bridge basis changed")
		result = 1
	station.free()
	return result

func _test_sections_and_bridges_share_one_hull_material() -> int:
	# Sections+bridges must all reference the SAME material resource, not a
	# fresh StandardMaterial3D per mesh — with num_sections in the thousands,
	# per-object materials would duplicate a GPU resource needlessly.
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var section1_mesh: MeshInstance3D = station.get_node("Section1").get_node("Mesh")
	var bridge0_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var result := 0
	if section0_mesh.material_override == null:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0/Mesh has no material_override")
		result = 1
	elif section0_mesh.material_override != section1_mesh.material_override:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0 and Section1 use different material resources")
		result = 1
	elif section0_mesh.material_override != bridge0_mesh.material_override:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0 and Bridge0 use different material resources")
		result = 1
	station.free()
	return result

func _test_sections_share_one_mesh_resource() -> int:
	# With num_sections in the thousands, a fresh CylinderMesh per section
	# would duplicate identical geometry in GPU memory thousands of times.
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var section1_mesh: MeshInstance3D = station.get_node("Section1").get_node("Mesh")
	var result := 0
	if section0_mesh.mesh == null or section0_mesh.mesh != section1_mesh.mesh:
		print("FAIL _test_sections_share_one_mesh_resource: Section0 and Section1 use different mesh resources")
		result = 1
	station.free()
	return result

func _test_stripes_share_one_mesh_resource() -> int:
	var station := _make_station(4)
	station.build_station()
	var stripe0: MeshInstance3D = station.get_node("Section0").get_node("Stripe")
	var stripe1: MeshInstance3D = station.get_node("Section1").get_node("Stripe")
	var result := 0
	if stripe0.mesh == null or stripe0.mesh != stripe1.mesh:
		print("FAIL _test_stripes_share_one_mesh_resource: Stripe meshes differ between sections")
		result = 1
	station.free()
	return result

func _test_bridges_share_one_mesh_resource() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge0_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var bridge1_mesh: MeshInstance3D = station.get_node("Bridge1").get_node("Mesh")
	var result := 0
	if bridge0_mesh.mesh == null or bridge0_mesh.mesh != bridge1_mesh.mesh:
		print("FAIL _test_bridges_share_one_mesh_resource: Bridge meshes differ between instances")
		result = 1
	station.free()
	return result

func _test_hull_material_has_emission_and_ao() -> int:
	var station := _make_station(4)
	station.build_station()
	var section_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var mat: StandardMaterial3D = section_mesh.material_override
	var result := 0
	if not mat.emission_enabled or mat.emission_texture == null:
		print("FAIL _test_hull_material_has_emission_and_ao: emission not enabled or no emission_texture")
		result = 1
	# Emission operator is additive (color + texture): a non-black base color
	# would make the whole hull glow, not just the lights painted in the texture.
	if not mat.emission.is_equal_approx(Color(0, 0, 0)):
		print("FAIL _test_hull_material_has_emission_and_ao: base emission color=%s expected black" % mat.emission)
		result = 1
	if not mat.ao_enabled or mat.ao_texture == null:
		print("FAIL _test_hull_material_has_emission_and_ao: ao not enabled or no ao_texture")
		result = 1
	station.free()
	return result

func _test_stripes_use_yellow_material_distinct_from_hull() -> int:
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var stripe: MeshInstance3D = station.get_node("Section0").get_node("Stripe")
	var result := 0
	if stripe.material_override == null or not (stripe.material_override is StandardMaterial3D):
		print("FAIL _test_stripes_use_yellow_material_distinct_from_hull: Stripe has no StandardMaterial3D override")
		result = 1
	else:
		var mat: StandardMaterial3D = stripe.material_override
		var c: Color = mat.albedo_color
		if c.r < 0.5 or c.g < 0.3 or c.b > 0.3:
			print("FAIL _test_stripes_use_yellow_material_distinct_from_hull: Stripe albedo_color=%s not yellow-ish" % c)
			result = 1
		if mat == section0_mesh.material_override:
			print("FAIL _test_stripes_use_yellow_material_distinct_from_hull: Stripe uses the same material as the hull")
			result = 1
	station.free()
	return result

func _test_sections_are_animatable_bodies() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if not (station.get_node("Section0") is AnimatableBody3D):
		print("FAIL _test_sections_are_animatable_bodies: Section0 is not an AnimatableBody3D")
		result = 1
	station.free()
	return result

func _test_bridges_are_static_bodies() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if not (station.get_node("Bridge0") is StaticBody3D):
		print("FAIL _test_bridges_are_static_bodies: Bridge0 is not a StaticBody3D")
		result = 1
	station.free()
	return result

func _test_sections_have_matching_collision_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var result := 0
	var collision := section.get_node_or_null("Collision")
	if collision == null or not (collision is CollisionShape3D) or not ((collision as CollisionShape3D).shape is CylinderShape3D):
		print("FAIL _test_sections_have_matching_collision_shape: Section0 has no CollisionShape3D with a CylinderShape3D")
		result = 1
	else:
		var shape: CylinderShape3D = (collision as CollisionShape3D).shape
		if not is_equal_approx(shape.radius, 30.0) or not is_equal_approx(shape.height, 80.0):
			print("FAIL _test_sections_have_matching_collision_shape: radius=%f height=%f expected 30.0/80.0" % [shape.radius, shape.height])
			result = 1
	station.free()
	return result

func _test_bridges_have_matching_collision_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge: StaticBody3D = station.get_node("Bridge0")
	var result := 0
	var collision := bridge.get_node_or_null("Collision")
	if collision == null or not (collision is CollisionShape3D) or not ((collision as CollisionShape3D).shape is CylinderShape3D):
		print("FAIL _test_bridges_have_matching_collision_shape: Bridge0 has no CollisionShape3D with a CylinderShape3D")
		result = 1
	else:
		var shape: CylinderShape3D = (collision as CollisionShape3D).shape
		if not is_equal_approx(shape.radius, 9.0):
			print("FAIL _test_bridges_have_matching_collision_shape: radius=%f expected 9.0" % shape.radius)
			result = 1
	station.free()
	return result

func _test_section_collision_shapes_are_shared() -> int:
	var station := _make_station(4)
	station.build_station()
	var shape0: Shape3D = (station.get_node("Section0").get_node("Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("Section1").get_node("Collision") as CollisionShape3D).shape
	var result := 0
	if shape0 == null or shape0 != shape1:
		print("FAIL _test_section_collision_shapes_are_shared: Section0 and Section1 use different collision shape resources")
		result = 1
	station.free()
	return result

func _test_bridge_collision_shapes_are_shared() -> int:
	var station := _make_station(4)
	station.build_station()
	var shape0: Shape3D = (station.get_node("Bridge0").get_node("Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("Bridge1").get_node("Collision") as CollisionShape3D).shape
	var result := 0
	if shape0 == null or shape0 != shape1:
		print("FAIL _test_bridge_collision_shapes_are_shared: Bridge0 and Bridge1 use different collision shape resources")
		result = 1
	station.free()
	return result
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station.gd`
Expected: multiple failures — `Section0` is still a `MeshInstance3D` with no `Mesh`/`Collision` children, so `.get_node("Mesh")` calls fail and type checks (`is AnimatableBody3D`) fail.

- [ ] **Step 3: Rewrite `build_station()` in `scripts/torus_station.gd`**

Replace the `build_station()` function (the whole function, from `func build_station() -> void:` to the end of the file) with:

```gdscript
func build_station() -> void:
	for child in get_children():
		if child.name.begins_with("Section") or child.name.begins_with("Bridge"):
			remove_child(child)
			child.queue_free()

	var effective_planet_radius := _effective_planet_radius()
	var hull_material := _build_hull_material(TAU * section_radius, section_length)
	var stripe_material := _build_stripe_material()

	var section_mesh := CylinderMesh.new()
	section_mesh.top_radius = section_radius
	section_mesh.bottom_radius = section_radius
	section_mesh.height = section_length

	var section_shape := CylinderShape3D.new()
	section_shape.radius = section_radius
	section_shape.height = section_length

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(2.0, section_length, 2.0)

	var section_transforms := TorusGeometry.compute_section_transforms(effective_planet_radius, orbit_altitude, num_sections)
	for i in range(section_transforms.size()):
		var section := AnimatableBody3D.new()
		section.name = "Section%d" % i

		var section_mesh_instance := MeshInstance3D.new()
		section_mesh_instance.name = "Mesh"
		section_mesh_instance.mesh = section_mesh
		section_mesh_instance.material_override = hull_material
		section.add_child(section_mesh_instance)

		var section_collision := CollisionShape3D.new()
		section_collision.name = "Collision"
		section_collision.shape = section_shape
		section.add_child(section_collision)

		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe"
		stripe.mesh = stripe_mesh
		stripe.material_override = stripe_material
		stripe.transform.origin = Vector3(0.0, 0.0, section_radius)
		section.add_child(stripe)

		section.transform = section_transforms[i]
		add_child(section)

	var bridge_length := TorusGeometry.compute_bridge_length(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_mesh := CylinderMesh.new()
	bridge_mesh.top_radius = section_radius * 0.3
	bridge_mesh.bottom_radius = section_radius * 0.3
	bridge_mesh.height = max(bridge_length, 0.01)

	var bridge_shape := CylinderShape3D.new()
	bridge_shape.radius = section_radius * 0.3
	bridge_shape.height = max(bridge_length, 0.01)

	for i in range(bridge_transforms.size()):
		var bridge := StaticBody3D.new()
		bridge.name = "Bridge%d" % i

		var bridge_mesh_instance := MeshInstance3D.new()
		bridge_mesh_instance.name = "Mesh"
		bridge_mesh_instance.mesh = bridge_mesh
		bridge_mesh_instance.material_override = hull_material
		bridge.add_child(bridge_mesh_instance)

		var bridge_collision := CollisionShape3D.new()
		bridge_collision.name = "Collision"
		bridge_collision.shape = bridge_shape
		bridge.add_child(bridge_collision)

		bridge.transform = bridge_transforms[i]
		add_child(bridge)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station.gd`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Run the full existing suite to check for regressions**

```bash
cd /home/patrick/projects/playground/torus1
for f in tests/test_planet.gd tests/test_torus_geometry.gd tests/test_torus_station.gd tests/test_void_cruiser.gd tests/test_void_cruiser_physics.gd tests/test_world_rebase.gd tests/test_world_origin_rebase.gd tests/test_scene_wiring.gd; do
  echo "== $f =="
  /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script "$f" 2>&1 | tail -5
done
```

Expected: every file reports `ALL TESTS PASSED`.

- [ ] **Step 6: Run the live project via Godot MCP and check for errors**

Call `mcp__godot__run_project` with `projectPath: "/home/patrick/projects/playground/torus1"`, then `mcp__godot__get_debug_output`, then `mcp__godot__stop_project`.

Expected: `errors` contains only the pre-existing `libX11`/`libxkbcommon` linking warnings. No physics or node-structure errors — in particular, watch for anything mentioning `AnimatableBody3D`, `StaticBody3D`, or `CollisionShape3D`, and confirm startup with ~2000 sections + ~2000 bridges each carrying a body/collision shape doesn't visibly hang (compare startup time against Task 2's Step 7 run as a sanity baseline).

- [ ] **Step 7: Commit**

```bash
git add scripts/torus_station.gd tests/test_torus_station.gd
git commit -m "Give station sections and bridges collision shapes (AnimatableBody3D/StaticBody3D)"
```
