# Planet, Bridge and Interior Textures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake new textures in Blender (through the MCP bridge) and use them: an Earth-like planet with a turning cloud layer and an atmosphere rim, rectangular-panel bridges, and textured interior tube and end walls.

**Architecture:** `tools/blender/bake_lib.py`, `panel_textures.py` and `planet_textures.py` (committed with this plan, already tried at low resolution) build procedural node graphs on a UV plane and bake PNGs into `assets/textures/`. Godot code: a bridge material in `torus_station.gd`; UVs and two materials in `interior_world.gd`; `Clouds` and `Atmosphere` child spheres in `planet.gd`. A new `tests/test_textures.gd` checks the baked files.

**Tech Stack:** Blender 5.2 (Cycles bake, driven by `mcp__blender__execute_blender_code`), Godot 4.6.1 double-precision, GDScript.

**Spec:** `docs/superpowers/specs/2026-09-28-textures-planet-bridges-interior-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` (never the `godot` on PATH). One test: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`; a `SCRIPT ERROR` line is a failure.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (35 files at the end: one new).
- After adding PNGs run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` and commit the `.import` files with the PNGs.
- Blender runs through MCP: `TOOLS = '<worktree>/tools/blender'; exec(open(TOOLS + '/<script>.py').read()); run('<worktree>/assets/textures')`. Pass `user_prompt` with the user's words.
- `CylinderMesh` sides use UV v from 0 to 0.5 only (measured): to show N repeats along a cylinder side, `uv1_scale.y = 2 * N`.
- Numbers (spec): bridge panel repeat ~100 m, tube repeat ~60 m, cap 64 repeats round, clouds +10 km turning one turn per 3600 s, atmosphere +40 km, rim power 4.
- Worktree Bash rules: literal paths, no variables/loops/`bash -c`; multi-step edits in a scratchpad Python file.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Code and comments in English, docs in Italian.
- Written without a dry run of the Godot side; rule on any edit that does not apply as written and ledger it.

## Review Focus

1. **Seams:** where the bridge texture wraps round (u 0/1) and where tube pieces meet; the plan relies on whole repeat counts and the 0..0.5 side-UV fact.
2. **Planet map orientation:** the maps assume SphereMesh's u/v formula; check the ice sits at both poles in a render and the storm is over water.
3. **Transparency sorting:** clouds (alpha) and atmosphere (additive) over a planet 1737 km across seen from 5000 km: check the render for z-fighting or the atmosphere drawing over the station.
4. **Texture memory:** 4096x2048 maps x4 plus 2048^2 x 12; judge import settings (VRAM compression) in the render/live run.
5. **Interior light:** the new materials under the interior's suns; the cap's hazard bands must sit at the hole and the rim, not the middle.

---

### Task 1: Panel textures and the bridge material

**Files:**
- Create: `assets/textures/bridge/{color,roughness,normal,emission}.png`, `assets/textures/interior_tube/...`, `assets/textures/interior_cap/...` (+ `.import`)
- Create: `tests/test_textures.gd`
- Modify: `scripts/torus_station.gd`, `tests/test_torus_station.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_textures.gd`:

```gdscript
extends SceneTree

# The baked textures (tools/blender/): sizes, and seamless edges where a set
# repeats.

func _init():
	var failures := 0
	failures += _test_panel_sets_exist_at_2048()
	failures += _test_repeating_panel_sets_have_no_seams()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _image(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null and image.is_compressed():
		image.decompress()
	return image

func _test_panel_sets_exist_at_2048() -> int:
	var result := 0
	for folder in ["bridge", "interior_tube", "interior_cap"]:
		for channel in ["color", "roughness", "normal", "emission"]:
			var path := "res://assets/textures/%s/%s.png" % [folder, channel]
			var image := _image(path)
			if image == null or image.get_size() != Vector2i(2048, 2048):
				print("FAIL _test_panel_sets_exist_at_2048: %s missing or not 2048x2048" % path)
				result = 1
	return result

# Mean colour difference between two pixel columns (or rows).
func _line_difference(image: Image, a: int, b: int, columns: bool) -> float:
	var total := 0.0
	var n := image.get_height() if columns else image.get_width()
	for i in range(0, n, 4):
		var p := image.get_pixel(a, i) if columns else image.get_pixel(i, a)
		var q := image.get_pixel(b, i) if columns else image.get_pixel(i, b)
		total += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
	return total / (n / 4.0)

func _test_repeating_panel_sets_have_no_seams() -> int:
	# Opposite edges should differ no more than two neighbouring lines do
	# anywhere inside (with some slack).
	var result := 0
	for folder in ["bridge", "interior_tube"]:
		var image := _image("res://assets/textures/%s/color.png" % folder)
		if image == null:
			print("FAIL _test_repeating_panel_sets_have_no_seams: no %s colour" % folder)
			result = 1
			continue
		var w := image.get_width()
		var h := image.get_height()
		var across := _line_difference(image, 0, w - 1, true)
		var inside := _line_difference(image, w / 2, w / 2 + 1, true)
		var down := _line_difference(image, 0, h - 1, false)
		var inside_rows := _line_difference(image, h / 2, h / 2 + 1, false)
		if across > inside * 3.0 + 0.05 or down > inside_rows * 3.0 + 0.05:
			print("FAIL _test_repeating_panel_sets_have_no_seams: %s edges differ %.3f / %.3f, inside %.3f / %.3f" % [folder, across, down, inside, inside_rows])
			result = 1
	return result
```

