# Dock Lamps and Navball Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed-size pad beacon with four corner lamps (8 m real, never under 2 px, hidden behind their bridge) and add a navball showing the ship's attitude in the ring's frame.

**Architecture:** `torus_station.gd` gives every dock four `DockLamp_k` quads sharing one `ShaderMaterial` whose vertex shader (with `skip_vertex_transform`) sizes and places the billboard in camera space, pulls it toward the camera by its own size and blinks it with `TIME`. `attitude.gd` (pure) builds the ring reference frame and the navball matrix. `navball.gd` is a HUD `Control` holding a `SubViewport` (own world) with a static sphere whose shader colours each point by the reference direction it stands for, plus a wing symbol; the cockpit hosts it and the void-cruiser feeds it every frame.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests; offscreen renders through `xvfb-run`.

**Spec:** `docs/superpowers/specs/2026-09-26-dock-lamps-navball-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`). If the script is gone, recreate it: loop over `tests/*.gd`, run each with `timeout 600`, grep for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function`; a missing preload or member prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone. Always use `timeout`.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` once before the first test run, and again after creating a new script/test (for its `.uid`).
- **Worktree shell rule:** in a worktree session, Bash commands with shell variables or `bash -c` constructs are refused. Use literal paths, one command per call; put multi-step edits in a Python file in the scratchpad and run it. After a Python edit that cuts code, check that the comment above the next function and any `static` keyword survived.
- **Shaders (probed under xvfb):** in this double-precision build, writing `MODELVIEW_MATRIX` in `vertex()` has no effect; use `render_mode skip_vertex_transform` and write `VERTEX` in camera space. The lamp shader of Task 1 rendered ~10 px at 500 m and 2 px at 4 km. Shader compile errors only show with a real renderer (xvfb), never headless.
- **Headless:** no rendering; `SubViewport` textures are empty. Tests check nodes, parameters and shader code; renders check the look.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`, `size`; prefix unused parameters with `_`; no bare integer division.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add Godot-generated `.uid` files.
- Live check: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run; renders through `xvfb-run -a`.

## Review Focus

1. **Lamp shader only verifiable with a renderer** — Task 5 renders at 500 m, 3 km and 30 km; the 2 px floor and the bridge occlusion are judged there.
2. **Navball mirrored or turned the wrong way** — the matrix maps screen right to the ship's right; Tests: `_test_level_facing_north`, `_test_yawed_east`, `_test_rolled_upside_down`, `_test_nose_up` (Task 2); Task 5 renders level and rolled 180°.
3. **Reference frame undefined on the ring's axis** (ship above the planet's pole). Test: `_test_reference_on_the_axis_is_still_a_frame` (Task 2).
4. **The navball's SubViewport texture assigned before the viewport is in the tree** (ViewportTexture path errors). Handled in `_ready`; the live check (Task 5) catches errors.
5. **Old beacon leftovers** — the beacon's per-frame material update in `_process` must go. Test: `_test_every_pad_has_four_corner_lamps` asserts no `Beacon` node (Task 1); the diff review checks `_process`.

---

### Task 1: Four corner lamps on every pad

**Files:**
- Modify: `scripts/torus_station.gd` (`_process`, beacon constants/vars/func, `build_station`, `_add_dock`)
- Test: `tests/test_torus_station.gd`

**Interfaces:**
- Produces on `torus_station.gd`: consts `LAMP_COLOR`, `LAMP_SIZE := 8.0`, `LAMP_MIN_PIXELS := 2.0`, `LAMP_RANGE := 50000.0`, `LAMP_LIFT_RATIO := 1.0 / 600.0`, `LAMP_CULL_MARGIN := 500.0`, `LAMP_SHADER`; nodes `Bridge<i>/DockLamp_0..3`. Removes `BEACON_*`, `_beacon_*`, `beacon_lit`, node `Beacon`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_torus_station.gd`, replace the three lines

```gdscript
	failures += _test_every_pad_has_a_fixed_size_beacon()
	failures += _test_beacon_blinks_half_a_second_in_one_and_a_half()
	failures += _test_beacon_is_never_hidden_by_its_bridge()
```

with

```gdscript
	failures += _test_every_pad_has_four_corner_lamps()
	failures += _test_lamp_shader_keeps_a_minimum_size_and_blinks()
```

