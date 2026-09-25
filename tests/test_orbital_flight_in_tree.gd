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

	_failures += _test_ship_finds_the_planet_and_shows_its_altitude()
	_failures += await _test_orbit_line_stays_on_the_planet_after_an_origin_shift()
	_failures += await _test_tab_key_reaches_the_ship()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_ship_finds_the_planet_and_shows_its_altitude() -> int:
	# The ship starts 10 km outside the ring and 4 km above its plane:
	# 6 959 601 m from the centre, 5222 km above the surface.
	var altitude: Label = _cruiser.get_node("Cockpit/Hud/Panel/Lines/AltitudeLabel")
	if not _cruiser.has_planet or altitude.text != "ALTITUDE  5222 km":
		print("FAIL _test_ship_finds_the_planet_and_shows_its_altitude: has_planet %s, '%s'" % [_cruiser.has_planet, altitude.text])
		return 1
	return 0

func _test_orbit_line_stays_on_the_planet_after_an_origin_shift() -> int:
	# Past 5000 m the world shifts back under the ship, planet included.
	var before: Vector3 = _planet.global_position
	_cruiser.global_position += Vector3(0.0, 0.0, -6000.0)
	for i in range(3):
		await physics_frame
		await process_frame
	var line: MeshInstance3D = _cruiser.get_node("OrbitLine")
	var result := 0
	if _planet.global_position.is_equal_approx(before):
		print("FAIL _test_orbit_line_stays_on_the_planet_after_an_origin_shift: no origin shift happened")
		result = 1
	if line.global_position.distance_to(_planet.global_position) > 1.0:
		print("FAIL _test_orbit_line_stays_on_the_planet_after_an_origin_shift: line %.1f m off the planet centre" % line.global_position.distance_to(_planet.global_position))
		result = 1
	return result

func _key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	return event

func _test_tab_key_reaches_the_ship() -> int:
	# Through the viewport, as a real key press: GUI focus must not eat it.
	var was: bool = _cruiser.flight_assist
	root.push_input(_key(true))
	root.push_input(_key(false))
	await process_frame
	if _cruiser.flight_assist == was:
		print("FAIL _test_tab_key_reaches_the_ship: Tab did not toggle flight assist")
		return 1
	root.push_input(_key(true))
	root.push_input(_key(false))
	await process_frame
	return 0
