# Station Interior Access (Piece A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dock the void-cruiser at a non-rotating collar on any bridge (HUD `DOCK  [F]`, key F), switch to a separate interior world (the bridge tube plus the two sections it joins, bare terrain, suns on the axis), fly it in a slower HUD-less internal-cruiser, and undock back outside at the same port.

**Architecture:** Pure helpers (`docking_rules.gd`, `interior_layout.gd`, a new `TorusGeometry` function) carry the math. The station gains a `DockingCollar%d` static body per bridge. `interior_world.gd` builds the interior in code: shared terrain chunk mesh/shape tiled 16×20 per section, caps, suns, a 4-segment bridge tube, and a dock. The void-cruiser's flight code moves into a shared `flying_craft.gd` base that `internal_cruiser.gd` also extends. A `GameMode` node in the main scene detaches the outside world (keeping it in memory), adds the interior, and swaps back, with a black fade.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-24-station-interior-access-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (runs every `tests/*.gd`; each file must print exactly `ALL TESTS PASSED`; exit 0). If that script is gone, recreate it: loop over `tests/*.gd`, grep each run's output for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep result is exactly `ALL TESTS PASSED`.
- **Reading RED:** a call to a missing method prints `SCRIPT ERROR: ... Nonexistent function` and the file may still end with `ALL TESTS PASSED`; a missing preload prints `Parse Error`. RED is confirmed by those lines or `FAIL` lines, never by the summary alone.
- **Fresh worktree:** before the first test run in a new worktree, run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import` once.
- **Off-tree vs in-tree:** `global_position`, `global_transform`, `to_local` and `to_global` error out on nodes not inside the tree. Off-tree tests (`_init()`) must use `transform` chains only; anything needing global coordinates, physics, cameras or input goes in an in-tree test (`_initialize()` + `await process_frame` / `await physics_frame`), as in `tests/test_torus_station_physics.gd`.
- `find_children()` on code-built nodes must pass `owned = false` (no owner is set).
- GDScript: write explicit types where a builtin returns Variant (`var x: float = ...`). Do not name locals `basis`, `transform`, `position`, `sign` (they shadow Node3D members or builtins).
- **Mesh winding (verified empirically):** with `SurfaceTool`, triangles `(p00, p10, p01)` and `(p10, p11, p01)` from `_add_quad` get normals from `generate_normals()` that, for a cylinder band `p00=(r,a0,z0) p10=(r,a1,z0) p01=(r,a0,z1)`, point toward the axis; for an annulus `p00=inner(a0) p10=outer(a0) p01=inner(a1)` they point to -Z.
- The renderer lights each object with at most 8 lights (`rendering/limits/opengl/max_lights_per_object` = 8).
- Ship axes: forward -Z, up +Y. Station bridge/collar local frame: +X = world up (radial "out" of the ring plane), +Y = bridge axis (ring tangent).
- Code and comments in English; docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage anything under `.claude/worktrees/`. Add Godot-generated `.uid` files for new scripts/tests to the same commit.
- Live check (the Godot MCP server is not connected in this session): `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR"` must print nothing. Do not launch a windowed run: the game is fullscreen and would take over the user's screen.

## Review Focus

1. **World-origin rebase while docking** — the outside ship is thousands of km from the origin next to a port; a rebase can fire between the prompt check and the key press, and right after undocking. Distances must stay right. Tests: all of Task 8 run on the real scene with the rebase node active.
2. **F pressed again during the fade** — must not start a second transition or build a second interior. Test: `_test_second_dock_press_during_transition_is_ignored` (Task 8).
3. **Station rebuilt (editor button / `build_station()` twice)** — must not leave orphan collars. Test: updated `_test_rebuild_does_not_leak` (Task 2).
4. **Lights over the 8-per-object limit** — any terrain chunk or tube segment reached by more than 7 axis lights (the dock light needs the 8th slot) shades wrongly. Tests: `_test_every_terrain_chunk_gets_one_to_seven_axis_lights`, `_test_every_bridge_tube_segment_gets_one_to_seven_axis_lights` (Task 3).
5. **Triangle-mesh collision against a turning hull** — the teleport bug came from shape contacts; the new collar and terrain use trimesh shapes. Tests: `_test_rotating_hull_resting_on_docking_collar_does_not_jump` (Task 2), `_test_rotating_hull_resting_on_terrain_does_not_jump` (Task 4).

---

### Task 1: Docking rule and nearest bridge

**Files:**
- Create: `scripts/docking_rules.gd`, `tests/test_docking_rules.gd`
- Modify: `scripts/torus_geometry.gd` (append a function), `tests/test_torus_geometry.gd`

**Interfaces:**
- Produces: `DockingRules.DOCK_RANGE := 150.0`, `DockingRules.DOCK_MAX_SPEED := 20.0`, `static func can_dock(distance: float, speed: float) -> bool`; `TorusGeometry.compute_nearest_bridge_index(station_local_position: Vector3, num_sections: int) -> int` (`-1` if `num_sections < 1`).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_docking_rules.gd`:

```gdscript
extends SceneTree

const DockingRules = preload("res://scripts/docking_rules.gd")

func _init():
	var failures := 0
	failures += _check("close and slow", DockingRules.can_dock(100.0, 5.0), true)
	failures += _check("exactly at both limits", DockingRules.can_dock(150.0, 20.0), true)
	failures += _check("just too far", DockingRules.can_dock(150.1, 0.0), false)
	failures += _check("just too fast", DockingRules.can_dock(0.0, 20.1), false)
	failures += _check("far and fast", DockingRules.can_dock(5000.0, 300.0), false)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _check(case_name: String, actual: bool, expected: bool) -> int:
	if actual != expected:
		print("FAIL _test_can_dock (%s): got %s expected %s" % [case_name, actual, expected])
		return 1
	return 0
```

In `tests/test_torus_geometry.gd`, add after `failures += _test_section_angular_velocity_zero_radius_does_not_crash()`:

```gdscript
	failures += _test_nearest_bridge_index_at_each_bridge()
	failures += _test_nearest_bridge_index_either_side_of_section_zero()
	failures += _test_nearest_bridge_index_ignores_height()
	failures += _test_nearest_bridge_index_degenerate()
```

and append at the end of the file:

```gdscript
func _ring_point(theta: float, height: float) -> Vector3:
	return Vector3(cos(theta) * 2000.0, height, sin(theta) * 2000.0)

func _test_nearest_bridge_index_at_each_bridge() -> int:
	var step := TAU / 4.0
	var result := 0
	for i in range(4):
		var index: int = TorusGeometry.compute_nearest_bridge_index(_ring_point(i * step + step * 0.5, 0.0), 4)
		if index != i:
			print("FAIL _test_nearest_bridge_index_at_each_bridge: at bridge %d got %d" % [i, index])
			result = 1
	return result

func _test_nearest_bridge_index_either_side_of_section_zero() -> int:
	# Section 0 sits at angle 0, between bridge 3 (before) and bridge 0 (after).
	var step := TAU / 4.0
	var result := 0
	var after: int = TorusGeometry.compute_nearest_bridge_index(_ring_point(step * 0.1, 0.0), 4)
	var before: int = TorusGeometry.compute_nearest_bridge_index(_ring_point(-step * 0.1, 0.0), 4)
	if after != 0 or before != 3:
		print("FAIL _test_nearest_bridge_index_either_side_of_section_zero: after=%d (expected 0) before=%d (expected 3)" % [after, before])
		result = 1
	return result

func _test_nearest_bridge_index_ignores_height() -> int:
	var step := TAU / 4.0
	var index: int = TorusGeometry.compute_nearest_bridge_index(_ring_point(2.0 * step + step * 0.5, 800.0), 4)
	if index != 2:
		print("FAIL _test_nearest_bridge_index_ignores_height: got %d expected 2" % index)
		return 1
	return 0

func _test_nearest_bridge_index_degenerate() -> int:
	var index: int = TorusGeometry.compute_nearest_bridge_index(_ring_point(0.3, 0.0), 0)
	if index != -1:
		print("FAIL _test_nearest_bridge_index_degenerate: got %d expected -1" % index)
		return 1
	return 0
```

- [ ] **Step 2: Run to verify they fail**

Run `tests/test_docking_rules.gd` — Expected: `Parse Error` (preload of `docking_rules.gd` does not exist).
Run `tests/test_torus_geometry.gd` — Expected: `Parse Error: Static function "compute_nearest_bridge_index()" not found`.

- [ ] **Step 3: Implement**

Create `scripts/docking_rules.gd`:

```gdscript
extends RefCounted

# One rule to dock at a station port from outside and to undock from the
# interior platform: close enough and slow enough.
const DOCK_RANGE := 150.0
const DOCK_MAX_SPEED := 20.0

static func can_dock(distance: float, speed: float) -> bool:
	return distance <= DOCK_RANGE and speed <= DOCK_MAX_SPEED
```

Append to `scripts/torus_geometry.gd`:

```gdscript
# Bridge i sits at angle i * step + step / 2 around the ring (see
# compute_bridge_transforms): round the position's angle to the nearest one.
static func compute_nearest_bridge_index(station_local_position: Vector3, num_sections: int) -> int:
	if num_sections < 1:
		return -1
	var step := TAU / num_sections
	var theta: float = fposmod(atan2(station_local_position.z, station_local_position.x), TAU)
	var index: int = roundi((theta - step * 0.5) / step)
	return posmod(index, num_sections)
```

- [ ] **Step 4: Run to verify they pass** — both files print `ALL TESTS PASSED`.

- [ ] **Step 5: Full suite** — every file `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add scripts/docking_rules.gd tests/test_docking_rules.gd scripts/torus_geometry.gd tests/test_torus_geometry.gd
git commit -m "$(cat <<'EOF'
Add the docking rule and nearest-bridge lookup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Docking collars on the station

**Files:**
- Modify: `scripts/torus_station.gd`, `tests/test_torus_station.gd`, `tests/test_torus_station_physics.gd`