delete the functions `_test_every_pad_has_a_fixed_size_beacon`, `_test_beacon_blinks_half_a_second_in_one_and_a_half` and `_test_beacon_is_never_hidden_by_its_bridge`, and append:

```gdscript
func _test_every_pad_has_four_corner_lamps() -> int:
	# Small station: bridge radius 9, lamps 9/600 m above the pad, on the
	# texture's green corner spots.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var first: MeshInstance3D = null
	for i in range(4):
		var bridge: Node3D = station.get_node("Bridge%d" % i)
		var pad: MeshInstance3D = bridge.get_node("DockPad")
		if bridge.get_node_or_null("Beacon") != null:
			print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d still has the old beacon" % i)
			result = 1
		var half: float = (pad.mesh as PlaneMesh).size.x * (0.5 - DockPadTexture.LAMP_INSET)
		var normal: Vector3 = pad.transform.basis.y.normalized()
		for k in range(4):
			var lamp := bridge.get_node_or_null("DockLamp_%d" % k) as MeshInstance3D
			if lamp == null:
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d has no DockLamp_%d" % [i, k])
				result = 1
				continue
			if first == null:
				first = lamp
			var offset: Vector3 = lamp.position - pad.position
			var height: float = offset.dot(normal)
			var flat: Vector3 = offset - normal * height
			var across: float = absf(flat.dot(pad.transform.basis.x.normalized()))
			var along: float = absf(flat.dot(pad.transform.basis.z.normalized()))
			if not is_equal_approx(height, 9.0 * TorusStationScript.LAMP_LIFT_RATIO) or not is_equal_approx(across, half) or not is_equal_approx(along, half):
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d at %.3f up, %.3f / %.3f across (expected %.3f, %.3f)" % [i, k, height, across, along, 9.0 * TorusStationScript.LAMP_LIFT_RATIO, half])
				result = 1
			if lamp.mesh != first.mesh or lamp.material_override != first.material_override or not (lamp.material_override is ShaderMaterial):
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d does not share the lamp mesh and shader material" % [i, k])
				result = 1
			if not is_equal_approx(lamp.visibility_range_end, TorusStationScript.LAMP_RANGE) or lamp.extra_cull_margin < TorusStationScript.LAMP_CULL_MARGIN:
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d drawn to %f m, cull margin %f" % [i, k, lamp.visibility_range_end, lamp.extra_cull_margin])
				result = 1
	station.free()
	return result

func _test_lamp_shader_keeps_a_minimum_size_and_blinks() -> int:
	# Headless has no renderer: check the code and parameters (Task 5 renders).
	var station := _make_station(4)
	station.build_station()
	var material := (station.get_node("Bridge0/DockLamp_0") as MeshInstance3D).material_override as ShaderMaterial
	var code: String = material.shader.code
	var result := 0
	for needle in ["skip_vertex_transform", "PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x", "max(lamp_size, min_pixels * pixel * depth)", "pull", "mod(TIME, period)", "discard"]:
		if not code.contains(needle):
			print("FAIL _test_lamp_shader_keeps_a_minimum_size_and_blinks: shader lacks '%s'" % needle)
			result = 1
	if not is_equal_approx(material.get_shader_parameter("lamp_size"), 8.0) or not is_equal_approx(material.get_shader_parameter("min_pixels"), 2.0):
		print("FAIL _test_lamp_shader_keeps_a_minimum_size_and_blinks: lamp_size %s min_pixels %s" % [material.get_shader_parameter("lamp_size"), material.get_shader_parameter("min_pixels")])
		result = 1
	station.free()
	return result
```

(`DockPadTexture` is already preloaded in this test file.)

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -4`
Expected: `Parse Error` naming `LAMP_LIFT_RATIO` / `LAMP_RANGE`.

- [ ] **Step 3: Implement**

In `scripts/torus_station.gd`:
- in `_process`, delete the three beacon lines (`_beacon_time += delta` and the `if _beacon_material != null:` block), leaving:

```gdscript
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_rotate_sections(delta)
```

- replace everything from the comment `# A blinking green beacon above every pad,` down to and including the `beacon_lit` function with:

