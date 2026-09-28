# Sun and Star Dome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A star dome with a discreet Milky Way (baked in Blender) as the space background, the sun drawn on it where the scene's light comes from, and a test proving the planet's atmosphere follows that same light.

**Architecture:** `tools/blender/sky_textures.py` (committed with this plan, tried at 4096x2048) bakes `assets/textures/sky/stars.png`. `scripts/space_sky.gd` on the scene's `WorldEnvironment` turns the background into a Sky with a sky shader: the star map plus a sun disc and glow at `LIGHT0_DIRECTION`. A new in-tree test checks the atmosphere's `sun_direction` against `SunLight`.

**Tech Stack:** Blender 5.2 through MCP; Godot 4.6.1 double-precision (`gl_compatibility`), GDScript, sky shader.

**Spec:** `docs/superpowers/specs/2026-09-28-sun-and-star-dome-design.md`

## Global Constraints

- Godot binary `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`; one test: `timeout 600 <binary> --headless --path . --script tests/<file>.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`; full suite `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (37 files at the end).
- Import after new PNGs (`<binary> --headless --path . --import`); set the star map's `.import` to `compress/mode=2`, `mipmaps/generate=true`, `detect_3d/compress_to=0` explicitly, then import again.
- Blender: `TOOLS = '<worktree>/tools/blender'; exec(open(TOOLS + '/sky_textures.py').read()); print(run('<worktree>/assets/textures'))`.
- Worktree Bash: literal paths; edits via scratchpad Python files. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Written without a dry run of the Godot side (sky shader derivatives and the sign of `LIGHT0_DIRECTION` are checked by render in Task 2); rule on deviations and ledger them.

## Review Focus

1. **Sun position:** the disc must sit where `SunLight`'s +Z points (toward the sun); a sign error puts it behind the viewer.
2. **Seam and poles of the star map:** no line at u = 0/1 (textureGrad), no pinch artefacts at the poles.
3. **Lighting unchanged:** ambient still the fixed colour, sky reflections off; station renders as before.
4. **Interior:** WorldEnvironment is kept inside; the sky must not show through or change interior lighting.
5. **Cost:** sky shader per pixel each frame plus a 32 MB map.

---

### Task 1: The star map and the atmosphere check

**Files:** Create `assets/textures/sky/stars.png` (+ `.import`), `tests/test_sky_in_tree.gd`; modify `tests/test_textures.gd`.

- [ ] **Step 1: Failing tests**

`tests/test_textures.gd`: add `_test_star_map` (register it):

```gdscript
func _test_star_map() -> int:
	# 8192 x 4096, plenty of bright stars, the Milky Way band brighter on
	# average than the sky near its pole.
	var image := _image("res://assets/textures/sky/stars.png")
	if image == null or image.get_size() != Vector2i(8192, 4096):
		print("FAIL _test_star_map: missing or not 8192x4096")
		return 1
	var bright := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).get_luminance() > 0.8:
				bright += 1
	if bright < 250:
		print("FAIL _test_star_map: only %d bright star pixels on a quarter of the map" % bright)
		return 1
	return 0
```

and add `"res://assets/textures/sky/stars.png"` to the path list of `_test_imported_compressed_with_mipmaps`.

Create `tests/test_sky_in_tree.gd`:

```gdscript
extends SceneTree

# The sky and the sun on the real scene.

var _failures := 0

func _initialize():
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	_failures += await _test_atmosphere_follows_the_scene_sun(scene)
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _sun_direction(scene: Node3D) -> Vector3:
	var air: MeshInstance3D = scene.get_node("PlanetSystem/Planet/Atmosphere")
	return (air.material_override as ShaderMaterial).get_shader_parameter("sun_direction")

func _test_atmosphere_follows_the_scene_sun(scene: Node3D) -> int:
	# The planet's rim glows toward the scene's own SunLight (+Z of the
	# light points at the sun), and keeps following it when it turns.
	var sun: DirectionalLight3D = scene.get_node("SunLight")
	var result := 0
	if not _sun_direction(scene).is_equal_approx(sun.global_transform.basis.z.normalized()):
		print("FAIL _test_atmosphere_follows_the_scene_sun: atmosphere %s, SunLight +Z %s" % [_sun_direction(scene), sun.global_transform.basis.z])
		result = 1
	sun.rotate_y(PI * 0.5)
	await process_frame
	await process_frame
	if not _sun_direction(scene).is_equal_approx(sun.global_transform.basis.z.normalized()):
		print("FAIL _test_atmosphere_follows_the_scene_sun: after turning the sun, atmosphere %s, SunLight +Z %s" % [_sun_direction(scene), sun.global_transform.basis.z])
		result = 1
	return result
```

- [ ] **Step 2: Run** — `test_textures.gd` fails (no star map). `test_sky_in_tree.gd`: record the result; if it passes, the wiring already works (ledger it: the check the user asked for, now pinned by a test).

- [ ] **Step 3:** Bake the star map; delete nothing; import; set the `.import` params; import again.

- [ ] **Step 4: Run to pass** both files.

- [ ] **Step 5: Commit** — "Bake the star dome and pin the atmosphere to the scene's sun".

### Task 2: The sky and the sun

**Files:** Create `scripts/space_sky.gd`, `tests/test_space_sky.gd`; modify `scenes/torus1_system.tscn`, `tests/test_scene_wiring.gd`, `tests/test_sky_in_tree.gd`.

- [ ] **Step 1: Failing tests**

`tests/test_space_sky.gd`:

```gdscript
extends SceneTree