In `tests/test_torus_station.gd` register and add:

```gdscript
func _test_bridges_have_their_own_panels() -> int:
	# Bridges: rectangular panels (bridge/), a whole number of ~100 m repeats
	# round and along the side (the side's UV v spans 0..0.5); sections keep
	# the hexagon hull.
	var station := _make_station(4)
	station.build_station()
	var bridge_mat := (station.get_node("Bridge0/Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var section_mat := (station.get_node("Section0/Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var result := 0
	if bridge_mat == null or bridge_mat == section_mat or bridge_mat.albedo_texture == null or not bridge_mat.albedo_texture.resource_path.ends_with("bridge/color.png") or not bridge_mat.emission_enabled or bridge_mat.emission_texture == null or bridge_mat.normal_texture == null:
		print("FAIL _test_bridges_have_their_own_panels: bridge material %s" % bridge_mat)
		station.free()
		return 1
	var round_repeats: float = bridge_mat.uv1_scale.x
	var along_repeats: float = bridge_mat.uv1_scale.y * 0.5
	if round_repeats != roundf(round_repeats) or along_repeats != roundf(along_repeats) or round_repeats < 1.0 or along_repeats < 1.0:
		print("FAIL _test_bridges_have_their_own_panels: uv scale %s is not whole repeats" % bridge_mat.uv1_scale)
		result = 1
	if not section_mat.albedo_texture.resource_path.ends_with("station/albedo.png"):
		print("FAIL _test_bridges_have_their_own_panels: the sections lost the hexagons")
		result = 1
	station.free()
	return result
```

- [ ] **Step 2: Run them to see them fail**

Expected: `test_textures.gd` fails (files missing); `test_torus_station.gd` fails `_test_bridges_have_their_own_panels` (bridges share the hull material).

- [ ] **Step 3: Bake and wire**

Bake with MCP: `TOOLS = '<worktree>/tools/blender'; exec(open(TOOLS + '/panel_textures.py').read()); print(run('<worktree>/assets/textures'))`. Then import.

In `scripts/torus_station.gd` add after the hull constants:

```gdscript
# Bridges carry their own panels (rectangular; tools/blender/panel_textures.py),
# about BRIDGE_TILE_SIZE metres a repeat.
const BRIDGE_TEXTURE_DIR := "res://assets/textures/bridge/"
const BRIDGE_TILE_SIZE := 100.0
```

and next to `_build_hull_material`:

```gdscript
# A whole number of repeats round and along, so no seam shows where the
# texture wraps. A CylinderMesh side spans UV v 0..0.5 only: twice the scale.
func _build_bridge_material(circumference: float, length: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(BRIDGE_TEXTURE_DIR + "color.png")
	mat.roughness_texture = load(BRIDGE_TEXTURE_DIR + "roughness.png")
	mat.normal_enabled = true
	mat.normal_texture = load(BRIDGE_TEXTURE_DIR + "normal.png")
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mat.emission_texture = load(BRIDGE_TEXTURE_DIR + "emission.png")
	mat.emission_energy_multiplier = HULL_LIGHTS_ENERGY
	var round_repeats := maxf(1.0, roundf(circumference / BRIDGE_TILE_SIZE))
	var along_repeats := maxf(1.0, roundf(length / BRIDGE_TILE_SIZE))
	mat.uv1_scale = Vector3(round_repeats, along_repeats * 2.0, 1.0)
	return mat
```

In `build_station`, build `var bridge_material := _build_bridge_material(TAU * get_bridge_radius(), bridge_length)` after `bridge_length` is known and set `bridge_mesh_instance.material_override = bridge_material`.

- [ ] **Step 4: Run to pass**

`test_textures.gd`, `test_torus_station.gd` → `ALL TESTS PASSED`.

- [ ] **Step 5: Commit** (PNGs, `.import` files, tools unchanged, scripts, tests): "Bake rectangular panel textures and give the bridges their own".

### Task 2: Interior textures

**Files:** Modify `scripts/interior_world.gd`, `tests/test_interior_world.gd`.

- [ ] **Step 1: Write the failing tests** in `tests/test_interior_world.gd` (match its setup of an `InteriorWorld`; register the test):

