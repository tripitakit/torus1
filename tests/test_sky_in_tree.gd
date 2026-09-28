extends SceneTree

# The sky and the sun on the real scene.

var _failures := 0

func _initialize():
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	_failures += await _test_atmosphere_follows_the_scene_sun(scene)
	_failures += _test_sky_is_up_in_the_scene(scene)
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

func _test_sky_is_up_in_the_scene(scene: Node3D) -> int:
	var world: WorldEnvironment = scene.get_node("WorldEnvironment")
	if world.environment == null or world.environment.background_mode != Environment.BG_SKY:
		print("FAIL _test_sky_is_up_in_the_scene: the space background is not the sky")
		return 1
	return 0
