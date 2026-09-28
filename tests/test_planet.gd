extends SceneTree

const PlanetScript = preload("res://scripts/planet.gd")

func _init():
	var failures := 0
	failures += _test_build_planet_sets_sphere_mesh()
	failures += _test_rebuild_does_not_leak()
	failures += _test_build_planet_sets_surface_material()
	failures += _test_planet_has_clouds_and_atmosphere()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_build_planet_sets_sphere_mesh() -> int:
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 500.0
	planet.build_planet()
	var result := 0
	if not (planet.mesh is SphereMesh):
		print("FAIL _test_build_planet_sets_sphere_mesh: mesh is not a SphereMesh")
		result = 1
	else:
		var sphere: SphereMesh = planet.mesh
		if not is_equal_approx(sphere.radius, 500.0):
			print("FAIL _test_build_planet_sets_sphere_mesh: radius=%f" % sphere.radius)
			result = 1
		if not is_equal_approx(sphere.height, 1000.0):
			print("FAIL _test_build_planet_sets_sphere_mesh: height=%f" % sphere.height)
			result = 1
	planet.free()
	return result

func _test_build_planet_sets_surface_material() -> int:
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 500.0
	planet.build_planet()
	var result := 0
	if planet.material_override == null or not (planet.material_override is StandardMaterial3D):
		print("FAIL _test_build_planet_sets_surface_material: no StandardMaterial3D override")
		result = 1
	else:
		var mat: StandardMaterial3D = planet.material_override
		if mat.albedo_texture == null or not mat.albedo_texture.resource_path.ends_with("planet/color.png"):
			print("FAIL _test_build_planet_sets_surface_material: albedo_texture is not the Earth-like planet/color.png")
			result = 1
	planet.free()
	return result

func _test_rebuild_does_not_leak() -> int:
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 500.0
	planet.build_planet()
	planet.planet_radius = 700.0
	planet.build_planet()
	var result := 0
	var sphere: SphereMesh = planet.mesh
	if not is_equal_approx(sphere.radius, 700.0):
		print("FAIL _test_rebuild_does_not_leak: radius=%f" % sphere.radius)
		result = 1
	planet.free()
	return result

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
