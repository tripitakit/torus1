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
