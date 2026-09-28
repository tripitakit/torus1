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