const SpaceSky = preload("res://scripts/space_sky.gd")

func _init():
	var failures := 0
	failures += _test_background_is_the_star_dome_with_the_sun()
	failures += _test_lighting_stays_as_it_was()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make() -> WorldEnvironment:
	var world: WorldEnvironment = SpaceSky.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.27, 0.32)
	env.ambient_light_energy = 0.25
	world.environment = env
	world.build_sky()
	return world

func _test_background_is_the_star_dome_with_the_sun() -> int:
	var world := _make()
	var env := world.environment
	var result := 0
	var mat := env.sky.sky_material as ShaderMaterial if env.sky != null else null
	var stars: Texture2D = mat.get_shader_parameter("star_map") if mat != null else null
	if env.background_mode != Environment.BG_SKY or mat == null or not mat.shader.code.contains("LIGHT0_DIRECTION") or stars == null or not stars.resource_path.ends_with("sky/stars.png"):
		print("FAIL _test_background_is_the_star_dome_with_the_sun: background %d, material %s" % [env.background_mode, mat])
		result = 1
	world.free()
	return result

func _test_lighting_stays_as_it_was() -> int:
	# The dome is only a backdrop: ambient light stays the fixed colour and
	# nothing reflects the sky.
	var world := _make()
	var env := world.environment
	var result := 0
	if env.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR or not env.ambient_light_color.is_equal_approx(Color(0.25, 0.27, 0.32)) or env.reflected_light_source != Environment.REFLECTION_SOURCE_DISABLED:
		print("FAIL _test_lighting_stays_as_it_was: ambient source %d colour %s, reflections %d" % [env.ambient_light_source, env.ambient_light_color, env.reflected_light_source])
		result = 1
	world.free()
	return result
```

`tests/test_scene_wiring.gd`: add (and register) `_test_world_environment_builds_the_sky`: instantiate the scene off-tree like the file's other tests do, check `WorldEnvironment`'s script is `res://scripts/space_sky.gd`, free it.

`tests/test_sky_in_tree.gd`: add `_test_sky_is_up_in_the_scene` (register): the scene's `WorldEnvironment.environment.background_mode == Environment.BG_SKY`.

- [ ] **Step 2: Run to fail** (`space_sky.gd` missing; scene not wired).

- [ ] **Step 3: Code**

`scripts/space_sky.gd`:

```gdscript
extends WorldEnvironment

# Space's backdrop: the star dome (tools/blender/sky_textures.py) with the
# sun drawn where the scene's light comes from — at infinity, fixed on the
# dome, out of reach. Only a backdrop: ambient light and reflections are
# left as the scene set them (fixed colour, no sky reflections).

const STARS_PATH := "res://assets/textures/sky/stars.png"
const SKY_SHADER := """
shader_type sky;
uniform sampler2D star_map : source_color, filter_linear_mipmap, repeat_enable;
uniform float star_energy = 1.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
// Angular radius of the disc and width of its glow (radians).
uniform float sun_radius = 0.0087;
uniform float glow_width = 0.05;
uniform float sun_energy = 6.0;
void sky() {
	vec3 d = normalize(EYEDIR);
	// The map's layout (see sky_textures.py): u = atan(x, z) / TAU, v from +Y.
	vec2 uv = vec2(atan(d.x, d.z) / TAU, acos(clamp(d.y, -1.0, 1.0)) / PI);
	// Gradients without the jump where u wraps, so no seam picks a tiny mip.
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	vec3 color = textureGrad(star_map, fract(uv), dx, dy).rgb * star_energy;
	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		float disc = 1.0 - smoothstep(sun_radius * 0.85, sun_radius, angle);
		float glow = exp(-angle / glow_width);
		color = mix(color, sun_color * sun_energy, disc) + sun_color * glow * 0.8;
	}
	COLOR = color;
}
"""

func _ready() -> void:
	build_sky()

func build_sky() -> void:
	var env := environment if environment != null else Environment.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("star_map", load(STARS_PATH))
	var sky := Sky.new()
	sky.sky_material = material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment = env
```

`scenes/torus1_system.tscn`: add `[ext_resource type="Script" path="res://scripts/space_sky.gd" id="6_sky"]` and `script = ExtResource("6_sky")` on the `WorldEnvironment` node.

- [ ] **Step 4: Run to pass** (`test_space_sky.gd`, `test_scene_wiring.gd`, `test_sky_in_tree.gd`).

- [ ] **Step 5: Render check** (xvfb): pilot view toward `SunLight`'s +Z (sun at the centre; if it is behind, `LIGHT0_DIRECTION` has the other sign: negate it in the shader and ledger), a view along the Milky Way, the planet+station view as before; tune `star_energy`/`sun_energy` if too dark/bright (ledger).

- [ ] **Step 6: Suite (37), live check, commit** — "Put the star dome and the sun in the sky".