```gdscript
# Four green lamps on each pad's corners (the texture's green spots), 8 m
# across: they shrink with distance like real objects but never below
# LAMP_MIN_PIXELS, so a dock still shows up to LAMP_RANGE. See LAMP_SHADER.
const LAMP_COLOR := Color(0.3, 1.0, 0.4)
const LAMP_SIZE := 8.0
const LAMP_MIN_PIXELS := 2.0
const LAMP_RANGE := 50000.0
const LAMP_LIFT_RATIO := 1.0 / 600.0
# The quad is 1 m; drawn, it reaches ~160 m across at 50 km.
const LAMP_CULL_MARGIN := 500.0
const LAMP_PERIOD := 1.5
const LAMP_ON_TIME := 0.5
# Billboard sized in camera space (writing MODELVIEW_MATRIX has no effect in
# this double-precision build; skip_vertex_transform does).
const LAMP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

uniform float lamp_size = 8.0;
uniform float min_pixels = 2.0;
uniform vec3 lamp_color : source_color = vec3(0.3, 1.0, 0.4);
uniform float period = 1.5;
uniform float on_time = 0.5;

void vertex() {
	// The lamp's centre in the camera's frame, and how far away it is.
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float depth = max(-centre.z, 0.001);
	// Width of one screen pixel per metre of depth.
	float pixel = 2.0 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);
	float world_size = max(lamp_size, min_pixels * pixel * depth);
	// Pulled toward the camera by its own size, keeping its size on screen:
	// the bridge face it sits on does not cut it, the bridge body still
	// hides it from the far side.
	float pull = clamp((depth - world_size) / depth, 0.1, 1.0);
	VERTEX = centre * pull + VERTEX * world_size * pull;
}

void fragment() {
	if (length(UV - vec2(0.5)) > 0.5 || mod(TIME, period) >= on_time) {
		discard;
	}
	ALBEDO = lamp_color;
}
"""

# One mesh and one material for every lamp.
var _lamp_mesh: QuadMesh
var _lamp_material: ShaderMaterial
```

- in `build_station`, replace the beacon block (from `_beacon_mesh = QuadMesh.new()` down to `_beacon_material.albedo_color = BEACON_COLOR`, including the comment lines inside it) with:

```gdscript
	_lamp_mesh = QuadMesh.new()
	_lamp_mesh.size = Vector2.ONE
	var lamp_shader := Shader.new()
	lamp_shader.code = LAMP_SHADER
	_lamp_material = ShaderMaterial.new()
	_lamp_material.shader = lamp_shader
	_lamp_material.set_shader_parameter("lamp_size", LAMP_SIZE)
	_lamp_material.set_shader_parameter("min_pixels", LAMP_MIN_PIXELS)
	_lamp_material.set_shader_parameter("lamp_color", LAMP_COLOR)
	_lamp_material.set_shader_parameter("period", LAMP_PERIOD)
	_lamp_material.set_shader_parameter("on_time", LAMP_ON_TIME)
```

- in `_add_dock`, replace the beacon block at the end (from `var beacon := MeshInstance3D.new()` to `bridge.add_child(beacon)`) with:

```gdscript
	# Lamps on the pad's corners, just above it.
	var half: float = pad_mesh.size.x * (0.5 - DockPadTexture.LAMP_INSET)
	var along := across.cross(normal)
	var lift: Vector3 = normal * get_bridge_radius() * LAMP_LIFT_RATIO
	var k := 0
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			var lamp := MeshInstance3D.new()
			lamp.name = "DockLamp_%d" % k
			lamp.mesh = _lamp_mesh
			lamp.material_override = _lamp_material
			lamp.position = centre + across * a * half + along * b * half + lift
			lamp.visibility_range_end = LAMP_RANGE
			lamp.extra_cull_margin = LAMP_CULL_MARGIN
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bridge.add_child(lamp)
			k += 1
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only. `grep -n "beacon\|BEACON" scripts/torus_station.gd` prints nothing. Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/torus_station.gd tests/test_torus_station.gd
git commit -m "Replace the pad beacon with four corner lamps: 8 m, never under 2 px

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Attitude math

**Files:**
- Create: `scripts/attitude.gd`, `tests/test_attitude.gd`

**Interfaces:**
- Produces (`static` on `attitude.gd`): `ring_reference(where: Vector3, planet_center: Vector3, axis: Vector3) -> Basis` (columns east, up, −north); `navball_matrix(ship_basis: Basis, reference: Basis) -> Basis`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_attitude.gd`:

```gdscript
extends SceneTree

const Attitude = preload("res://scripts/attitude.gd")

# Planet at the origin, ring axis +Y, ship on +X: east +X, up +Y, north -Z,
# so the reference is the identity.
var _reference: Basis = Attitude.ring_reference(Vector3(100.0, 0.0, 0.0), Vector3.ZERO, Vector3.UP)

func _init():
	var failures := 0
	failures += _test_reference_axes()
	failures += _test_reference_on_the_axis_is_still_a_frame()
	failures += _test_level_facing_north()
	failures += _test_yawed_east()
	failures += _test_rolled_upside_down()
	failures += _test_nose_up()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _orthonormal(frame: Basis) -> bool:
	return is_equal_approx(frame.x.length(), 1.0) and is_equal_approx(frame.y.length(), 1.0) and is_equal_approx(frame.z.length(), 1.0) and absf(frame.x.dot(frame.y)) < 1e-6 and absf(frame.y.dot(frame.z)) < 1e-6 and absf(frame.x.dot(frame.z)) < 1e-6 and frame.determinant() > 0.0

func _test_reference_axes() -> int:
	var result := 0
	if not _reference.is_equal_approx(Basis()):
		print("FAIL _test_reference_axes: on +X with axis +Y got %s, expected identity" % _reference)
		result = 1
	# Elsewhere: east points away from the planet within the ring's plane,
	# north is up x east.
	var where := Vector3(30.0, 500.0, -400.0)
	var frame: Basis = Attitude.ring_reference(where, Vector3(30.0, 0.0, 0.0), Vector3.UP)
	var east := Vector3(0.0, 0.0, -1.0)
	if not _orthonormal(frame) or not frame.x.is_equal_approx(east) or not frame.y.is_equal_approx(Vector3.UP) or not (-frame.z).is_equal_approx(Vector3.UP.cross(east)):
		print("FAIL _test_reference_axes: at %s got %s" % [where, frame])
		result = 1
	return result

func _test_reference_on_the_axis_is_still_a_frame() -> int:
	var frame: Basis = Attitude.ring_reference(Vector3(0.0, 800.0, 0.0), Vector3.ZERO, Vector3.UP)
	if not _orthonormal(frame) or not frame.y.is_equal_approx(Vector3.UP):
		print("FAIL _test_reference_on_the_axis_is_still_a_frame: %s" % frame)
		return 1
	return 0

# Screen points of the ball: +z toward its camera (centre), +x right, +y up.
# Reference directions: +x east, +y up, -z north.
func _check(test_name: String, ship: Basis, screen: Vector3, expected: Vector3) -> int:
	var got: Vector3 = Attitude.navball_matrix(ship, _reference) * screen
	if not got.is_equal_approx(expected):
		print("FAIL %s: screen %s shows %s, expected %s" % [test_name, screen, got, expected])
		return 1
	return 0

func _test_level_facing_north() -> int:
	var result := 0
	result += _check("_test_level_facing_north", Basis(), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	result += _check("_test_level_facing_north", Basis(), Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	result += _check("_test_level_facing_north", Basis(), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0))
	return mini(result, 1)

func _test_yawed_east() -> int:
	# Turned right 90 degrees: the nose (-Z) now points east (+X).
	var ship := Basis(Vector3.UP, -PI / 2.0)
	return _check("_test_yawed_east", ship, Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0))

func _test_rolled_upside_down() -> int:
	# Rolled 180 degrees about the nose: the top of the ball shows down.
	var ship := Basis(Vector3.BACK, PI)
	var result := 0
	result += _check("_test_rolled_upside_down", ship, Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0))
	result += _check("_test_rolled_upside_down", ship, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	return mini(result, 1)

func _test_nose_up() -> int:
	var ship := Basis(Vector3.RIGHT, PI / 2.0)
	return _check("_test_nose_up", ship, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0))
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_attitude.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `Parse Error` (preload of `attitude.gd` fails).

- [ ] **Step 3: Implement**

Create `scripts/attitude.gd`:

```gdscript
extends RefCounted

# The navball's frame and the ship's attitude in it. The reference is the
# ring's plane: up = the ring's axis, east = away from the planet within
# that plane, north = up x east, the way the ring turns there (prograde).

