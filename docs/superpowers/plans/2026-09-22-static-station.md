# Static Planet + Torus1 Station Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Godot 4.6 project containing a static, procedurally generated planet and a Torus1 station ring (cylindrical sections + longitudinal bridges) around it, verified visually.

**Architecture:** Two small `@tool` scripts (`planet.gd`, `torus_station.gd`) generate mesh children from exported parameters, both callable from the editor (tool button) and automatically at runtime (`_ready()`). The ring math (section/bridge positions and orientations) lives in a separate pure-function script (`torus_geometry.gd`) so it can be unit-tested headlessly, independent of mesh generation. The scene itself is assembled through the Godot MCP server (`create_scene`/`add_node`/`save_scene`), then run and screenshotted for a visual check.

**Tech Stack:** Godot 4.6.1 (GDScript), Godot MCP server (`mcp__godot__*` tools) for scene assembly and running the project, headless `godot --headless --script` runs for automated tests.

**Spec:** `docs/superpowers/specs/2026-09-22-static-station-design.md`

## Global Constraints

- Godot version: 4.6.1 (`/home/patrick/Godot_v4.6.1-stable_linux.x86_64`), configured as `GODOT_PATH` in `.mcp.json`.
- 1 Godot unit = 1 meter.
- No rotation, gravity, or flight mechanics in this piece — geometry only.
- Planet radius: 500.0 m. Orbit altitude: 1500.0 m (torus radius = 2000.0 m).
- Section radius: 30.0 m. Section length: 80.0 m. Default section count: 100.
- Bridge length and section/bridge positions are always derived from the above, never hardcoded.

## Review Focus

- `num_sections` of 0 or 1 must not crash `compute_section_transforms` (division by the angular step) — covered in Task 2.
- The ring must close: the last section connects back to the first via a bridge, not just N-1 bridges for N sections — covered in Task 2.
- `section_length` longer than the per-section arc spacing yields a negative bridge length; the function must still return valid transforms rather than crash (visual overlap is an accepted known limitation, not a crash) — covered in Task 2.
- Calling `build_station()` / `build_planet()` twice (e.g., pressing the editor rebuild button repeatedly) must not leak previous children — covered in Tasks 3 and 4.
- Script attachment via the MCP `add_node` `properties: {"script": ...}` field is unverified behavior of this specific MCP server — Task 5 includes a read-back check of the saved `.tscn` and a manual text-edit fallback if the script reference didn't attach.

---

### Task 1: Godot project skeleton

**Files:**
- Create: `project.godot`
- Create: `.gitignore`

**Interfaces:**
- Produces: a Godot project directory recognized by the Godot MCP server at `projectPath = "/home/patrick/projects/playground/torus1"`.

- [ ] **Step 1: Write `project.godot`**

```ini
; Engine configuration file.
config_version=5

[application]

config/name="Torus1"
config/features=PackedStringArray("4.6")
run/main_scene="res://scenes/torus1_system.tscn"

[rendering]

renderer/rendering_method="mobile"
```

(`run/main_scene` points at a scene that Task 5 will create — this is fine, Godot only resolves it when the project actually runs.)

- [ ] **Step 2: Write `.gitignore`**

```
.godot/
*.translation
export.cfg
export_presets.cfg
```

- [ ] **Step 3: Verify the project is recognized**

Call `mcp__godot__get_project_info` with `projectPath: "/home/patrick/projects/playground/torus1"`.
Expected: a successful response describing the project (name "Torus1", Godot version 4.6.x) — not an error about a missing/invalid project.

- [ ] **Step 4: Commit**

```bash
git add project.godot .gitignore
git commit -m "Add Godot project skeleton"
```

---

### Task 2: Torus ring geometry math (pure, headless-tested)

**Files:**
- Create: `scripts/torus_geometry.gd`
- Test: `tests/test_torus_geometry.gd`

