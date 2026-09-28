extends SceneTree

const PlanetScript = preload("res://scripts/planet.gd")

func _init():
	var failures := 0
	failures += _test_build_planet_sets_sphere_mesh()
	failures += _test_rebuild_does_not_leak()
	failures += _test_build_planet_sets_surface_material()
	failures += _test_planet_has_clouds_and_atmosphere()
	failures += _test_surface_mesh_is_fine_enough_to_land_on()

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
	# One surface shader: the Earth-like maps with the cloud layer on top
	# (a separate cloud sphere z-fought the surface in the renders).
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 500.0
	planet.build_planet()
	var result := 0
	var mat := planet.material_override as ShaderMaterial
	if mat == null:
		print("FAIL _test_build_planet_sets_surface_material: no ShaderMaterial override")
		planet.free()
		return 1
	var color: Texture2D = mat.get_shader_parameter("surface_color")
	var clouds: Texture2D = mat.get_shader_parameter("clouds")
	if color == null or not color.resource_path.ends_with("planet/color.png") or clouds == null or not clouds.resource_path.ends_with("clouds/clouds.png") or mat.get_shader_parameter("surface_normal") == null or mat.get_shader_parameter("surface_roughness") == null:
		print("FAIL _test_build_planet_sets_surface_material: the surface shader lacks its maps")
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
	var air := planet.get_node_or_null("Atmosphere") as MeshInstance3D
	if air == null or planet.get_node_or_null("Clouds") != null:
		print("FAIL _test_planet_has_clouds_and_atmosphere: expected an Atmosphere shell and no separate Clouds sphere")
		planet.free()
		return 1
	if not is_equal_approx((air.mesh as SphereMesh).radius, 1000.0 + planet.ATMOSPHERE_HEIGHT):
		print("FAIL _test_planet_has_clouds_and_atmosphere: atmosphere radius %f" % (air.mesh as SphereMesh).radius)
		result = 1
	var air_mat := air.material_override as ShaderMaterial
	if air_mat == null or not air_mat.shader.code.contains("blend_add") or air_mat.get_shader_parameter("sun_direction") == null:
		print("FAIL _test_planet_has_clouds_and_atmosphere: atmosphere shader missing")
		result = 1
	# The clouds turn one turn per CLOUD_TURN seconds: their map slides by a
	# quarter of its width in a quarter of that.
	var surface := planet.material_override as ShaderMaterial
	var before: float = surface.get_shader_parameter("cloud_offset")
	planet._turn_clouds(planet.CLOUD_TURN * 0.25)
	var after: float = surface.get_shader_parameter("cloud_offset")
	if not is_equal_approx(fposmod(after - before, 1.0), 0.25):
		print("FAIL _test_planet_has_clouds_and_atmosphere: a quarter of CLOUD_TURN moved the clouds by %f of a turn" % fposmod(after - before, 1.0))
		result = 1
	planet.free()
	return result

func _test_surface_mesh_is_fine_enough_to_land_on() -> int:
	# A crash stops the ship on the true sphere; the drawn faces sag inside it
	# by about R (1 - cos(pi / segments)) round and R (1 - cos(pi / 2 rings))
	# along. With the real radius that must stay within 50 m, not kilometres.
	var planet: MeshInstance3D = PlanetScript.new()
	planet.planet_radius = 1737400.0
	planet.build_planet()
	var sphere := planet.mesh as SphereMesh
	var r: float = planet.planet_radius
	var sag: float = r * (1.0 - cos(PI / sphere.radial_segments)) + r * (1.0 - cos(PI / (2.0 * sphere.rings)))
	var result := 0
	if sag > 50.0:
		print("FAIL _test_surface_mesh_is_fine_enough_to_land_on: faces sag up to %.0f m (%d segments, %d rings)" % [sag, sphere.radial_segments, sphere.rings])
		result = 1
	planet.free()
	return result