# Columns (east, up, -north).
static func ring_reference(where: Vector3, planet_center: Vector3, axis: Vector3) -> Basis:
	var up := axis.normalized()
	var out := where - planet_center
	var east := out - up * out.dot(up)
	if east.length() < 1e-6:
		# On the axis east is undefined: any direction square to it will do.
		east = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.BACK)
	east = east.normalized()
	var north := up.cross(east)
	return Basis(east, up, -north)

# Maps a point of the navball as its camera sees it (+z toward the camera,
# +x right, +y up) to the reference direction it shows (+x east, +y up,
# -z north): the centre is where the nose points, right is the ship's right,
# up its dorsal side.
static func navball_matrix(ship_basis: Basis, reference: Basis) -> Basis:
	return reference.inverse() * ship_basis * Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, -1.0))
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only. Run `--import` for the `.uid` files.

- [ ] **Step 5: Commit**

```bash
git add scripts/attitude.gd scripts/attitude.gd.uid tests/test_attitude.gd tests/test_attitude.gd.uid
git commit -m "Add the attitude math: the ring's reference frame and the navball matrix

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The navball on the HUD

**Files:**
- Create: `scripts/navball.gd`, `tests/test_navball.gd`
- Modify: `scripts/cockpit.gd` (preload, `_build_hud`, new `update_attitude`)
- Test: `tests/test_cockpit.gd`

**Interfaces:**
- Produces on `navball.gd` (extends `Control`): consts `PANEL_SIZE := Vector2(200.0, 200.0)`, `BALL_PIXELS := 180`, `BALL_SHADER`; children `Viewport` (SubViewport with `Ball` and `Camera`), `Picture` (TextureRect), `Wings` (Line2D, drawn last); `func set_attitude(matrix: Basis)`, `func attitude() -> Basis`.
- Produces on `cockpit.gd`: node `Hud/Navball`; `func update_attitude(matrix: Basis)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_navball.gd`:

```gdscript
extends SceneTree

const Navball = preload("res://scripts/navball.gd")

func _init():
	var failures := 0
	failures += _test_a_ball_in_its_own_little_world()
	failures += _test_wings_drawn_over_the_ball()
	failures += _test_attitude_reaches_the_shader()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_a_ball_in_its_own_little_world() -> int:
	var navball: Control = Navball.new()
	var result := 0
	var viewport := navball.get_node_or_null("Viewport") as SubViewport
	var ball := navball.get_node_or_null("Viewport/Ball") as MeshInstance3D
	var camera := navball.get_node_or_null("Viewport/Camera") as Camera3D
	if viewport == null or ball == null or camera == null:
		print("FAIL _test_a_ball_in_its_own_little_world: missing Viewport, Ball or Camera")
		navball.free()
		return 1
	if not viewport.own_world_3d or not viewport.transparent_bg or viewport.size != Vector2i(Navball.BALL_PIXELS, Navball.BALL_PIXELS):
		print("FAIL _test_a_ball_in_its_own_little_world: viewport own world %s, transparent %s, size %s" % [viewport.own_world_3d, viewport.transparent_bg, viewport.size])
		result = 1
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not (ball.mesh is SphereMesh) or not (ball.material_override is ShaderMaterial):
		print("FAIL _test_a_ball_in_its_own_little_world: camera not orthogonal, or ball not a shaded sphere")
		result = 1
	var code: String = (ball.material_override as ShaderMaterial).shader.code
	for needle in ["uniform mat3 attitude", "asin", "atan(d.x, -d.z)", "render_mode unshaded"]:
		if not code.contains(needle):
			print("FAIL _test_a_ball_in_its_own_little_world: shader lacks '%s'" % needle)
			result = 1
	if navball.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("FAIL _test_a_ball_in_its_own_little_world: the navball catches the mouse")
		result = 1
	navball.free()
	return result

func _test_wings_drawn_over_the_ball() -> int:
	var navball: Control = Navball.new()
	var result := 0
	var picture := navball.get_node_or_null("Picture") as TextureRect
	var wings := navball.get_node_or_null("Wings") as Line2D
	if picture == null or wings == null or wings.get_index() < picture.get_index() or wings.get_point_count() < 3:
		print("FAIL _test_wings_drawn_over_the_ball: Picture and Wings missing, or Wings drawn under the ball")
		result = 1
	navball.free()
	return result