**Interfaces:**
- Produces:
  - `TorusGeometry.compute_section_transforms(planet_radius: float, orbit_altitude: float, num_sections: int) -> Array[Transform3D]`
  - `TorusGeometry.compute_bridge_transforms(planet_radius: float, orbit_altitude: float, num_sections: int, section_length: float) -> Array[Transform3D]`
  - `TorusGeometry.compute_bridge_length(planet_radius: float, orbit_altitude: float, num_sections: int, section_length: float) -> float`
  - Loaded elsewhere via `const TorusGeometry = preload("res://scripts/torus_geometry.gd")` (no `class_name`, to avoid depending on the global class cache before the project has ever been opened in the editor).

- [ ] **Step 1: Write the failing test**

Create `tests/test_torus_geometry.gd`:

```gdscript
extends SceneTree

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

func _init():
	var failures := 0
	failures += _test_section_count()
	failures += _test_section_zero_theta()
	failures += _test_ring_closes()
	failures += _test_degenerate_num_sections()
	failures += _test_negative_bridge_length_does_not_crash()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_section_count() -> int:
	var transforms = TorusGeometry.compute_section_transforms(500.0, 1500.0, 4)
	if transforms.size() != 4:
		print("FAIL _test_section_count: expected 4 transforms, got %d" % transforms.size())
		return 1
	return 0

func _test_section_zero_theta() -> int:
	# At theta=0: position=(torus_radius,0,0), tangent=(0,0,1),
	# basis.x=UP=(0,1,0), basis.y=tangent=(0,0,1), basis.z=UP.cross(tangent)=(1,0,0)
	var transforms = TorusGeometry.compute_section_transforms(500.0, 1500.0, 4)
	var t: Transform3D = transforms[0]
	var failed := false
	if not t.origin.is_equal_approx(Vector3(2000.0, 0.0, 0.0)):
		print("FAIL _test_section_zero_theta: origin=%s" % t.origin)
		failed = true
	if not t.basis.x.is_equal_approx(Vector3(0.0, 1.0, 0.0)):
		print("FAIL _test_section_zero_theta: basis.x=%s" % t.basis.x)
		failed = true
	if not t.basis.y.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		print("FAIL _test_section_zero_theta: basis.y=%s" % t.basis.y)
		failed = true
	if not t.basis.z.is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		print("FAIL _test_section_zero_theta: basis.z=%s" % t.basis.z)
		failed = true
	return 1 if failed else 0

func _test_ring_closes() -> int:
	# N sections must produce N bridges (last section connects back to the first).
	var bridges = TorusGeometry.compute_bridge_transforms(500.0, 1500.0, 100, 80.0)
	if bridges.size() != 100:
		print("FAIL _test_ring_closes: expected 100 bridges, got %d" % bridges.size())
		return 1
	return 0

func _test_degenerate_num_sections() -> int:
	var zero = TorusGeometry.compute_section_transforms(500.0, 1500.0, 0)
	var one = TorusGeometry.compute_section_transforms(500.0, 1500.0, 1)
	if zero.size() != 0:
		print("FAIL _test_degenerate_num_sections: num_sections=0 should give 0 transforms, got %d" % zero.size())
		return 1
	if one.size() != 1:
		print("FAIL _test_degenerate_num_sections: num_sections=1 should give 1 transform, got %d" % one.size())
		return 1
	return 0

func _test_negative_bridge_length_does_not_crash() -> int:
	# section_length (500) far exceeds the arc spacing at num_sections=4 -> negative bridge length.
	var length = TorusGeometry.compute_bridge_length(500.0, 1500.0, 4, 500.0)
	if length >= 0.0:
		print("FAIL _test_negative_bridge_length_does_not_crash: expected a negative length, got %f" % length)
		return 1
	var bridges = TorusGeometry.compute_bridge_transforms(500.0, 1500.0, 4, 500.0)
	if bridges.size() != 4:
		print("FAIL _test_negative_bridge_length_does_not_crash: expected 4 bridges even when overlapping, got %d" % bridges.size())
		return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path /home/patrick/projects/playground/torus1 --script res://tests/test_torus_geometry.gd`
Expected: an error, since `res://scripts/torus_geometry.gd` does not exist yet (e.g. "Cannot open file 'res://scripts/torus_geometry.gd'.").

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/torus_geometry.gd`:

```gdscript
extends RefCounted

