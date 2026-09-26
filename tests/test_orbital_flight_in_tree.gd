extends SceneTree

# The orbital flight on the real scene (planet, station, origin shift).

var _failures := 0
var _scene: Node3D
var _cruiser: CharacterBody3D
var _planet: Node3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	await process_frame
	_cruiser = _scene.get_node("VoidCruiser")
	_planet = _scene.get_node("PlanetSystem/Planet")

	_failures += _test_ship_finds_the_planet_without_orbit_hud_or_line()
	_failures += await _test_gravity_follows_the_planet_after_an_origin_shift()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_ship_finds_the_planet_without_orbit_hud_or_line() -> int:
	var result := 0
	if not _cruiser.has_planet or not _cruiser.planet_center.is_equal_approx(_planet.global_position):
		print("FAIL _test_ship_finds_the_planet_without_orbit_hud_or_line: has_planet %s, centre %s vs planet %s" % [_cruiser.has_planet, _cruiser.planet_center, _planet.global_position])
		result = 1
	if _cruiser.get_node_or_null("OrbitLine") != null or _cruiser.get_node_or_null("Cockpit/Hud/Panel/Lines/AltitudeLabel") != null:
		print("FAIL _test_ship_finds_the_planet_without_orbit_hud_or_line: the orbit line or the orbit HUD lines are still there")
		result = 1
	return result

func _test_gravity_follows_the_planet_after_an_origin_shift() -> int:
	# Past 5000 m the world shifts back under the ship, planet included.
	var before: Vector3 = _planet.global_position
	_cruiser.global_position += Vector3(0.0, 0.0, -6000.0)
	for i in range(3):
		await physics_frame
		await process_frame
	var result := 0
	if _planet.global_position.is_equal_approx(before):
		print("FAIL _test_gravity_follows_the_planet_after_an_origin_shift: no origin shift happened")
		result = 1
	if _cruiser.planet_center.distance_to(_planet.global_position) > 1.0:
		print("FAIL _test_gravity_follows_the_planet_after_an_origin_shift: ship pulls toward %s, planet at %s" % [_cruiser.planet_center, _planet.global_position])
		result = 1
	return result