func _test_attitude_reaches_the_shader() -> int:
	var navball: Control = Navball.new()
	var rolled := Basis(Vector3.BACK, PI)
	navball.set_attitude(rolled)
	var result := 0
	if not navball.attitude().is_equal_approx(rolled):
		print("FAIL _test_attitude_reaches_the_shader: attitude %s, expected %s" % [navball.attitude(), rolled])
		result = 1
	navball.free()
	return result
```

In `tests/test_cockpit.gd`, add after `failures += _test_hud_hosts_the_velocity_cross_bottom_left()`:

```gdscript
	failures += _test_hud_hosts_the_navball_bottom_centre()
```

and append:

```gdscript
func _test_hud_hosts_the_navball_bottom_centre() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var navball := cockpit.get_node_or_null("Hud/Navball") as Control
	if navball == null:
		print("FAIL _test_hud_hosts_the_navball_bottom_centre: no Hud/Navball")
		cockpit.free()
		return 1
	if not is_equal_approx(navball.anchor_left, 0.5) or not is_equal_approx(navball.anchor_top, 1.0) or navball.offset_bottom > 0.0:
		print("FAIL _test_hud_hosts_the_navball_bottom_centre: anchors %f/%f bottom %f" % [navball.anchor_left, navball.anchor_top, navball.offset_bottom])
		result = 1
	var matrix := Basis(Vector3.UP, 0.7)
	cockpit.update_attitude(matrix)
	if not navball.attitude().is_equal_approx(matrix):
		print("FAIL _test_hud_hosts_the_navball_bottom_centre: update_attitude did not reach the navball")
		result = 1
	cockpit.free()
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_navball.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `Parse Error` (preload fails).
Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `FAIL _test_hud_hosts_the_navball_bottom_centre: no Hud/Navball`.

- [ ] **Step 3: Implement**

Create `scripts/navball.gd`:

```gdscript
extends Control

# Attitude indicator: a sphere coloured by direction (sky above the ring's
# plane, ground below, a 30 degree grid, prograde and radial markers) seen
# by a camera in its own little world. The sphere never turns: the shader
# gets the attitude matrix (Attitude.navball_matrix) and paints each point
# with the direction it stands for. A fixed yellow wing symbol marks the
# nose.

const PANEL_SIZE := Vector2(200.0, 200.0)
const BALL_PIXELS := 180
const WING_COLOR := Color(1.0, 0.85, 0.2)
const WING_WIDTH := 3.0
const BALL_SHADER := """
shader_type spatial;
render_mode unshaded;

uniform mat3 attitude = mat3(1.0);

varying vec3 direction;

const vec3 SKY = vec3(0.25, 0.5, 0.85);
const vec3 GROUND = vec3(0.55, 0.35, 0.2);
const vec3 PROGRADE = vec3(1.0, 0.85, 0.2);
const vec3 RETROGRADE = vec3(0.5, 0.42, 0.1);
const vec3 RADIAL_OUT = vec3(0.3, 0.9, 1.0);
const vec3 RADIAL_IN = vec3(0.1, 0.4, 0.5);

void vertex() {
	// The sphere never turns: its normal is the point's place on the ball.
	direction = NORMAL;
}

// 1 within `wide` degrees of `target`, else 0.
float marker(vec3 d, vec3 target, float wide) {
	return step(cos(radians(wide)), dot(d, target));
}

void fragment() {
	// The reference direction this point shows: +x east, +y up, -z north.
	vec3 d = normalize(attitude * normalize(direction));
	float pitch = degrees(asin(clamp(d.y, -1.0, 1.0)));
	float heading = degrees(atan(d.x, -d.z));
	vec3 color = pitch >= 0.0 ? SKY : GROUND;
	float off_pitch = abs(pitch - 30.0 * round(pitch / 30.0));
	float off_heading = abs(heading - 30.0 * round(heading / 30.0)) * cos(radians(pitch));
	if (off_pitch < 0.7 || off_heading < 0.7) {
		color *= 0.6;
	}
	if (abs(pitch) < 0.8) {
		color = vec3(1.0);
	}
	color = mix(color, PROGRADE, marker(d, vec3(0.0, 0.0, -1.0), 7.0));
	color = mix(color, RETROGRADE, marker(d, vec3(0.0, 0.0, 1.0), 7.0));
	color = mix(color, RADIAL_OUT, marker(d, vec3(1.0, 0.0, 0.0), 7.0));
	color = mix(color, RADIAL_IN, marker(d, vec3(-1.0, 0.0, 0.0), 7.0));
	ALBEDO = color;
}
"""

var _material: ShaderMaterial
var _viewport: SubViewport
var _picture: TextureRect

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = Vector2i(BALL_PIXELS, BALL_PIXELS)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	ball.mesh = sphere
	var shader := Shader.new()
	shader.code = BALL_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("attitude", Basis())
	ball.material_override = _material
	_viewport.add_child(ball)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.1
	camera.position = Vector3(0.0, 0.0, 3.0)
	camera.current = true
	_viewport.add_child(camera)

	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.position = (PANEL_SIZE - Vector2(BALL_PIXELS, BALL_PIXELS)) * 0.5
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)

	# The nose: fixed wings over the ball's centre.
	var wings := Line2D.new()
	wings.name = "Wings"
	wings.width = WING_WIDTH
	wings.default_color = WING_COLOR
	var centre := PANEL_SIZE * 0.5
	for point in [Vector2(-40.0, 0.0), Vector2(-14.0, 0.0), Vector2(0.0, 10.0), Vector2(14.0, 0.0), Vector2(40.0, 0.0)]:
		wings.add_point(centre + point)
	add_child(wings)

# The viewport's picture only once it is in the tree (a ViewportTexture
# taken off-tree has no path to resolve).
func _ready() -> void:
	_picture.texture = _viewport.get_texture()

func set_attitude(matrix: Basis) -> void:
	_material.set_shader_parameter("attitude", matrix)

func attitude() -> Basis:
	return _material.get_shader_parameter("attitude")
```