static func compute_section_transforms(planet_radius: float, orbit_altitude: float, num_sections: int) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if num_sections < 1:
		return transforms
	var torus_radius := planet_radius + orbit_altitude
	var step := TAU / num_sections
	for i in range(num_sections):
		transforms.append(_section_transform_at(torus_radius, i * step))
	return transforms

static func compute_bridge_length(planet_radius: float, orbit_altitude: float, num_sections: int, section_length: float) -> float:
	if num_sections < 1:
		return 0.0
	var torus_radius := planet_radius + orbit_altitude
	var circumference := TAU * torus_radius
	var step_arc_length := circumference / num_sections
	return step_arc_length - section_length

static func compute_bridge_transforms(planet_radius: float, orbit_altitude: float, num_sections: int, section_length: float) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if num_sections < 1:
		return transforms
	var torus_radius := planet_radius + orbit_altitude
	var step := TAU / num_sections
	for i in range(num_sections):
		var theta_mid := i * step + step * 0.5
		transforms.append(_section_transform_at(torus_radius, theta_mid))
	return transforms

static func _section_transform_at(torus_radius: float, theta: float) -> Transform3D:
	var position := Vector3(cos(theta), 0.0, sin(theta)) * torus_radius
	var tangent := Vector3(-sin(theta), 0.0, cos(theta))
	var x_axis := Vector3.UP
	var y_axis := tangent
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	return Transform3D(basis, position)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path /home/patrick/projects/playground/torus1 --script res://tests/test_torus_geometry.gd`
Expected: `ALL TESTS PASSED` printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/torus_geometry.gd tests/test_torus_geometry.gd
git commit -m "Add torus ring geometry math with headless tests"
```

---

### Task 3: Planet build script

**Files:**
- Create: `scripts/planet.gd`
- Test: `tests/test_planet.gd`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `planet.gd` is a script attachable to a `MeshInstance3D`, exporting `planet_radius: float` and a method `build_planet() -> void` that sets `self.mesh` to a `SphereMesh` sized from `planet_radius`. Called automatically from `_ready()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_planet.gd`:

```gdscript
extends SceneTree

const PlanetScript = preload("res://scripts/planet.gd")

func _init():
	var failures := 0
	failures += _test_build_planet_sets_sphere_mesh()
	failures += _test_rebuild_does_not_leak()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_build_planet_sets_sphere_mesh() -> int:
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 500.0
	planet.build_planet()
	if not (planet.mesh is SphereMesh):
		print("FAIL _test_build_planet_sets_sphere_mesh: mesh is not a SphereMesh")
		return 1
	var sphere: SphereMesh = planet.mesh
	if not is_equal_approx(sphere.radius, 500.0):
		print("FAIL _test_build_planet_sets_sphere_mesh: radius=%f" % sphere.radius)
		return 1
	if not is_equal_approx(sphere.height, 1000.0):
		print("FAIL _test_build_planet_sets_sphere_mesh: height=%f" % sphere.height)
		return 1
	return 0

func _test_rebuild_does_not_leak() -> int:
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 500.0
	planet.build_planet()
	planet.planet_radius = 700.0
	planet.build_planet()
	var sphere: SphereMesh = planet.mesh
	if not is_equal_approx(sphere.radius, 700.0):
		print("FAIL _test_rebuild_does_not_leak: radius=%f" % sphere.radius)
		return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path /home/patrick/projects/playground/torus1 --script res://tests/test_planet.gd`
Expected: an error, `res://scripts/planet.gd` does not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/planet.gd`:

```gdscript
@tool
extends MeshInstance3D

@export var planet_radius: float = 500.0

@export_tool_button("Rebuild Planet")
var rebuild_action: Callable = build_planet

func _ready() -> void:
	build_planet()

func build_planet() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius
	sphere.height = planet_radius * 2.0
	mesh = sphere
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path /home/patrick/projects/playground/torus1 --script res://tests/test_planet.gd`
Expected: `ALL TESTS PASSED` printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/planet.gd tests/test_planet.gd
git commit -m "Add planet build script with headless tests"
```

---

### Task 4: Torus station build script

**Files:**
- Create: `scripts/torus_station.gd`
- Test: `tests/test_torus_station.gd`

**Interfaces:**
- Consumes: `TorusGeometry.compute_section_transforms`, `TorusGeometry.compute_bridge_transforms` (Task 2).
- Produces: `torus_station.gd` attachable to a `Node3D`, exporting `planet_radius`, `orbit_altitude`, `num_sections`, `section_radius`, `section_length`, and a method `build_station() -> void` that (re)generates `Section%d` and `Bridge%d` `MeshInstance3D` children. Called automatically from `_ready()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_torus_station.gd`:

```gdscript
extends SceneTree