**Interfaces:**
- Consumes: `TorusGeometry.compute_nearest_bridge_index` (Task 1).
- Produces on the station: `const BRIDGE_RADIUS_RATIO := 0.3`, `COLLAR_INNER_RATIO := 1.05`, `COLLAR_OUTER_RATIO := 1.25`, `PORT_OFFSET_RATIO := 0.01`; `func get_bridge_radius() -> float`; `func get_bridge_length() -> float`; `func nearest_bridge_index(world_position: Vector3) -> int` (in-tree only); `func get_docking_port(bridge_index: int) -> Node3D`. Children `DockingCollar%d` (`StaticBody3D`, same transform as `Bridge%d`) with `Mesh` (shared `TorusMesh`), `Collision` (shared `ConcavePolygonShape3D`), `Port` (`Node3D` at local `(outer_radius + bridge_radius * 0.01, 0, 0)`) → `Platform` (`MeshInstance3D`).

- [ ] **Step 1: Write the failing off-tree tests**

In `tests/test_torus_station.gd`:
- In `_test_build_station_child_count` and `_test_rebuild_does_not_leak`, change the expected count `8` to `12` in both the `if` and the `print` (4 sections + 4 bridges + 4 collars).
- In `_test_build_station_preserves_unrelated_children`, change `9` to `13` (and the message's "8 generated" to "12 generated").
- Add after `failures += _test_bridge_collision_shapes_are_shared()`:

```gdscript
	failures += _test_each_bridge_has_a_docking_collar()
	failures += _test_docking_collars_share_mesh_and_shape()
	failures += _test_rotate_sections_does_not_rotate_docking_collars()
	failures += _test_bridge_radius_and_length_helpers()
```

- Append:

```gdscript
func _test_each_bridge_has_a_docking_collar() -> int:
	# Small station: bridge radius 9 -> collar radii 9.45 / 11.25, port at 11.34.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	for i in range(4):
		var collar := station.get_node_or_null("DockingCollar%d" % i)
		if collar == null or not (collar is StaticBody3D):
			print("FAIL _test_each_bridge_has_a_docking_collar: no DockingCollar%d StaticBody3D" % i)
			result = 1
			continue
		var bridge: Node3D = station.get_node("Bridge%d" % i)
		if not (collar as Node3D).transform.is_equal_approx(bridge.transform):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d transform differs from Bridge%d" % [i, i])
			result = 1
		var mesh_node := collar.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node == null or not (mesh_node.mesh is TorusMesh):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d has no TorusMesh" % i)
			result = 1
		else:
			var torus: TorusMesh = mesh_node.mesh
			if not is_equal_approx(torus.inner_radius, 9.45) or not is_equal_approx(torus.outer_radius, 11.25):
				print("FAIL _test_each_bridge_has_a_docking_collar: radii %f / %f expected 9.45 / 11.25" % [torus.inner_radius, torus.outer_radius])
				result = 1
		var collision := collar.get_node_or_null("Collision") as CollisionShape3D
		if collision == null or not (collision.shape is ConcavePolygonShape3D):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d has no ConcavePolygonShape3D" % i)
			result = 1
		var port := collar.get_node_or_null("Port") as Node3D
		if port == null or not port.position.is_equal_approx(Vector3(11.34, 0.0, 0.0)):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d Port missing or at %s, expected (11.34, 0, 0)" % [i, str(port.position) if port else "none"])
			result = 1
		elif port.get_node_or_null("Platform") == null:
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d/Port has no Platform" % i)
			result = 1
	station.free()
	return result

func _test_docking_collars_share_mesh_and_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var mesh0: Mesh = (station.get_node("DockingCollar0/Mesh") as MeshInstance3D).mesh
	var mesh1: Mesh = (station.get_node("DockingCollar1/Mesh") as MeshInstance3D).mesh
	var shape0: Shape3D = (station.get_node("DockingCollar0/Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("DockingCollar1/Collision") as CollisionShape3D).shape
	if mesh0 == null or mesh0 != mesh1 or shape0 == null or shape0 != shape1:
		print("FAIL _test_docking_collars_share_mesh_and_shape: collars do not share one mesh and one shape")
		result = 1
	station.free()
	return result

func _test_rotate_sections_does_not_rotate_docking_collars() -> int:
	# The collar must stay still so its port can be docked at.
	var station := _make_station(4)
	station.build_station()
	var collar: Node3D = station.get_node("DockingCollar0")
	var bridge: Node3D = station.get_node("Bridge0")
	var collar_before: Transform3D = collar.transform
	var bridge_before: Transform3D = bridge.transform
	station._rotate_sections(1.0)
	var result := 0
	if not collar.transform.is_equal_approx(collar_before):
		print("FAIL _test_rotate_sections_does_not_rotate_docking_collars: the collar rotated")
		result = 1
	if bridge.transform.is_equal_approx(bridge_before):
		print("FAIL _test_rotate_sections_does_not_rotate_docking_collars: the bridge did not rotate (test setup broken)")
		result = 1
	station.free()
	return result

func _test_bridge_radius_and_length_helpers() -> int:
	var station := _make_station(4)
	var result := 0
	if not is_equal_approx(station.get_bridge_radius(), 9.0):
		print("FAIL _test_bridge_radius_and_length_helpers: bridge radius %f expected 9.0" % station.get_bridge_radius())
		result = 1
	var expected_length: float = TorusGeometry.compute_bridge_length(500.0, 1500.0, 4, 80.0)
	if not is_equal_approx(station.get_bridge_length(), expected_length):
		print("FAIL _test_bridge_radius_and_length_helpers: bridge length %f expected %f" % [station.get_bridge_length(), expected_length])
		result = 1
	station.free()
	return result
```

- [ ] **Step 2: Write the failing in-tree tests**

In `tests/test_torus_station_physics.gd`, add after `_failures += await _test_rotating_hull_resting_on_bridge_does_not_jump()`:

```gdscript
	_failures += await _test_nearest_bridge_index_finds_each_port()
	_failures += await _test_rotating_hull_resting_on_docking_collar_does_not_jump()
```

and append:

```gdscript
func _test_nearest_bridge_index_finds_each_port() -> int:
	var station := _make_station()
	root.add_child(station)
	station.set_process(false)
	station.build_station()
	await process_frame
	var result := 0
	for i in range(station.num_sections):
		var port: Node3D = station.get_docking_port(i)
		if port != station.get_node("DockingCollar%d/Port" % i):
			print("FAIL _test_nearest_bridge_index_finds_each_port: get_docking_port(%d) is not DockingCollar%d/Port" % [i, i])
			result = 1
			continue
		var index: int = station.nearest_bridge_index(port.global_position)
		if index != i:
			print("FAIL _test_nearest_bridge_index_finds_each_port: port %d resolved to bridge %d" % [i, index])
			result = 1
	station.free()
	return result

func _test_rotating_hull_resting_on_docking_collar_does_not_jump() -> int:
	# Same failure mode as the teleport bug, on the collar's trimesh shape.
	var station := _make_full_scale_station()
	root.add_child(station)
	station.set_process(false)
	station.build_station()
	await physics_frame
	var outer_radius: float = station.get_bridge_radius() * 1.25
	var biggest: float = await _biggest_shove_while_turning_on(station.get_node("DockingCollar0"), outer_radius, 0.0)
	var result := 0
	if biggest > 2.0:
		print("FAIL _test_rotating_hull_resting_on_docking_collar_does_not_jump: a still, turning hull was shoved %.1f m in one tick" % biggest)
		result = 1
	station.free()
	return result
```

- [ ] **Step 3: Run to verify they fail**

`tests/test_torus_station.gd` — Expected: `FAIL` lines for the child counts (8 vs 12, 9 vs 13), `no DockingCollar0 StaticBody3D`, and `SCRIPT ERROR ... Nonexistent function 'get_bridge_radius'`.
`tests/test_torus_station_physics.gd` — Expected: `SCRIPT ERROR ... Nonexistent function 'get_docking_port'` / `'get_bridge_radius'`.

- [ ] **Step 4: Implement** in `scripts/torus_station.gd`:

Add after `const HULL_LIGHTS_ENERGY := 3.0`:

```gdscript
const BRIDGE_RADIUS_RATIO := 0.3
# A docking collar around the middle of every bridge. It does not spin, so its
# port stays still for docking. Sizes are fractions of the bridge radius.
const COLLAR_INNER_RATIO := 1.05
const COLLAR_OUTER_RATIO := 1.25
const PORT_OFFSET_RATIO := 0.01
const PORT_SIZE_RATIO := Vector3(0.007, 0.1, 0.1)
const PORT_COLOR := Color(0.2, 1.0, 0.35)
const COLLAR_COLOR := Color(0.35, 0.37, 0.4)
```

Add after `_effective_planet_radius()`:

```gdscript
func get_bridge_radius() -> float:
	return section_radius * BRIDGE_RADIUS_RATIO

func get_bridge_length() -> float:
	return TorusGeometry.compute_bridge_length(_effective_planet_radius(), orbit_altitude, num_sections, section_length)

# In-tree only (uses the station's global transform).
func nearest_bridge_index(world_position: Vector3) -> int:
	return TorusGeometry.compute_nearest_bridge_index(to_local(world_position), num_sections)

func get_docking_port(bridge_index: int) -> Node3D:
	return get_node("DockingCollar%d/Port" % bridge_index)
```

In `build_station()`:
- The cleanup condition becomes `if child.name.begins_with("Section") or child.name.begins_with("Bridge") or child.name.begins_with("DockingCollar"):`.
- Replace both `section_radius * 0.3` with `get_bridge_radius()`.
- At the end of the function (after the bridge loop) add `_build_docking_collars(bridge_transforms)`.

Add the new function:

```gdscript
func _build_docking_collars(bridge_transforms: Array[Transform3D]) -> void:
	var bridge_radius := get_bridge_radius()
	var collar_mesh := TorusMesh.new()
	collar_mesh.inner_radius = bridge_radius * COLLAR_INNER_RATIO
	collar_mesh.outer_radius = bridge_radius * COLLAR_OUTER_RATIO
	# Triangle shape from the visible mesh: no analytic shape (see the
	# CylinderShape3D teleport note on _build_prism_shape).
	var collar_shape := collar_mesh.create_trimesh_shape()
	var collar_material := StandardMaterial3D.new()
	collar_material.albedo_color = COLLAR_COLOR
	collar_material.metallic = 0.6
	collar_material.roughness = 0.4

	var port_mesh := BoxMesh.new()
	port_mesh.size = PORT_SIZE_RATIO * bridge_radius
	# Glowing, not a real light: 2000 extra lights would cost too much.
	var port_material := StandardMaterial3D.new()
	port_material.albedo_color = PORT_COLOR
	port_material.emission_enabled = true
	port_material.emission = PORT_COLOR
	port_material.emission_energy_multiplier = 3.0

	for i in range(bridge_transforms.size()):
		# Named neither Section nor Bridge: _rotate_sections leaves it still.
		var collar := StaticBody3D.new()
		collar.name = "DockingCollar%d" % i
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = collar_mesh
		mesh_instance.material_override = collar_material
		collar.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = collar_shape
		collar.add_child(collision)
		var port := Node3D.new()
		port.name = "Port"
		port.position = Vector3(collar_mesh.outer_radius + bridge_radius * PORT_OFFSET_RATIO, 0.0, 0.0)
		var platform := MeshInstance3D.new()
		platform.name = "Platform"
		platform.mesh = port_mesh
		platform.material_override = port_material
		port.add_child(platform)
		collar.add_child(port)
		collar.transform = bridge_transforms[i]
		add_child(collar)
```

- [ ] **Step 5: Run to verify they pass** — both files `ALL TESTS PASSED`.

- [ ] **Step 6: Full suite** — every file `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add scripts/torus_station.gd tests/test_torus_station.gd tests/test_torus_station_physics.gd
git commit -m "$(cat <<'EOF'
Add a non-rotating docking collar with a glowing port to every bridge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Interior layout math

**Files:**
- Create: `scripts/interior_layout.gd`, `tests/test_interior_layout.gd`

**Interfaces:**
- Produces (all `static`): `section_center_z(bridge_length: float, section_length: float, side: float) -> float`; `sun_positions(center_z: float, section_length: float, spacing: float) -> PackedVector3Array`; `cylinder_point(radius: float, angle: float, z: float) -> Vector3`; `count_lights_reaching_band(radius: float, z0: float, z1: float, lights: PackedVector2Array) -> int` (each light: `x` = position on the axis, `y` = range).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_interior_layout.gd`:

```gdscript
extends SceneTree

const InteriorLayout = preload("res://scripts/interior_layout.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

const SECTION_RADIUS := 2000.0
const SECTION_LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const SUN_RANGE := 2600.0
const BRIDGE_LIGHT_RANGE := 900.0

var _bridge_length: float = TorusGeometry.compute_bridge_length(1737400.0, 5212200.0, 2000, SECTION_LENGTH)

func _init():
	var failures := 0
	failures += _test_sections_sit_either_side_of_the_bridge()
	failures += _test_twenty_suns_one_per_kilometre()
	failures += _test_cylinder_point_on_the_wall()
	failures += _test_every_terrain_chunk_gets_one_to_seven_axis_lights()
	failures += _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _all_axis_lights() -> PackedVector2Array:
	var lights := PackedVector2Array()
	for side in [-1.0, 1.0]:
		var center: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, side)
		for sun in InteriorLayout.sun_positions(center, SECTION_LENGTH, 1000.0):
			lights.append(Vector2(sun.z, SUN_RANGE))
	for k in range(3):
		lights.append(Vector2(_bridge_length * (k - 1) / 3.0, BRIDGE_LIGHT_RANGE))
	return lights

func _test_sections_sit_either_side_of_the_bridge() -> int:
	var ahead: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, -1.0)
	var behind: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, 1.0)
	var result := 0
	# Each section's near end touches the bridge's end.
	if not is_equal_approx(ahead + SECTION_LENGTH * 0.5, -_bridge_length * 0.5) or not is_equal_approx(behind - SECTION_LENGTH * 0.5, _bridge_length * 0.5):
		print("FAIL _test_sections_sit_either_side_of_the_bridge: centres %f / %f with bridge length %f" % [ahead, behind, _bridge_length])
		result = 1
	return result

func _test_twenty_suns_one_per_kilometre() -> int:
	var center: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, -1.0)
	var suns: PackedVector3Array = InteriorLayout.sun_positions(center, SECTION_LENGTH, 1000.0)
	var result := 0
	var start: float = center - SECTION_LENGTH * 0.5
	if suns.size() != 20:
		print("FAIL _test_twenty_suns_one_per_kilometre: %d suns expected 20" % suns.size())
		return 1
	for k in range(20):
		var expected := Vector3(0.0, 0.0, start + 500.0 + 1000.0 * k)
		if not suns[k].is_equal_approx(expected):
			print("FAIL _test_twenty_suns_one_per_kilometre: sun %d at %s expected %s" % [k, suns[k], expected])
			result = 1
	return result

func _test_cylinder_point_on_the_wall() -> int:
	var point: Vector3 = InteriorLayout.cylinder_point(SECTION_RADIUS, 1.0, -300.0)
	if not is_equal_approx(Vector2(point.x, point.y).length(), SECTION_RADIUS) or not is_equal_approx(point.z, -300.0) or not is_equal_approx(atan2(point.y, point.x), 1.0):
		print("FAIL _test_cylinder_point_on_the_wall: %s" % point)
		return 1
	return 0

func _test_every_terrain_chunk_gets_one_to_seven_axis_lights() -> int:
	# 8 lights per object at most; the 8th slot is left for the dock light.
	var lights := _all_axis_lights()
	var result := 0
	for side in [-1.0, 1.0]:
		var center: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, side)
		var start: float = center - SECTION_LENGTH * 0.5
		for along in range(20):
			var z0: float = start + along * 1000.0
			var count: int = InteriorLayout.count_lights_reaching_band(SECTION_RADIUS, z0, z0 + 1000.0, lights)
			if count < 1 or count > 7:
				print("FAIL _test_every_terrain_chunk_gets_one_to_seven_axis_lights: side %s chunk %d reached by %d lights" % [side, along, count])
				result = 1
	return result

func _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights() -> int:
	var lights := _all_axis_lights()
	var result := 0
	var segment_length: float = _bridge_length / 4.0
	for k in range(4):
		var z0: float = -_bridge_length * 0.5 + k * segment_length
		var count: int = InteriorLayout.count_lights_reaching_band(BRIDGE_RADIUS, z0, z0 + segment_length, lights)
		if count < 1 or count > 7:
			print("FAIL _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights: segment %d reached by %d lights" % [k, count])
			result = 1
	return result
```

- [ ] **Step 2: Run to verify it fails** — Expected: `Parse Error` (preload of `interior_layout.gd`).

- [ ] **Step 3: Implement** — create `scripts/interior_layout.gd`:

```gdscript
extends RefCounted

# Interior world layout: the docked bridge is centred on the origin with its
# axis along Z; the section "ahead" (side -1) lies toward -Z, the section
# "behind" (side +1) toward +Z. Built straight: the real ring's 0.18 degree
# bend between neighbours is ignored.

static func section_center_z(bridge_length: float, section_length: float, side: float) -> float:
	return side * (bridge_length + section_length) * 0.5

# One light at the middle of every `spacing` metres of the section.
static func sun_positions(center_z: float, section_length: float, spacing: float) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var count: int = roundi(section_length / spacing)
	var start: float = center_z - section_length * 0.5
	for k in range(count):
		positions.append(Vector3(0.0, 0.0, start + spacing * (k + 0.5)))
	return positions

static func cylinder_point(radius: float, angle: float, z: float) -> Vector3:
	return Vector3(cos(angle) * radius, sin(angle) * radius, z)

# How many lights on the axis reach a band of the cylinder wall at `radius`
# between z0 and z1. lights: x = position along the axis, y = light range.
static func count_lights_reaching_band(radius: float, z0: float, z1: float, lights: PackedVector2Array) -> int:
	var count := 0
	for light in lights:
		var dz: float = maxf(0.0, maxf(z0 - light.x, light.x - z1))
		if sqrt(radius * radius + dz * dz) < light.y:
			count += 1
	return count
```

- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/interior_layout.gd tests/test_interior_layout.gd
git commit -m "$(cat <<'EOF'
Add interior layout math: section placement, suns, light-limit check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Interior world

**Files:**
- Create: `scripts/interior_world.gd`, `tests/test_interior_world.gd`, `tests/test_interior_world_physics.gd`

**Interfaces:**
- Consumes: `InteriorLayout` (Task 3).
- Produces: `interior_world.gd` (`Node3D`) with vars `section_radius`, `section_length`, `bridge_radius`, `bridge_length` (defaults 2000 / 20000 / 600 / 1834.0, set before `build()`); `func build() -> void`; `func get_spawn_transform() -> Transform3D`; `func get_dock_position() -> Vector3` (world assumed at the origin); `func set_undock_ready(ready: bool) -> void`. Node names as in the spec tree: `SectionAhead`/`SectionBehind` → `Chunk_%02d_%02d`, `NearCap`, `FarCap`, `Sun_%02d` (→ `Globe`, `Light`); `BridgeTube` → `Segment_%d`; `BridgeLight_%d`; `Dock` → `Platform`, `Light`, `Sign`. Constants `SIGN_READY_COLOR`, `SIGN_IDLE_COLOR`, `SIGN_TEXT := "UNDOCK  [F]"`.

- [ ] **Step 1: Write the failing off-tree tests**

Create `tests/test_interior_world.gd`:

```gdscript
extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const BRIDGE_LENGTH := 1834.0

func _init():
	var failures := 0
	failures += _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape()
	failures += _test_terrain_vertices_on_the_wall_facing_the_axis()
	failures += _test_terrain_chunks_tile_the_whole_wall()
	failures += _test_near_cap_open_far_cap_closed_both_facing_in()
	failures += _test_twenty_suns_per_section_on_the_axis()
	failures += _test_bridge_tube_four_segments_facing_the_axis()
	failures += _test_dock_platform_spawn_and_sign()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_world() -> Node3D:
	var world: Node3D = InteriorWorldScript.new()
	world.section_radius = RADIUS
	world.section_length = LENGTH
	world.bridge_radius = BRIDGE_RADIUS
	world.bridge_length = BRIDGE_LENGTH
	world.build()
	return world

func _section_start(side: float) -> float:
	var center: float = side * (BRIDGE_LENGTH + LENGTH) * 0.5
	return center - LENGTH * 0.5

# Every vertex of `mesh` placed by `xform`: at `radius` from the axis, normal
# pointing toward the axis.
func _check_wall(test_name: String, mesh: Mesh, xform: Transform3D, radius: float) -> int:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(vertices.size()):
		var v: Vector3 = xform * vertices[i]
		var n: Vector3 = xform.basis * normals[i]
		if absf(Vector2(v.x, v.y).length() - radius) > 0.01:
			print("FAIL %s: vertex %s is %.3f m from the axis, expected %.1f" % [test_name, v, Vector2(v.x, v.y).length(), radius])
			return 1
		if n.dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
			print("FAIL %s: normal %s at %s points away from the axis" % [test_name, n, v])
			return 1
	return 0

func _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape() -> int:
	var world := _make_world()
	var result := 0
	var first_mesh: Mesh = null
	var first_shape: Shape3D = null
	for section_name in ["SectionAhead", "SectionBehind"]:
		var section := world.get_node_or_null(section_name)
		if section == null:
			print("FAIL _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape: no %s" % section_name)
			result = 1
			continue
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape: %s has %d chunks, expected 320" % [section_name, chunks.size()])
			result = 1
		for chunk in chunks:
			var mesh: Mesh = (chunk.get_node("Mesh") as MeshInstance3D).mesh
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			if first_mesh == null:
				first_mesh = mesh
				first_shape = shape
			if mesh != first_mesh or shape != first_shape or not (shape is ConcavePolygonShape3D):
				print("FAIL _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape: %s/%s does not share the chunk mesh and trimesh shape" % [section_name, chunk.name])
				result = 1
				break
	world.free()
	return result

func _test_terrain_vertices_on_the_wall_facing_the_axis() -> int:
	var world := _make_world()
	var chunk: Node3D = world.get_node("SectionAhead/Chunk_03_07")
	var mesh: Mesh = (chunk.get_node("Mesh") as MeshInstance3D).mesh
	var result := _check_wall("_test_terrain_vertices_on_the_wall_facing_the_axis", mesh, chunk.transform, RADIUS)
	world.free()
	return result

func _test_terrain_chunks_tile_the_whole_wall() -> int:
	var world := _make_world()
	var result := 0
	for side in [-1.0, 1.0]:
		var section_name := "SectionAhead" if side < 0.0 else "SectionBehind"
		var first: Node3D = world.get_node("%s/Chunk_00_00" % section_name)
		var last: Node3D = world.get_node("%s/Chunk_15_19" % section_name)
		var start: float = _section_start(side)
		if not is_equal_approx(first.transform.origin.z, start) or not is_equal_approx(last.transform.origin.z + 1000.0, start + LENGTH):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: %s chunks span %f..%f expected %f..%f" % [section_name, first.transform.origin.z, last.transform.origin.z + 1000.0, start, start + LENGTH])
			result = 1
		var last_angle: float = atan2(last.transform.basis.x.y, last.transform.basis.x.x)
		if not is_equal_approx(fposmod(last_angle, TAU), 15.0 * TAU / 16.0):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: %s last chunk turned %f rad, expected %f" % [section_name, last_angle, 15.0 * TAU / 16.0])
			result = 1
	world.free()
	return result

func _cap_min_radius_and_facing(cap: Node3D) -> Array:
	var mesh: Mesh = (cap.get_node("Mesh") as MeshInstance3D).mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var min_radius := INF
	for v in vertices:
		min_radius = minf(min_radius, Vector2(v.x, v.y).length())
	var facing_z: float = (cap.transform.basis * normals[0]).z
	return [min_radius, facing_z]

func _test_near_cap_open_far_cap_closed_both_facing_in() -> int:
	var world := _make_world()
	var result := 0
	for side in [-1.0, 1.0]:
		var section_name := "SectionAhead" if side < 0.0 else "SectionBehind"
		var near_cap: Node3D = world.get_node("%s/NearCap" % section_name)
		var far_cap: Node3D = world.get_node("%s/FarCap" % section_name)
		var near: Array = _cap_min_radius_and_facing(near_cap)
		var far: Array = _cap_min_radius_and_facing(far_cap)
		# Into the section = the direction of `side` along Z for the near cap.
		if absf(near[0] - BRIDGE_RADIUS) > 0.01 or signf(near[1]) != side or not is_equal_approx(near_cap.transform.origin.z, side * BRIDGE_LENGTH * 0.5):
			print("FAIL _test_near_cap_open_far_cap_closed_both_facing_in: %s near cap hole %f facing %f at z %f" % [section_name, near[0], near[1], near_cap.transform.origin.z])
			result = 1
		if far[0] > 0.01 or signf(far[1]) != -side:
			print("FAIL _test_near_cap_open_far_cap_closed_both_facing_in: %s far cap hole %f facing %f" % [section_name, far[0], far[1]])
			result = 1
		if not (near_cap is StaticBody3D) or not ((near_cap.get_node("Collision") as CollisionShape3D).shape is ConcavePolygonShape3D):
			print("FAIL _test_near_cap_open_far_cap_closed_both_facing_in: %s near cap has no trimesh collision" % section_name)
			result = 1
	world.free()
	return result

func _test_twenty_suns_per_section_on_the_axis() -> int:
	var world := _make_world()
	var result := 0
	for side in [-1.0, 1.0]:
		var section_name := "SectionAhead" if side < 0.0 else "SectionBehind"
		var section := world.get_node(section_name)
		var suns := section.find_children("Sun_*", "Node3D", false, false)
		if suns.size() != 20:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s has %d suns" % [section_name, suns.size()])
			result = 1
			continue
		var first: Node3D = section.get_node("Sun_00")
		if not first.position.is_equal_approx(Vector3(0.0, 0.0, _section_start(side) + 500.0)):
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s Sun_00 at %s" % [section_name, first.position])
			result = 1
		var light := first.get_node_or_null("Light") as OmniLight3D
		if light == null or not is_equal_approx(light.omni_range, 2600.0) or light.shadow_enabled:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s Sun_00 light missing, wrong range, or casting shadows" % section_name)
			result = 1
		if first.get_node_or_null("Globe") == null:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s Sun_00 has no Globe" % section_name)
			result = 1
	world.free()
	return result

func _test_bridge_tube_four_segments_facing_the_axis() -> int:
	var world := _make_world()
	var result := 0
	for k in range(4):
		var segment := world.get_node_or_null("BridgeTube/Segment_%d" % k) as StaticBody3D
		if segment == null:
			print("FAIL _test_bridge_tube_four_segments_facing_the_axis: no Segment_%d" % k)
			result = 1
			continue
		if not is_equal_approx(segment.position.z, -BRIDGE_LENGTH * 0.5 + k * BRIDGE_LENGTH / 4.0):
			print("FAIL _test_bridge_tube_four_segments_facing_the_axis: Segment_%d at z %f" % [k, segment.position.z])
			result = 1
		var mesh: Mesh = (segment.get_node("Mesh") as MeshInstance3D).mesh
		result = maxi(result, _check_wall("_test_bridge_tube_four_segments_facing_the_axis", mesh, segment.transform, BRIDGE_RADIUS))
	for k in range(3):
		var light := world.get_node_or_null("BridgeLight_%d" % k) as OmniLight3D
		if light == null or not light.position.is_equal_approx(Vector3(0.0, 0.0, BRIDGE_LENGTH * (k - 1) / 3.0)):
			print("FAIL _test_bridge_tube_four_segments_facing_the_axis: BridgeLight_%d missing or misplaced" % k)
			result = 1
	world.free()
	return result

func _test_dock_platform_spawn_and_sign() -> int:
	var world := _make_world()
	var result := 0
	var platform := world.get_node_or_null("Dock/Platform") as StaticBody3D
	var expected_platform := Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)
	if platform == null or not platform.position.is_equal_approx(expected_platform):
		print("FAIL _test_dock_platform_spawn_and_sign: platform missing or not at %s" % expected_platform)
		world.free()
		return 1
	if not world.get_dock_position().is_equal_approx(expected_platform):
		print("FAIL _test_dock_platform_spawn_and_sign: get_dock_position()=%s" % world.get_dock_position())
		result = 1
	var spawn: Transform3D = world.get_spawn_transform()
	if not spawn.origin.is_equal_approx(expected_platform + Vector3(0.0, 24.0, 0.0)) or not spawn.basis.is_equal_approx(Basis()):
		print("FAIL _test_dock_platform_spawn_and_sign: spawn %s expected 24 m above the platform, facing -Z" % spawn)
		result = 1
	var undock_sign := world.get_node_or_null("Dock/Sign") as Label3D
	if undock_sign == null or undock_sign.text != "UNDOCK  [F]":
		print("FAIL _test_dock_platform_spawn_and_sign: no sign reading 'UNDOCK  [F]'")
		world.free()
		return 1
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
		print("FAIL _test_dock_platform_spawn_and_sign: sign does not start idle")
		result = 1
	world.set_undock_ready(true)
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_READY_COLOR):
		print("FAIL _test_dock_platform_spawn_and_sign: sign not lit when ready")
		result = 1
	world.set_undock_ready(false)
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
		print("FAIL _test_dock_platform_spawn_and_sign: sign still lit when not ready")
		result = 1
	world.free()
	return result
```

- [ ] **Step 2: Write the failing in-tree test**

Create `tests/test_interior_world_physics.gd`:

```gdscript
extends SceneTree

# Same failure mode as the station "teleport" bug, on the interior terrain's
# trimesh shape: a still hull turning while resting on the floor.

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

var _failures := 0

func _initialize():
	await process_frame
	_failures += await _test_rotating_hull_resting_on_terrain_does_not_jump()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_rotating_hull_resting_on_terrain_does_not_jump() -> int:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	root.add_child(world)
	var hull := CharacterBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 8.0)
	shape_node.shape = box
	hull.add_child(shape_node)
	root.add_child(hull)
	# Floor at the bottom of the ahead section, halfway along it.
	var center_z: float = -(world.bridge_length + world.section_length) * 0.5
	hull.global_position = Vector3(0.0, -(world.section_radius - 1.0 - 0.05), center_z)
	await physics_frame
	var biggest := 0.0
	for tick in range(240):
		var before: Vector3 = hull.global_position
		hull.move_and_collide(Vector3.ZERO)
		hull.rotate_object_local(Vector3.RIGHT, -0.7 / 60.0)
		hull.rotate_object_local(Vector3.UP, -1.4 / 60.0)
		await physics_frame
		biggest = maxf(biggest, hull.global_position.distance_to(before))
	var result := 0
	if biggest > 2.0:
		print("FAIL _test_rotating_hull_resting_on_terrain_does_not_jump: a still, turning hull was shoved %.1f m in one tick" % biggest)
		result = 1
	hull.free()
	world.free()
	return result
```

- [ ] **Step 3: Run to verify they fail** — both: `Parse Error` (preload of `interior_world.gd`).

- [ ] **Step 4: Implement** — create `scripts/interior_world.gd`:

```gdscript
extends Node3D

# The inside of the station around one bridge, built on docking: the bridge
# tube centred on the origin (axis along Z) and the two sections it joins.
# It does not rotate: this is the frame of the people living inside, so the
# ground stays still.

const InteriorLayout = preload("res://scripts/interior_layout.gd")

# Set before build(); defaults are the full-scale station's.
var section_radius := 2000.0
var section_length := 20000.0
var bridge_radius := 600.0
var bridge_length := 1834.0

# Terrain split in chunks: the renderer lights each object with at most 8
# lights (see InteriorLayout.count_lights_reaching_band).
const CHUNKS_AROUND := 16
const CHUNK_LENGTH := 1000.0
const CHUNK_ARC_SEGMENTS := 8
const CHUNK_LENGTH_SEGMENTS := 4
const CAP_SEGMENTS := 128
const TUBE_SEGMENTS := 4
const TUBE_ARC_SEGMENTS := 64

const SUN_SPACING := 1000.0
const SUN_RANGE := 2600.0
const SUN_ENERGY := 3.0
const SUN_COLOR := Color(1.0, 0.93, 0.8)
const SUN_GLOBE_RADIUS := 30.0
const BRIDGE_LIGHT_RANGE := 900.0
const BRIDGE_LIGHT_ENERGY := 2.0

const TERRAIN_COLOR := Color(0.32, 0.42, 0.22)
const STRUCTURE_COLOR := Color(0.45, 0.47, 0.5)

const DOCK_PLATFORM_SIZE := Vector3(60.0, 4.0, 60.0)
const DOCK_LIGHT_RANGE := 150.0
const SPAWN_HEIGHT := 24.0
const SIGN_TEXT := "UNDOCK  [F]"
const SIGN_READY_COLOR := Color(0.3, 1.0, 0.4)
const SIGN_IDLE_COLOR := Color(0.5, 0.5, 0.5)

var _terrain_material: StandardMaterial3D
var _structure_material: StandardMaterial3D
var _sun_mesh: SphereMesh
var _sun_material: StandardMaterial3D

func build() -> void:
	_terrain_material = _make_material(TERRAIN_COLOR, 0.95)
	_structure_material = _make_material(STRUCTURE_COLOR, 0.6)
	_sun_mesh = SphereMesh.new()
	_sun_mesh.radius = SUN_GLOBE_RADIUS
	_sun_mesh.height = SUN_GLOBE_RADIUS * 2.0
	_sun_material = StandardMaterial3D.new()
	_sun_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sun_material.albedo_color = SUN_COLOR

	# Every chunk is the same piece of wall, turned and shifted: one mesh and
	# one collision shape for all of them.
	var chunk_mesh := _build_band_mesh(section_radius, TAU / CHUNKS_AROUND, CHUNK_LENGTH, CHUNK_ARC_SEGMENTS, CHUNK_LENGTH_SEGMENTS)
	var chunk_shape := chunk_mesh.create_trimesh_shape()
	for side in [-1.0, 1.0]:
		_build_section(side, chunk_mesh, chunk_shape)
	_build_bridge_tube()
	_build_bridge_lights()
	_build_dock()

# Above the dock platform, bow toward the section ahead (-Z), "up" toward the
# tube's axis (the platform sits at the bottom of the tube).
func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis(), _platform_position() + Vector3(0.0, SPAWN_HEIGHT, 0.0))

# The interior world always sits at the origin of the main scene.
func get_dock_position() -> Vector3:
	return transform * _platform_position()

func set_undock_ready(ready: bool) -> void:
	(get_node("Dock/Sign") as Label3D).modulate = SIGN_READY_COLOR if ready else SIGN_IDLE_COLOR

func _platform_position() -> Vector3:
	return Vector3(0.0, -bridge_radius + DOCK_PLATFORM_SIZE.y * 0.5, 0.0)

func _build_section(side: float, chunk_mesh: ArrayMesh, chunk_shape: Shape3D) -> void:
	var section := Node3D.new()
	section.name = "SectionAhead" if side < 0.0 else "SectionBehind"
	add_child(section)
	var center_z: float = InteriorLayout.section_center_z(bridge_length, section_length, side)
	var start_z: float = center_z - section_length * 0.5
	var chunks_along: int = roundi(section_length / CHUNK_LENGTH)
	var angle_step: float = TAU / CHUNKS_AROUND
	for around in range(CHUNKS_AROUND):
		for along in range(chunks_along):
			var chunk := StaticBody3D.new()
			chunk.name = "Chunk_%02d_%02d" % [around, along]
			chunk.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), around * angle_step), Vector3(0.0, 0.0, start_z + along * CHUNK_LENGTH))
			_add_mesh_and_collision(chunk, chunk_mesh, chunk_shape, _terrain_material)
			section.add_child(chunk)
	# Both caps face into the section. The one by the bridge has the tube's
	# hole; the far one is closed (its door to the next bridge opens in piece C).
	section.add_child(_build_cap("NearCap", bridge_radius, center_z - side * section_length * 0.5, side))
	section.add_child(_build_cap("FarCap", 0.0, center_z + side * section_length * 0.5, -side))
	var suns: PackedVector3Array = InteriorLayout.sun_positions(center_z, section_length, SUN_SPACING)
	for k in range(suns.size()):
		section.add_child(_build_sun("Sun_%02d" % k, suns[k]))

func _build_cap(cap_name: String, inner_radius: float, z: float, facing: float) -> StaticBody3D:
	var cap := StaticBody3D.new()
	cap.name = cap_name
	var mesh := _build_annulus_mesh(inner_radius, section_radius, CAP_SEGMENTS)
	# The annulus faces -Z; half a turn around Y makes it face +Z.
	var cap_basis := Basis() if facing < 0.0 else Basis(Vector3.UP, PI)
	cap.transform = Transform3D(cap_basis, Vector3(0.0, 0.0, z))
	_add_mesh_and_collision(cap, mesh, mesh.create_trimesh_shape(), _structure_material)
	return cap

func _build_sun(sun_name: String, sun_position: Vector3) -> Node3D:
	var sun := Node3D.new()
	sun.name = sun_name
	sun.position = sun_position
	var globe := MeshInstance3D.new()
	globe.name = "Globe"
	globe.mesh = _sun_mesh
	globe.material_override = _sun_material
	sun.add_child(globe)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = SUN_COLOR
	light.light_energy = SUN_ENERGY
	light.omni_range = SUN_RANGE
	# No shadows: at kilometre scale shadow maps band and flicker (as the
	# headlights did), and 40 shadowed lights would cost too much.
	light.shadow_enabled = false
	sun.add_child(light)
	return sun

func _build_bridge_tube() -> void:
	var tube := Node3D.new()
	tube.name = "BridgeTube"
	add_child(tube)
	var segment_length: float = bridge_length / TUBE_SEGMENTS
	var mesh := _build_band_mesh(bridge_radius, TAU, segment_length, TUBE_ARC_SEGMENTS, 1)
	var shape := mesh.create_trimesh_shape()
	for k in range(TUBE_SEGMENTS):
		var segment := StaticBody3D.new()
		segment.name = "Segment_%d" % k
		segment.position = Vector3(0.0, 0.0, -bridge_length * 0.5 + k * segment_length)
		_add_mesh_and_collision(segment, mesh, shape, _structure_material)
		tube.add_child(segment)

func _build_bridge_lights() -> void:
	for k in range(3):
		var light := OmniLight3D.new()
		light.name = "BridgeLight_%d" % k
		light.position = Vector3(0.0, 0.0, bridge_length * (k - 1) / 3.0)
		light.light_color = SUN_COLOR
		light.light_energy = BRIDGE_LIGHT_ENERGY
		light.omni_range = BRIDGE_LIGHT_RANGE
		light.shadow_enabled = false
		add_child(light)

func _build_dock() -> void:
	var dock := Node3D.new()
	dock.name = "Dock"
	add_child(dock)

	var platform := StaticBody3D.new()
	platform.name = "Platform"
	platform.position = _platform_position()
	var box := BoxMesh.new()
	box.size = DOCK_PLATFORM_SIZE
	var box_shape := BoxShape3D.new()
	box_shape.size = DOCK_PLATFORM_SIZE
	var platform_material := _make_material(SIGN_READY_COLOR, 0.5)
	platform_material.emission_enabled = true
	platform_material.emission = SIGN_READY_COLOR
	platform_material.emission_energy_multiplier = 1.5
	_add_mesh_and_collision(platform, box, box_shape, platform_material)
	dock.add_child(platform)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = _platform_position() + Vector3(0.0, 30.0, 0.0)
	light.light_color = SIGN_READY_COLOR
	light.light_energy = 2.0
	light.omni_range = DOCK_LIGHT_RANGE
	light.shadow_enabled = false
	dock.add_child(light)

	# The only undock cue: there is no HUD inside.
	var undock_sign := Label3D.new()
	undock_sign.name = "Sign"
	undock_sign.text = SIGN_TEXT
	undock_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	undock_sign.font_size = 96
	undock_sign.pixel_size = 0.1
	undock_sign.position = _platform_position() + Vector3(0.0, 45.0, 0.0)
	undock_sign.modulate = SIGN_IDLE_COLOR
	dock.add_child(undock_sign)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _add_mesh_and_collision(body: Node3D, mesh: Mesh, shape: Shape3D, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)

# Inner wall of a cylinder: angle 0..angle_span, z 0..length, facing the axis.
func _build_band_mesh(radius: float, angle_span: float, length: float, arc_segments: int, length_segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(arc_segments):
		var a0: float = angle_span * i / arc_segments
		var a1: float = angle_span * (i + 1) / arc_segments
		for j in range(length_segments):
			var z0: float = length * j / length_segments
			var z1: float = length * (j + 1) / length_segments
			_add_quad(st,
				InteriorLayout.cylinder_point(radius, a0, z0),
				InteriorLayout.cylinder_point(radius, a1, z0),
				InteriorLayout.cylinder_point(radius, a0, z1),
				InteriorLayout.cylinder_point(radius, a1, z1))
	st.generate_normals()
	return st.commit()

# Flat ring in the z = 0 plane from inner_radius to outer_radius, facing -Z.
# inner_radius 0 gives a full disc.
func _build_annulus_mesh(inner_radius: float, outer_radius: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		var inner0 := InteriorLayout.cylinder_point(inner_radius, a0, 0.0)
		var inner1 := InteriorLayout.cylinder_point(inner_radius, a1, 0.0)
		var outer0 := InteriorLayout.cylinder_point(outer_radius, a0, 0.0)
		var outer1 := InteriorLayout.cylinder_point(outer_radius, a1, 0.0)
		if inner_radius > 0.0:
			_add_quad(st, inner0, outer0, inner1, outer1)
		else:
			_add_triangle(st, inner0, outer0, outer1)
	st.generate_normals()
	return st.commit()

# p00-p10 and p01-p11 are opposite edges. This winding is the one
# SurfaceTool.generate_normals turns into the facing direction documented on
# the two builders above (verified empirically).
func _add_quad(st: SurfaceTool, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3) -> void:
	_add_triangle(st, p00, p10, p01)
	_add_triangle(st, p10, p11, p01)

func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
```

- [ ] **Step 5: Run to verify they pass** — both files `ALL TESTS PASSED`. If a facing check fails, the winding in `_add_quad`/`_add_triangle` is the suspect: swap the order of two vertices in the failing builder and record a `Ruling:`.
- [ ] **Step 6: Full suite.**
- [ ] **Step 7: Commit**

```bash
git add scripts/interior_world.gd tests/test_interior_world.gd tests/test_interior_world_physics.gd
git commit -m "$(cat <<'EOF'
Build the station interior: bridge tube, two sections, suns, dock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Shared flight code for both craft

**Files:**
- Create: `scripts/flying_craft.gd`
- Modify: `scripts/void_cruiser.gd`, `tests/test_void_cruiser.gd`

**Interfaces:**
- Produces: `flying_craft.gd` (`extends CharacterBody3D`) with `const VoidCruiserPhysics`, exports `thrust_power` (150), `linear_damping` (0.5), `torque_power` (2.0), `angular_damping` (0.5), `mouse_sensitivity` (`0.01 / 6.0`), `collision_restitution` (0.4); `var angular_velocity`; `_unhandled_input`, `_read_thrust_input`, `_read_torque_input`, `_apply_physics_step`, `_move`. `void_cruiser.gd` extends it; its behavior is unchanged.

- [ ] **Step 1: Write the failing test**

In `tests/test_void_cruiser.gd` add `const FlyingCraftScript = preload("res://scripts/flying_craft.gd")` after the other preloads, `failures += _test_void_cruiser_flies_with_the_shared_flying_craft()` after `failures += _test_ship_model_is_gone()`, and append:

```gdscript
func _test_void_cruiser_flies_with_the_shared_flying_craft() -> int:
	# The internal-cruiser reuses the same flight model: it lives in one place.
	var cruiser := _make_cruiser()
	var result := 0
	if (cruiser.get_script() as Script).get_base_script() != FlyingCraftScript:
		print("FAIL _test_void_cruiser_flies_with_the_shared_flying_craft: void_cruiser.gd does not extend flying_craft.gd")
		result = 1
	cruiser.free()
	return result
```

- [ ] **Step 2: Run to verify it fails** — `Parse Error: Preload file "res://scripts/flying_craft.gd" does not exist`.

- [ ] **Step 3: Implement**

Create `scripts/flying_craft.gd`:

```gdscript
extends CharacterBody3D

# Flight model shared by the player's craft: 6-DOF thrust and torque with
# damping, mouse-look, and a bounce on collision.

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

@export var thrust_power: float = 150.0
@export_range(0.0, 0.999, 0.001) var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export_range(0.0, 0.999, 0.001) var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01 / 6.0
@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4

var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO
```

Then **move** (cut from `scripts/void_cruiser.gd`, paste at the end of `scripts/flying_craft.gd`, unchanged) these five functions with their comments: `_unhandled_input`, `_read_thrust_input`, `_read_torque_input`, `_apply_physics_step`, `_move`.

In `scripts/void_cruiser.gd`:
- First line `extends CharacterBody3D` → `extends "res://scripts/flying_craft.gd"`.
- Delete the line `const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")` (now inherited).
- Delete the exports `thrust_power`, `linear_damping`, `torque_power`, `angular_damping`, `mouse_sensitivity`, `collision_restitution`. Keep `forward_thrust_ramp_multiplier` and `forward_thrust_ramp_duration`.
- Delete `var angular_velocity: Vector3 = Vector3.ZERO` and `var _mouse_delta: Vector2 = Vector2.ZERO`. Keep `_forward_hold_time`, `_forward_hold_sign`, `_strobe_time`.
- Keep `_physics_process` (it applies the ramp, then calls the inherited `_apply_physics_step`) and `_update_forward_hold_time`.

- [ ] **Step 4: Run** `tests/test_void_cruiser.gd` — `ALL TESTS PASSED` (every existing flight test still green). Also `grep -n "func _move\|func _read_thrust_input\|mouse_sensitivity" scripts/void_cruiser.gd` — Expected: no function definitions left there, no `mouse_sensitivity` export.
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/flying_craft.gd scripts/void_cruiser.gd tests/test_void_cruiser.gd
git commit -m "$(cat <<'EOF'
Move the void-cruiser's flight model into a shared flying_craft base

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Internal-cruiser

**Files:**
- Create: `scripts/internal_cruiser.gd`, `tests/test_internal_cruiser.gd`, `tests/test_internal_cruiser_physics.gd`

**Interfaces:**
- Consumes: `flying_craft.gd` (Task 5); `interior_world.gd` (Task 4) in the physics test.
- Produces: `internal_cruiser.gd` extends `flying_craft.gd`; `const HULL_SIZE := Vector3(4, 2, 8)`; `build_collision_shape()`, `build_camera()` (child `Camera`, current, `KEEP_WIDTH`, fov 90); `_physics_process` without ramp; thrust 70.

- [ ] **Step 1: Write the failing off-tree tests**

Create `tests/test_internal_cruiser.gd`:

```gdscript
extends SceneTree

const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

func _init():
	var failures := 0
	failures += _test_first_person_camera()
	failures += _test_no_hud()
	failures += _test_small_hull()
	failures += _test_top_speed_about_101_without_ramp()
	failures += _test_same_mouse_sensitivity_as_void_cruiser()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cruiser() -> Node3D:
	var cruiser: Node3D = InternalCruiserScript.new()
	cruiser.build_collision_shape()
	cruiser.build_camera()
	return cruiser

func _test_first_person_camera() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	var camera := cruiser.get_node_or_null("Camera") as Camera3D
	if camera == null or not camera.current or camera.keep_aspect != Camera3D.KEEP_WIDTH or not is_equal_approx(camera.fov, 90.0):
		print("FAIL _test_first_person_camera: need a current Camera with KEEP_WIDTH and fov 90")
		result = 1
	cruiser.free()
	return result

func _test_no_hud() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.find_children("*", "CanvasLayer", true, false).size() > 0 or cruiser.get_node_or_null("Cockpit") != null:
		print("FAIL _test_no_hud: the internal-cruiser must have no HUD")
		result = 1
	cruiser.free()
	return result

func _test_small_hull() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	var shape_node := cruiser.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not (shape_node.shape is BoxShape3D) or not (shape_node.shape as BoxShape3D).size.is_equal_approx(Vector3(4.0, 2.0, 8.0)):
		print("FAIL _test_small_hull: expected a 4 x 2 x 8 box")
		result = 1
	cruiser.free()
	return result

func _test_top_speed_about_101_without_ramp() -> int:
	# thrust 70, damping 0.5: v = 70 / ln 2 ~ 101 m/s. With the void-cruiser's
	# 10x ramp it would pass 1000 m/s.
	var cruiser := _make_cruiser()
	Input.action_press("move_forward")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 95.0 or speed > 105.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_top_speed_about_101_without_ramp: velocity %s (speed %.1f), expected about 101 m/s toward -Z" % [cruiser.velocity, speed])
		result = 1
	cruiser.free()
	return result

func _test_same_mouse_sensitivity_as_void_cruiser() -> int:
	var cruiser := _make_cruiser()
	var void_cruiser: Node3D = VoidCruiserScript.new()
	var result := 0
	if not is_equal_approx(cruiser.mouse_sensitivity, void_cruiser.mouse_sensitivity):
		print("FAIL _test_same_mouse_sensitivity_as_void_cruiser: %f vs %f" % [cruiser.mouse_sensitivity, void_cruiser.mouse_sensitivity])
		result = 1
	cruiser.free()
	void_cruiser.free()
	return result
```

- [ ] **Step 2: Write the failing in-tree tests**

Create `tests/test_internal_cruiser_physics.gd`:

```gdscript
extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")

var _failures := 0

func _initialize():
	await process_frame
	_failures += await _test_bounces_off_the_terrain()
	_failures += await _test_cannot_fly_through_the_far_cap()
	_failures += await _test_its_camera_is_the_live_camera()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_world_with_cruiser(start: Vector3, start_velocity: Vector3) -> Array:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	var cruiser: CharacterBody3D = InternalCruiserScript.new()
	cruiser.name = "InternalCruiser"
	cruiser.linear_damping = 0.0
	cruiser.position = start
	cruiser.velocity = start_velocity
	world.add_child(cruiser)
	root.add_child(world)
	return [world, cruiser]

func _test_bounces_off_the_terrain() -> int:
	var center_z: float = -(1834.0 + 20000.0) * 0.5
	var nodes := _make_world_with_cruiser(Vector3(0.0, -(2000.0 - 30.0), center_z), Vector3(0.0, -30.0, 0.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var deepest := 0.0
	for tick in range(180):
		await physics_frame
		deepest = maxf(deepest, Vector2(cruiser.position.x, cruiser.position.y).length())
	var result := 0
	if cruiser.velocity.y <= 0.0 or deepest > 2000.0:
		print("FAIL _test_bounces_off_the_terrain: velocity %s, deepest %.2f m from the axis (floor at 2000)" % [cruiser.velocity, deepest])
		result = 1
	world.free()
	return result

func _test_cannot_fly_through_the_far_cap() -> int:
	var far_cap_z: float = -(1834.0 * 0.5 + 20000.0)
	var nodes := _make_world_with_cruiser(Vector3(0.0, 0.0, far_cap_z + 200.0), Vector3(0.0, 0.0, -100.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var furthest := 0.0
	for tick in range(240):
		await physics_frame
		furthest = minf(furthest, cruiser.position.z)
	var result := 0
	if furthest < far_cap_z or cruiser.velocity.z <= 0.0:
		print("FAIL _test_cannot_fly_through_the_far_cap: reached z %.2f (cap at %.2f), velocity %s" % [furthest, far_cap_z, cruiser.velocity])
		result = 1
	world.free()
	return result

func _test_its_camera_is_the_live_camera() -> int:
	var nodes := _make_world_with_cruiser(Vector3(0.0, -500.0, 0.0), Vector3.ZERO)
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	await process_frame
	var result := 0
	if root.get_camera_3d() != cruiser.get_node("Camera"):
		print("FAIL _test_its_camera_is_the_live_camera: the window renders %s" % root.get_camera_3d())
		result = 1
	world.free()
	return result
```

- [ ] **Step 3: Run to verify they fail** — both: `Parse Error` (preload of `internal_cruiser.gd`).

- [ ] **Step 4: Implement** — create `scripts/internal_cruiser.gd`:

```gdscript
extends "res://scripts/flying_craft.gd"

# The small craft flown inside the station: same controls as the
# void-cruiser, but no thrust ramp, no HUD and no gravity.

const HULL_SIZE := Vector3(4.0, 2.0, 8.0)
const CAMERA_POSITION := Vector3(0.0, 0.3, -2.0)
const CAMERA_HFOV := 90.0
const CAMERA_NEAR := 0.2
const CAMERA_FAR := 60000.0
# With linear_damping 0.5 the top speed is thrust / ln 2: about 101 m/s.
const INTERNAL_THRUST := 70.0

func _init() -> void:
	thrust_power = INTERNAL_THRUST

func _ready() -> void:
	build_collision_shape()
	build_camera()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func build_collision_shape() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = HULL_SIZE
	shape_node.shape = box
	add_child(shape_node)

func build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = CAMERA_POSITION
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAMERA_HFOV
	camera.near = CAMERA_NEAR
	camera.far = CAMERA_FAR
	camera.current = true
	add_child(camera)

func _physics_process(delta: float) -> void:
	_apply_physics_step(delta, _read_thrust_input(), _read_torque_input(delta))
```

- [ ] **Step 5: Run to verify they pass.**
- [ ] **Step 6: Full suite.**
- [ ] **Step 7: Commit**

```bash
git add scripts/internal_cruiser.gd tests/test_internal_cruiser.gd tests/test_internal_cruiser_physics.gd
git commit -m "$(cat <<'EOF'
Add the internal-cruiser: slower, no ramp, no HUD

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: DOCK prompt on the HUD

**Files:**
- Modify: `scripts/cockpit.gd`, `tests/test_cockpit.gd`

**Interfaces:**
- Produces: HUD label `Hud/Panel/Lines/DockLabel` (text `DOCK  [F]`, hidden by default, last in `Lines`); `func set_dock_prompt(available: bool) -> void`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_cockpit.gd`:
- In `_test_hud_lines_in_display_order`, append `"DockLabel"` to the `expected` array.
- Add `failures += _test_dock_prompt_hidden_until_docking_is_possible()` to the list and append:

```gdscript
func _test_dock_prompt_hidden_until_docking_is_possible() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var label := cockpit.get_node_or_null("Hud/Panel/Lines/DockLabel") as Label
	if label == null or label.text != "DOCK  [F]":
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: no DockLabel reading 'DOCK  [F]'")
		cockpit.free()
		return 1
	if label.visible:
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: visible before any check")
		result = 1
	cockpit.set_dock_prompt(true)
	if not label.visible:
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: not shown by set_dock_prompt(true)")
		result = 1
	cockpit.set_dock_prompt(false)
	if label.visible:
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: not hidden by set_dock_prompt(false)")
		result = 1
	cockpit.free()
	return result
```

- [ ] **Step 2: Run to verify they fail** — `FAIL _test_hud_lines_in_display_order` and `FAIL ... no DockLabel`.

- [ ] **Step 3: Implement** in `scripts/cockpit.gd`:

Add after `const HUD_BACKGROUND_COLOR ...`:

```gdscript
const DOCK_PROMPT_TEXT := "DOCK  [F]"
const DOCK_PROMPT_COLOR := Color(0.3, 1.0, 0.4)
```

In `_build_hud()`, right before `update_hud(0.0, {})`:

```gdscript
	var dock_settings := LabelSettings.new()
	dock_settings.font_size = HUD_FONT_SIZE
	dock_settings.font_color = DOCK_PROMPT_COLOR
	_add_hud_label(lines, "DockLabel", dock_settings)
	var dock_label: Label = lines.get_node("DockLabel")
	dock_label.text = DOCK_PROMPT_TEXT
	dock_label.visible = false
```

Add after `update_hud`:

```gdscript
func set_dock_prompt(available: bool) -> void:
	(get_node("Hud/Panel/Lines/DockLabel") as Label).visible = available
```

- [ ] **Step 4: Run to verify they pass.**
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/cockpit.gd tests/test_cockpit.gd
git commit -m "$(cat <<'EOF'
Show DOCK [F] on the HUD when docking is possible

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Game mode — dock, enter, undock

**Files:**
- Create: `scripts/game_mode.gd`, `tests/test_game_mode.gd`
- Modify: `project.godot` (input action), `scenes/torus1_system.tscn`, `tests/test_scene_wiring.gd`

**Interfaces:**
- Consumes: `DockingRules.can_dock` (Task 1); station `nearest_bridge_index`, `get_docking_port`, `get_bridge_radius`, `get_bridge_length`, `section_radius`, `section_length` (Task 2); `InteriorWorld` (Task 4); `InternalCruiser` (Task 6); `Cockpit.set_dock_prompt` (Task 7).
- Produces: node `GameMode` in the main scene; `func is_inside() -> bool`; `var docked_bridge: int`; `func enter_interior(bridge_index: int) -> void`; `func exit_interior() -> void`; child `Fade/Curtain` (`ColorRect`); input action `dock` on F.

- [ ] **Step 1: Write the failing wiring tests**

In `tests/test_scene_wiring.gd` add `failures += _test_dock_action_is_bound_to_f()` to the list, and inside `_test_scene_wiring()`, right before `scene.free()`:

```gdscript
	var game_mode := scene.get_node_or_null("GameMode")
	if game_mode == null or game_mode.get_script() == null or (game_mode.get_script() as Script).resource_path != "res://scripts/game_mode.gd":
		print("FAIL _test_scene_wiring: no GameMode node with game_mode.gd")
		result = 1
	else:
		if game_mode.get_node_or_null(game_mode.station_path) != scene.get_node_or_null("PlanetSystem/TorusStation"):
			print("FAIL _test_scene_wiring: GameMode.station_path does not resolve to TorusStation")
			result = 1
		if game_mode.get_node_or_null(game_mode.void_cruiser_path) != void_cruiser:
			print("FAIL _test_scene_wiring: GameMode.void_cruiser_path does not resolve to VoidCruiser")
			result = 1
```

and append:

```gdscript
func _test_dock_action_is_bound_to_f() -> int:
	if not InputMap.has_action("dock"):
		print("FAIL _test_dock_action_is_bound_to_f: no 'dock' input action")
		return 1
	for event in InputMap.action_get_events("dock"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F:
			return 0
	print("FAIL _test_dock_action_is_bound_to_f: 'dock' is not on the F key")
	return 1
```

- [ ] **Step 2: Write the failing in-tree tests**

Create `tests/test_game_mode.gd`:

```gdscript
extends SceneTree

# Runs on the real scene (2000 sections, world-origin rebase active).

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

var _failures := 0
var _scene: Node3D
var _game_mode: Node
var _station: Node3D
var _void_cruiser: CharacterBody3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_game_mode = _scene.get_node("GameMode")
	_station = _scene.get_node("PlanetSystem/TorusStation")
	_void_cruiser = _scene.get_node("VoidCruiser")
	# The tests put the ship where they want it; no input-driven flight.
	_void_cruiser.set_physics_process(false)

	_failures += await _test_dock_prompt_follows_distance_and_speed()
	_failures += await _test_dock_key_far_from_port_does_nothing()
	_failures += await _test_dock_key_near_port_enters_interior()
	_failures += await _test_undock_sign_and_key_return_outside()
	_failures += await _test_undock_key_far_from_dock_does_nothing()
	_failures += await _test_second_dock_press_during_transition_is_ignored()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _port() -> Node3D:
	return _station.get_docking_port(0)

func _park_near_port(distance: float, speed: float) -> void:
	var outward: Vector3 = _port().global_transform.basis.x.normalized()
	_void_cruiser.global_position = _port().global_position + outward * distance
	_void_cruiser.velocity = outward * speed

func _press_dock() -> void:
	var event := InputEventAction.new()
	event.action = "dock"
	event.pressed = true
	_game_mode._unhandled_input(event)

func _wait_for_transition() -> void:
	await create_timer(1.2).timeout

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _test_dock_prompt_follows_distance_and_speed() -> int:
	var label: Label = _void_cruiser.get_node("Cockpit/Hud/Panel/Lines/DockLabel")
	var result := 0
	_park_near_port(100.0, 0.0)
	await _frames(3)
	if not label.visible:
		print("FAIL _test_dock_prompt_follows_distance_and_speed: hidden at 100 m and 0 m/s")
		result = 1
	_park_near_port(300.0, 0.0)
	await _frames(3)
	if label.visible:
		print("FAIL _test_dock_prompt_follows_distance_and_speed: shown at 300 m")
		result = 1
	_park_near_port(100.0, 30.0)
	await _frames(3)
	if label.visible:
		print("FAIL _test_dock_prompt_follows_distance_and_speed: shown at 30 m/s")
		result = 1
	return result

func _test_dock_key_far_from_port_does_nothing() -> int:
	_park_near_port(300.0, 0.0)
	await _frames(2)
	_press_dock()
	await _wait_for_transition()
	if _game_mode.is_inside():
		print("FAIL _test_dock_key_far_from_port_does_nothing: docked from 300 m")
		_game_mode.exit_interior()
		return 1
	return 0

func _test_dock_key_near_port_enters_interior() -> int:
	_park_near_port(100.0, 0.0)
	await _frames(2)
	_press_dock()
	await _wait_for_transition()
	var result := 0
	if not _game_mode.is_inside() or _game_mode.docked_bridge != 0:
		print("FAIL _test_dock_key_near_port_enters_interior: not inside bridge 0 (inside=%s bridge=%d)" % [_game_mode.is_inside(), _game_mode.docked_bridge])
		return 1
	var interior := _scene.get_node_or_null("InteriorWorld")
	if interior == null:
		print("FAIL _test_dock_key_near_port_enters_interior: no InteriorWorld")
		return 1
	if _void_cruiser.is_inside_tree() or _station.is_inside_tree():
		print("FAIL _test_dock_key_near_port_enters_interior: the outside world is still in the tree")
		result = 1
	if _scene.get_node_or_null("WorldEnvironment") == null:
		print("FAIL _test_dock_key_near_port_enters_interior: WorldEnvironment was removed")
		result = 1
	if root.get_camera_3d() != interior.get_node("InternalCruiser/Camera"):
		print("FAIL _test_dock_key_near_port_enters_interior: the window renders %s" % root.get_camera_3d())
		result = 1
	if not is_zero_approx((_game_mode.get_node("Fade/Curtain") as ColorRect).color.a):
		print("FAIL _test_dock_key_near_port_enters_interior: the fade did not clear")
		result = 1
	return result

func _test_undock_sign_and_key_return_outside() -> int:
	var interior: Node3D = _scene.get_node("InteriorWorld")
	var undock_sign: Label3D = interior.get_node("Dock/Sign")
	await _frames(3)
	var result := 0
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_READY_COLOR):
		print("FAIL _test_undock_sign_and_key_return_outside: sign not lit at the spawn point")
		result = 1
	_press_dock()
	await _wait_for_transition()
	if _game_mode.is_inside() or not _void_cruiser.is_inside_tree() or _scene.get_node_or_null("InteriorWorld") != null:
		print("FAIL _test_undock_sign_and_key_return_outside: still inside after undocking")
		return 1
	var outward: Vector3 = _port().global_transform.basis.x.normalized()
	var distance: float = _void_cruiser.global_position.distance_to(_port().global_position)
	if absf(distance - 60.0) > 0.5 or not _void_cruiser.velocity.is_zero_approx():
		print("FAIL _test_undock_sign_and_key_return_outside: %.2f m from the port (expected 60), velocity %s" % [distance, _void_cruiser.velocity])
		result = 1
	if (-_void_cruiser.global_transform.basis.z).dot(outward) < 0.99:
		print("FAIL _test_undock_sign_and_key_return_outside: the bow does not point outward")
		result = 1
	if root.get_camera_3d() != _void_cruiser.get_node("Cockpit/PilotCamera"):
		print("FAIL _test_undock_sign_and_key_return_outside: the window renders %s, expected PilotCamera" % root.get_camera_3d())
		result = 1
	return result

func _test_undock_key_far_from_dock_does_nothing() -> int:
	_game_mode.enter_interior(0)
	var interior: Node3D = _scene.get_node("InteriorWorld")
	var cruiser: CharacterBody3D = interior.get_node("InternalCruiser")
	cruiser.set_physics_process(false)
	cruiser.position = Vector3(0.0, 0.0, -5000.0)
	await _frames(3)
	var result := 0
	if not (interior.get_node("Dock/Sign") as Label3D).modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
		print("FAIL _test_undock_key_far_from_dock_does_nothing: sign lit 5 km from the dock")
		result = 1
	_press_dock()
	await _wait_for_transition()
	if not _game_mode.is_inside():
		print("FAIL _test_undock_key_far_from_dock_does_nothing: undocked from 5 km away")
		return 1
	_game_mode.exit_interior()
	return result

func _test_second_dock_press_during_transition_is_ignored() -> int:
	_park_near_port(100.0, 0.0)
	await _frames(2)
	_press_dock()
	await _frames(2)
	_press_dock()
	await _wait_for_transition()
	var result := 0
	var interiors := _scene.find_children("InteriorWorld*", "Node3D", false, false)
	if not _game_mode.is_inside() or interiors.size() != 1:
		print("FAIL _test_second_dock_press_during_transition_is_ignored: inside=%s with %d interiors" % [_game_mode.is_inside(), interiors.size()])
		result = 1
	if _game_mode.is_inside():
		_game_mode.exit_interior()
	return result
```

- [ ] **Step 3: Run to verify they fail**

`tests/test_scene_wiring.gd` — Expected: `FAIL ... no GameMode node` and `FAIL ... no 'dock' input action`.
`tests/test_game_mode.gd` — Expected: `SCRIPT ERROR` (no `GameMode` node / nonexistent function).

- [ ] **Step 4: Implement**

In `project.godot`, right after the `roll_right={...}` block (before the blank line and `[rendering]`), add:

```
dock={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":70,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Create `scripts/game_mode.gd`:

```gdscript
extends Node

# Switches between flying outside the station (void-cruiser) and inside it
# (internal-cruiser in a separate interior world). The outside world is taken
# out of the tree while inside, kept in memory, and put back unchanged.

const DockingRules = preload("res://scripts/docking_rules.gd")
const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")

enum Mode { VOID, INTERIOR }

@export var station_path: NodePath = NodePath("../PlanetSystem/TorusStation")
@export var void_cruiser_path: NodePath = NodePath("../VoidCruiser")

const FADE_TIME := 0.4
# The void-cruiser reappears this far out from the port it docked at.
const UNDOCK_CLEARANCE := 60.0
const KEPT_WHILE_INSIDE := ["WorldEnvironment"]

var mode: Mode = Mode.VOID
var docked_bridge := -1

var _station: Node3D
var _void_cruiser: CharacterBody3D
var _interior: Node3D
var _detached: Array = []
var _transitioning := false
var _curtain: ColorRect

func _ready() -> void:
	_station = get_node(station_path)
	_void_cruiser = get_node(void_cruiser_path)
	_build_fade()

func is_inside() -> bool:
	return mode == Mode.INTERIOR

func _process(_delta: float) -> void:
	if mode == Mode.VOID:
		var cockpit := _void_cruiser.get_node_or_null("Cockpit")
		if cockpit:
			cockpit.set_dock_prompt(_can_dock_now())
	elif _interior:
		_interior.set_undock_ready(_can_undock_now())

func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or not event.is_action_pressed("dock"):
		return
	if mode == Mode.VOID and _can_dock_now():
		_transition(enter_interior.bind(_station.nearest_bridge_index(_void_cruiser.global_position)))
	elif mode == Mode.INTERIOR and _can_undock_now():
		_transition(exit_interior)

func _can_dock_now() -> bool:
	var port: Node3D = _station.get_docking_port(_station.nearest_bridge_index(_void_cruiser.global_position))
	return DockingRules.can_dock(port.global_position.distance_to(_void_cruiser.global_position), _void_cruiser.velocity.length())

func _can_undock_now() -> bool:
	var cruiser: CharacterBody3D = _interior.get_node("InternalCruiser")
	return DockingRules.can_dock(_interior.get_dock_position().distance_to(cruiser.global_position), cruiser.velocity.length())

func enter_interior(bridge_index: int) -> void:
	var parent := get_parent()
	_detached.clear()
	for child in parent.get_children():
		if child == self or String(child.name) in KEPT_WHILE_INSIDE:
			continue
		_detached.append([child, child.get_index()])
	for entry in _detached:
		parent.remove_child(entry[0])

	_interior = InteriorWorldScript.new()
	_interior.name = "InteriorWorld"
	_interior.section_radius = _station.section_radius
	_interior.section_length = _station.section_length
	_interior.bridge_radius = _station.get_bridge_radius()
	_interior.bridge_length = _station.get_bridge_length()
	_interior.build()
	var cruiser: CharacterBody3D = InternalCruiserScript.new()
	cruiser.name = "InternalCruiser"
	cruiser.transform = _interior.get_spawn_transform()
	_interior.add_child(cruiser)
	parent.add_child(_interior)
	docked_bridge = bridge_index
	mode = Mode.INTERIOR

func exit_interior() -> void:
	var parent := get_parent()
	parent.remove_child(_interior)
	_interior.free()
	_interior = null
	# Back in their original order (indices were taken before any removal).
	for entry in _detached:
		parent.add_child(entry[0])
		parent.move_child(entry[0], entry[1])
	_detached.clear()

	var port: Node3D = _station.get_docking_port(docked_bridge)
	var outward: Vector3 = port.global_transform.basis.x.normalized()
	var along: Vector3 = port.global_transform.basis.y.normalized()
	_void_cruiser.global_transform = Transform3D(Basis.looking_at(outward, along), port.global_position + outward * UNDOCK_CLEARANCE)
	_void_cruiser.velocity = Vector3.ZERO
	_void_cruiser.angular_velocity = Vector3.ZERO
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	docked_bridge = -1
	mode = Mode.VOID

func _transition(action: Callable) -> void:
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	await tween.finished
	action.call()
	tween = create_tween()
	tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)
	await tween.finished
	_transitioning = false