In `scripts/cockpit.gd`:
- add below `const VelocityCrossScript = ...`:

```gdscript
const NavballScript = preload("res://scripts/navball.gd")
```

- add after `update_velocity`:

```gdscript
# The ship's attitude in the ring's frame (see Attitude.navball_matrix).
func update_attitude(matrix: Basis) -> void:
	(get_node("Hud/Navball") as Control).set_attitude(matrix)
```

- in `_build_hud`, after `hud.add_child(cross)` add:

```gdscript
	# Bottom centre.
	var navball: Control = NavballScript.new()
	navball.name = "Navball"
	navball.anchor_left = 0.5
	navball.anchor_right = 0.5
	navball.anchor_top = 1.0
	navball.anchor_bottom = 1.0
	navball.offset_left = -NavballScript.PANEL_SIZE.x * 0.5
	navball.offset_right = NavballScript.PANEL_SIZE.x * 0.5
	navball.offset_top = -HUD_MARGIN - NavballScript.PANEL_SIZE.y
	navball.offset_bottom = -HUD_MARGIN
	hud.add_child(navball)
```

- [ ] **Step 4: Run to verify it passes**

Run the two Step 2 commands. Expected: `ALL TESTS PASSED` only, for each. Run `--import` for the `.uid` files. Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/navball.gd scripts/navball.gd.uid scripts/cockpit.gd tests/test_navball.gd tests/test_navball.gd.uid tests/test_cockpit.gd
git commit -m "Add a navball to the HUD: sky, ground, grid and prograde/radial markers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The void-cruiser feeds the navball

**Files:**
- Modify: `scripts/void_cruiser.gd`
- Test: `tests/test_void_cruiser.gd`

**Interfaces:**
- Consumes: Task 2 `Attitude.ring_reference`, `Attitude.navball_matrix`; Task 3 `cockpit.update_attitude`; existing `has_planet`, `planet_center`, `planet_axis`, `_world_position()`, `_world_basis()`.
- Produces on `void_cruiser.gd`: `func attitude_matrix() -> Basis`; the cockpit gets it every frame.

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser.gd`, add after `failures += _test_process_feeds_the_velocity_cross()`:

```gdscript
	failures += _test_process_feeds_the_navball()