const TorusStationScript = preload("res://scripts/torus_station.gd")

func _init():
	var failures := 0
	failures += _test_build_station_child_count()
	failures += _test_section_and_bridge_mesh_shape()
	failures += _test_rebuild_does_not_leak()

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
	return station

func _test_build_station_child_count() -> int:
	var station := _make_station(4)
	station.build_station()
	if station.get_child_count() != 8:
		print("FAIL _test_build_station_child_count: expected 8 children, got %d" % station.get_child_count())
		return 1
	return 0

func _test_section_and_bridge_mesh_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: MeshInstance3D = station.get_node("Section0")
	var bridge: MeshInstance3D = station.get_node("Bridge0")
	var failed := false
	if not (section.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Section0.mesh is not CylinderMesh")
		failed = true
	else:
		var cyl: CylinderMesh = section.mesh
		if not is_equal_approx(cyl.top_radius, 30.0) or not is_equal_approx(cyl.height, 80.0):
			print("FAIL _test_section_and_bridge_mesh_shape: Section0 top_radius=%f height=%f" % [cyl.top_radius, cyl.height])
			failed = true
	if not (bridge.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Bridge0.mesh is not CylinderMesh")
		failed = true
	return 1 if failed else 0

func _test_rebuild_does_not_leak() -> int:
	var station := _make_station(4)
	station.build_station()
	station.build_station()
	if station.get_child_count() != 8:
		print("FAIL _test_rebuild_does_not_leak: expected 8 children after rebuild, got %d" % station.get_child_count())
		return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path /home/patrick/projects/playground/torus1 --script res://tests/test_torus_station.gd`
Expected: an error, `res://scripts/torus_station.gd` does not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/torus_station.gd`:

```gdscript
@tool
extends Node3D

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

@export var planet_radius: float = 500.0
@export var orbit_altitude: float = 1500.0
@export var num_sections: int = 100
@export var section_radius: float = 30.0
@export var section_length: float = 80.0

@export_tool_button("Rebuild Station")
var rebuild_action: Callable = build_station

func _ready() -> void:
	build_station()

func build_station() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var section_transforms := TorusGeometry.compute_section_transforms(planet_radius, orbit_altitude, num_sections)
	for i in range(section_transforms.size()):
		var section := MeshInstance3D.new()
		section.name = "Section%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = section_radius
		cyl.bottom_radius = section_radius
		cyl.height = section_length
		section.mesh = cyl
		section.transform = section_transforms[i]
		add_child(section)

	var bridge_length := TorusGeometry.compute_bridge_length(planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(planet_radius, orbit_altitude, num_sections, section_length)
	for i in range(bridge_transforms.size()):
		var bridge := MeshInstance3D.new()
		bridge.name = "Bridge%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = section_radius * 0.3
		cyl.bottom_radius = section_radius * 0.3
		cyl.height = max(bridge_length, 0.01)
		bridge.mesh = cyl
		bridge.transform = bridge_transforms[i]
		add_child(bridge)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable_linux.x86_64 --headless --path /home/patrick/projects/playground/torus1 --script res://tests/test_torus_station.gd`
Expected: `ALL TESTS PASSED` printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/torus_station.gd tests/test_torus_station.gd
git commit -m "Add torus station build script with headless tests"
```

---

### Task 5: Assemble and visually verify the scene

**Files:**
- Create (via MCP, not directly written): `scenes/torus1_system.tscn`

**Interfaces:**
- Consumes: `scripts/planet.gd` (Task 3), `scripts/torus_station.gd` (Task 4).

- [ ] **Step 1: Create the scene**

Call `mcp__godot__create_scene` with `projectPath: "/home/patrick/projects/playground/torus1"`, `scenePath: "scenes/torus1_system.tscn"`, `rootNodeType: "Node3D"`.
Expected: success response confirming the scene file was created.

- [ ] **Step 2: Add the Planet node**

Call `mcp__godot__add_node` with `projectPath`, `scenePath: "scenes/torus1_system.tscn"`, `parentNodePath: "root"`, `nodeType: "MeshInstance3D"`, `nodeName: "Planet"`, `properties: {"script": "res://scripts/planet.gd"}`.

- [ ] **Step 3: Add the TorusStation node**

Call `mcp__godot__add_node` with the same `projectPath`/`scenePath`, `parentNodePath: "root"`, `nodeType: "Node3D"`, `nodeName: "TorusStation"`, `properties: {"script": "res://scripts/torus_station.gd"}`.

- [ ] **Step 4: Add a top-down verification camera**

Call `mcp__godot__add_node` with the same `projectPath`/`scenePath`, `parentNodePath: "root"`, `nodeType: "Camera3D"`, `nodeName: "TopDownCamera"`, `properties: {"position": [0, 6000, 0], "rotation_degrees": [-90, 0, 0], "current": true}`.

At height 6000 with the default 75° vertical FOV, the visible half-extent on the ground is ~6000*tan(37.5°) ≈ 4600 m, comfortably framing the 2000 m torus radius plus margin.

- [ ] **Step 5: Save the scene**

Call `mcp__godot__save_scene` with `projectPath`, `scenePath: "scenes/torus1_system.tscn"`.

- [ ] **Step 6: Verify script and camera attachment**

Read `scenes/torus1_system.tscn`. Expected:
- `[ext_resource ... path="res://scripts/planet.gd" ...]` and `[ext_resource ... path="res://scripts/torus_station.gd" ...]` headers, with the `Planet`/`TorusStation` node blocks each referencing their `ExtResource` via a `script = ExtResource(...)` line.
- A `[node name="TopDownCamera" type="Camera3D" ...]` block with `transform` reflecting position `(0, 6000, 0)` and a -90° X rotation, and `current = true`.

If any of these are missing or wrong (the `properties` field wasn't honored by `add_node` for that value type): edit `scenes/torus1_system.tscn` directly as text to fix it — add the missing `[ext_resource type="Script" ...]` / `script = ExtResource(...)` lines, or fix the camera's `transform`/`current` line — then re-run Step 5 to have Godot re-save/normalize it, or leave the hand edit as-is since `.tscn` is a plain text format Godot re-parses on load.

- [ ] **Step 7: Run the project**

Call `mcp__godot__run_project` with `projectPath`, `scene: "scenes/torus1_system.tscn"`.

- [ ] **Step 8: Check for runtime errors**

Call `mcp__godot__get_debug_output`.
Expected: no script errors (no `build_station`/`build_planet` stack traces, no null-reference errors, no camera warnings now that `TopDownCamera` is present).

- [ ] **Step 9: Capture and inspect a screenshot**

Run: `import -window root /home/patrick/projects/playground/torus1/tests/manual_screenshot.png` (captures the whole screen; the Godot run window should be visible in the foreground since `run_project` just launched it).
Then read `tests/manual_screenshot.png` (image) to visually confirm, from above: the station forms a closed ring around the planet, sections and bridges alternate around the circumference, and the ring is centered on the planet.

If nothing useful is visible (e.g. the window wasn't focused), retry after a short pause, or run `mcp__godot__launch_editor` instead and screenshot the editor's 3D viewport with the scene open.

A close-up look at an individual section (orbiting the editor camera near one `Section`/`Bridge` pair) is worth doing interactively together with the user afterward, in-editor — it's a subjective "does this look right" check better done live than scripted.

- [ ] **Step 10: Stop the project**

Call `mcp__godot__stop_project`.

- [ ] **Step 11: Commit**

```bash
git add scenes/torus1_system.tscn
git rm --cached tests/manual_screenshot.png 2>/dev/null || true
git commit -m "Assemble static planet and torus station scene"
```

(The screenshot is a manual verification artifact, not project source — do not commit it; add `tests/manual_screenshot.png` to `.gitignore` if it was written inside the repo.)

---