```gdscript
func _test_tube_and_caps_are_textured() -> int:
	# Tube and end walls carry UVs and the interior panel textures.
	var world := _make_world()
	var result := 0
	var tube := world._tube_mesh as ArrayMesh
	var cap := world._cap_mesh as ArrayMesh
	var tube_uv: PackedVector2Array = tube.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var cap_uv: PackedVector2Array = cap.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if tube_uv.is_empty() or cap_uv.is_empty():
		print("FAIL _test_tube_and_caps_are_textured: missing UVs (tube %d, cap %d)" % [tube_uv.size(), cap_uv.size()])
		world.free()
		return 1
	var cap_min := Vector2(INF, INF)
	var cap_max := -cap_min
	for uv in cap_uv:
		cap_min = cap_min.min(uv)
		cap_max = cap_max.max(uv)
	if not cap_min.is_equal_approx(Vector2.ZERO) or not cap_max.is_equal_approx(Vector2(world.CAP_TEXTURE_REPEATS, 1.0)):
		print("FAIL _test_tube_and_caps_are_textured: cap UVs %s .. %s" % [cap_min, cap_max])
		result = 1
	var tube_max := 0.0
	for uv in tube_uv:
		tube_max = maxf(tube_max, uv.y)
	if tube_max != roundf(tube_max) or tube_max < 1.0:
		print("FAIL _test_tube_and_caps_are_textured: a tube piece spans %f repeats, not a whole number" % tube_max)
		result = 1
	for m in [world._tube_material, world._cap_material]:
		if m == null or m.albedo_texture == null or m.normal_texture == null or not m.emission_enabled:
			print("FAIL _test_tube_and_caps_are_textured: material %s lacks its textures" % m)
			result = 1
	world.free()
	return result
```

(If the test file has no `_make_world()`, use whatever it uses to build an `InteriorWorld` off the tree with real radii; ledger the adaptation.)

- [ ] **Step 2: Run to fail** — `_tube_material` / UVs missing.

- [ ] **Step 3: Code** in `scripts/interior_world.gd`:
- Constants: `const TUBE_TILE_SIZE := 60.0`, `const CAP_TEXTURE_REPEATS := 64`, `const TUBE_TEXTURE_DIR := "res://assets/textures/interior_tube/"`, `const CAP_TEXTURE_DIR := "res://assets/textures/interior_cap/"`.
- `_build_band_mesh(radius, angle_span, length, arc_segments, length_segments, u_repeats := 1.0, v_repeats := 1.0)`: set `st.set_uv(Vector2(u_repeats * a / angle_span, v_repeats * z / length))` for each vertex (add a `_add_quad_uv` beside `_add_quad`, same winding, UV per corner).
- `_build_annulus_mesh(inner, outer, segments, u_repeats := 1.0)`: UV `(u_repeats * a / TAU, (r - inner) / (outer - inner))`.
- `_tube_mesh = _build_band_mesh(bridge_radius, TAU, piece, TUBE_ARC_SEGMENTS, 1, maxf(1.0, roundf(TAU * bridge_radius / TUBE_TILE_SIZE)), maxf(1.0, roundf(piece / TUBE_TILE_SIZE)))` with `piece := bridge_length / TUBE_SEGMENTS`; the chunk collision shape call keeps its defaults.
- `_cap_mesh = _build_annulus_mesh(bridge_radius, section_radius, CAP_SEGMENTS, CAP_TEXTURE_REPEATS)`.
- `var _tube_material: StandardMaterial3D` and `var _cap_material: StandardMaterial3D`, built by `_panel_material(dir)` (albedo, roughness, normal, emission with energy 2.0); tube segments and caps use them instead of `_structure_material`.

- [ ] **Step 4: Run to pass** — `test_interior_world.gd`, `test_interior_streaming.gd`, `test_interior_world_physics.gd`.

- [ ] **Step 5: Commit** — "Texture the interior tube and end walls".

### Task 3: The planet

**Files:** Create `assets/textures/planet/color.png` (+ roughness, normal replaced), `assets/textures/clouds/clouds.png`; delete `assets/textures/planet/albedo.png` (+ `.import`); modify `scripts/planet.gd`, `tests/test_planet.gd`, `tests/test_textures.gd`.

- [ ] **Step 1: Failing tests**

`tests/test_textures.gd` gains `_test_planet_maps` (register it): `res://assets/textures/planet/color.png`, `roughness.png`, `normal.png` are 4096x2048; `res://assets/textures/clouds/clouds.png` is 4096x2048 with an alpha channel (`image.detect_alpha() != Image.ALPHA_NONE`) whose values include both < 0.1 and > 0.9 somewhere on a sampled row near 20 degrees north (row ≈ 0.39 · height).

`tests/test_planet.gd` gains:

```gdscript
func _test_planet_has_clouds_and_atmosphere() -> int:
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 1000.0
	planet.build_planet()
	var result := 0
	var clouds := planet.get_node_or_null("Clouds") as MeshInstance3D
	var air := planet.get_node_or_null("Atmosphere") as MeshInstance3D
	if clouds == null or air == null:
		print("FAIL _test_planet_has_clouds_and_atmosphere: missing layers")
		planet.free()
		return 1
	if not is_equal_approx((clouds.mesh as SphereMesh).radius, 1000.0 + planet.CLOUD_HEIGHT) or not is_equal_approx((air.mesh as SphereMesh).radius, 1000.0 + planet.ATMOSPHERE_HEIGHT):
		print("FAIL _test_planet_has_clouds_and_atmosphere: radii %f, %f" % [(clouds.mesh as SphereMesh).radius, (air.mesh as SphereMesh).radius])
		result = 1
	var cloud_mat := clouds.material_override as StandardMaterial3D
	if cloud_mat == null or cloud_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or cloud_mat.albedo_texture == null:
		print("FAIL _test_planet_has_clouds_and_atmosphere: clouds not a transparent textured layer")
		result = 1
	var air_mat := air.material_override as ShaderMaterial
	if air_mat == null or not air_mat.shader.code.contains("blend_add") or air_mat.get_shader_parameter("sun_direction") == null:
		print("FAIL _test_planet_has_clouds_and_atmosphere: atmosphere shader missing")
		result = 1
	# The clouds turn one turn per CLOUD_TURN seconds.
	var before := clouds.transform.basis
	planet._turn_clouds(planet.CLOUD_TURN * 0.25)
	if not clouds.transform.basis.is_equal_approx(before.rotated(Vector3.UP, PI * 0.5)):
		print("FAIL _test_planet_has_clouds_and_atmosphere: a quarter of CLOUD_TURN did not turn the clouds a quarter turn")
		result = 1
	planet.free()
	return result
```

and `_test_build_planet_sets_surface_material` checks `albedo_texture.resource_path.ends_with("planet/color.png")`.

- [ ] **Step 2: Run to fail.**

- [ ] **Step 3: Bake and code**

Bake: `TOOLS = ...; exec(open(TOOLS + '/planet_textures.py').read()); print(run('<worktree>/assets/textures'))`; delete `assets/textures/planet/albedo.png` and its `.import`; import.

`scripts/planet.gd`:

```gdscript
const SURFACE_ALBEDO_PATH := "res://assets/textures/planet/color.png"
const CLOUDS_PATH := "res://assets/textures/clouds/clouds.png"
# Cloud layer and atmosphere shell above the surface (metres), and the
# clouds' turn (seconds per turn, relative to the surface).
const CLOUD_HEIGHT := 10000.0
const ATMOSPHERE_HEIGHT := 40000.0
const CLOUD_TURN := 3600.0
const ATMOSPHERE_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
// Toward the sun, in world space.
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);
uniform vec4 glow : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform float falloff = 4.0;
varying vec3 world_normal;
void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), falloff);
	float day = clamp(dot(world_normal, normalize(sun_direction)) + 0.25, 0.0, 1.0);
	ALBEDO = glow.rgb * rim * day * 2.0;
}
"""
@export var sun_path: NodePath = NodePath("../../SunLight")
```

`build_planet()` also (re)builds `Clouds` (SphereMesh radius + CLOUD_HEIGHT, StandardMaterial3D with `albedo_texture = load(CLOUDS_PATH)`, `transparency = TRANSPARENCY_ALPHA`, `cull_mode = CULL_BACK`, no shadows) and `Atmosphere` (SphereMesh radius + ATMOSPHERE_HEIGHT, ShaderMaterial with the shader), freeing old ones first so rebuilds do not leak. `_process(delta)`: skip in the editor; `_turn_clouds(delta)`; if the node at `sun_path` exists, set the atmosphere's `sun_direction` to its global `basis.z`. `_turn_clouds(delta)`: `clouds.rotate_y(TAU * delta / CLOUD_TURN)`.

- [ ] **Step 4: Run to pass** — `test_planet.gd`, `test_textures.gd`, `test_scene_wiring.gd`.

- [ ] **Step 5: Commit** — "Bake an Earth-like planet with a turning cloud layer and an atmosphere rim".

### Task 4: Renders, suite, live check

- [ ] Render with xvfb: (a) from the ship's start looking at the planet; (b) a bridge from ~300 m; (c) inside a section looking at an end wall and into the bridge tube (use `GameMode.enter_interior` as `test_game_mode.gd` does, or place the internal cruiser). Read each image; tune the scripts' colours if the planet is too dark/bright or panels unreadable (re-bake, re-run tests), ledgering what changed.
- [ ] Full suite (35 files) and the live check.
- [ ] Commit any tuning.