```

and append:

```gdscript
func _test_process_feeds_the_navball() -> int:
	# Planet at the origin, axis +Y, ship on +X: the reference is the
	# identity. Rolled upside down, the top of the ball shows down.
	var cruiser := _make_cruiser()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_axis = Vector3.UP
	cruiser.position = Vector3(1000.0, 0.0, 0.0)
	cruiser.transform.basis = Basis(Vector3.BACK, PI)
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser._process(0.016)
	var navball = cruiser.get_node("Cockpit/Hud/Navball")
	var result := 0
	var top: Vector3 = navball.attitude() * Vector3(0.0, 1.0, 0.0)
	if not top.is_equal_approx(Vector3(0.0, -1.0, 0.0)) or not navball.attitude().is_equal_approx(cruiser.attitude_matrix()):
		print("FAIL _test_process_feeds_the_navball: the top of the ball shows %s, expected down" % top)
		result = 1
	var loose := _make_cruiser()
	if not loose.attitude_matrix().is_equal_approx(Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, -1.0))):
		print("FAIL _test_process_feeds_the_navball: without a planet the reference is not the identity")
		result = 1
	loose.free()
	cruiser.free()
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -4`
Expected: `SCRIPT ERROR` naming `attitude_matrix` and/or `FAIL _test_process_feeds_the_navball`.

- [ ] **Step 3: Implement**

In `scripts/void_cruiser.gd`:
- add below `const VelocityCross = ...`:

```gdscript
const Attitude = preload("res://scripts/attitude.gd")
```

- in `_process`, after the `cockpit.update_velocity(...)` line add:

```gdscript
		cockpit.update_attitude(attitude_matrix())
```

- add after `_world_basis`:

```gdscript
# The navball's matrix: the ship's attitude in the ring's frame (identity
# frame without a planet).
func attitude_matrix() -> Basis:
	var reference := Basis()
	if has_planet:
		reference = Attitude.ring_reference(_world_position(), planet_center, planet_axis)
	return Attitude.navball_matrix(_world_basis(), reference)
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only. Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd
git commit -m "Feed the navball the ship's attitude in the ring's frame

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Verification

**Files:**
- Create (scratchpad only): `/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_lamps_navball.gd`

- [ ] **Step 1: Live check**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"`
Expected: no output.

- [ ] **Step 2: Offscreen renders**

Create the scratchpad script:

```gdscript
extends SceneTree

# The pilot's view toward dock 0 from 500 m, 3 km and 30 km (lamps), then
# the same 3 km view rolled 180 degrees (navball upside down). The lamps
# blink: each view waits until they are on (the first 0.5 s of each 1.5 s).
const SCRATCH := "/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/"

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
	for view in [["lamps_500m", 500.0, 0.0], ["lamps_3km", 3000.0, 0.0], ["lamps_30km", 30000.0, 0.0], ["navball_rolled", 3000.0, PI]]:
		var port: Node3D = station.get_docking_port(0)
		var out: Vector3 = port.global_transform.basis.x.normalized()
		var along: Vector3 = port.global_transform.basis.y.normalized()
		var eye: Vector3 = port.global_position + out * view[1] * 0.8 + along * view[1] * 0.6
		var facing := Basis.looking_at(port.global_position - eye, out)
		cruiser.global_transform = Transform3D(facing * Basis(Vector3.BACK, view[2]), eye)
		cruiser.velocity = Vector3.ZERO
		for i in range(4):
			await process_frame
		while fmod(Time.get_ticks_msec() / 1000.0, 1.5) > 0.3:
			await process_frame
		for i in range(2):
			await process_frame
		root.get_texture().get_image().save_png(SCRATCH + "%s.png" % view[0])
		print("saved ", view[0])
	quit()
```

Run: `timeout 300 xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . --script /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_lamps_navball.gd 2>&1 | grep -iE "saved|error" | grep -v XSetIOErrorExitHandler`
Expected: four `saved` lines, no errors (a `SHADER ERROR` here is a code bug to fix, not a visual note).

Note: the shader's `TIME` and `Time.get_ticks_msec()` are not the same clock; if a render catches the lamps off, re-run it once. If the lamps are off in every attempt, ledger it and compare `TIME` against engine time before changing code.

- [ ] **Step 3: Look at the renders**

Open the four PNGs with the Read tool. Expected:
- 500 m: four round green lamps on the pad's corners, about 10–15 px each;
- 3 km: four tiny green dots (2–3 px) on the pad;
- 30 km: the dock marked by a tiny green dot (2 px), not a big square;
- every view: the navball at the bottom centre with sky and ground and the wing symbol; in `navball_rolled`, brown ground at the top of the ball, blue sky below.

Visual-only issues go to the final message as observations.

- [ ] **Step 4: Full suite**

Run the full suite. Expected: every file `ALL TESTS PASSED`.