func _build_fade() -> void:
	var fade := CanvasLayer.new()
	fade.name = "Fade"
	fade.layer = 100
	add_child(fade)
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.add_child(_curtain)
```

In `scenes/torus1_system.tscn`, add after the `4_rebase` ext_resource line:

```
[ext_resource type="Script" path="res://scripts/game_mode.gd" id="5_game_mode"]
```

and at the end of the file:

```

[node name="GameMode" type="Node" parent="." unique_id=1450392817]
script = ExtResource("5_game_mode")
```

- [ ] **Step 5: Run to verify they pass** — `tests/test_scene_wiring.gd` and `tests/test_game_mode.gd` print `ALL TESTS PASSED`.

- [ ] **Step 6: Full suite.**

- [ ] **Step 7: Live check** — `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR"` prints nothing.

- [ ] **Step 8: Commit**

```bash
git add scripts/game_mode.gd tests/test_game_mode.gd project.godot scenes/torus1_system.tscn tests/test_scene_wiring.gd
git commit -m "$(cat <<'EOF'
Dock with F to enter the station interior, and undock back outside

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Manual verification (user, in game)

1. Near any bridge you see a still ring with a glowing green port; at < 150 m and < 20 m/s the HUD shows `DOCK  [F]`.
2. F: fade, then you are inside the bridge above a green platform, looking toward a section; no HUD.
3. Flying into a section: ground curving up around you, 20 suns along the axis, far wall closed.
4. Back at the platform the sign turns green; F takes you outside next to the ring, facing away.
5. Light levels, sun brightness, flight speed: tune by eye (`SUN_ENERGY`, `INTERNAL_THRUST`).
