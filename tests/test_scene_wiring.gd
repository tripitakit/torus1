extends SceneTree

func _init():
	var failures := 0
	failures += _test_scene_wiring()
	failures += _test_game_starts_fullscreen()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_game_starts_fullscreen() -> int:
	var mode: int = ProjectSettings.get_setting("display/window/size/mode", DisplayServer.WINDOW_MODE_WINDOWED)
	if mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		print("FAIL _test_game_starts_fullscreen: display/window/size/mode=%d expected %d (fullscreen)" % [mode, DisplayServer.WINDOW_MODE_FULLSCREEN])
		return 1
	return 0

func _test_scene_wiring() -> int:
	var packed: PackedScene = load("res://scenes/torus1_system.tscn")
	var scene: Node3D = packed.instantiate()
	var result := 0

	var planet_system := scene.get_node_or_null("PlanetSystem")
	var void_cruiser := scene.get_node_or_null("VoidCruiser")
	var rebase := scene.get_node_or_null("WorldOriginRebase")

	if planet_system == null:
		print("FAIL _test_scene_wiring: PlanetSystem node missing")
		result = 1

	if void_cruiser == null:
		print("FAIL _test_scene_wiring: VoidCruiser node missing")
		result = 1
	elif not (void_cruiser as Node3D).position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_scene_wiring: VoidCruiser position=%s" % (void_cruiser as Node3D).position)
		result = 1

	if void_cruiser != null and void_cruiser.get_node_or_null("ChaseCamera") != null:
		print("FAIL _test_scene_wiring: VoidCruiser still has a ChaseCamera; the view is now the cockpit's PilotCamera, built by void_cruiser.gd")
		result = 1

	if planet_system != null and void_cruiser != null:
		if planet_system.get_parent() != void_cruiser.get_parent():
			print("FAIL _test_scene_wiring: PlanetSystem and VoidCruiser are not siblings, so WorldOriginRebase's sibling auto-discovery would never shift PlanetSystem")
			result = 1

	if planet_system != null:
		var planet := planet_system.get_node_or_null("Planet")
		var torus_station := planet_system.get_node_or_null("TorusStation")
		if planet == null:
			print("FAIL _test_scene_wiring: PlanetSystem/Planet missing")
			result = 1
		if torus_station == null:
			print("FAIL _test_scene_wiring: PlanetSystem/TorusStation missing")
			result = 1
		if planet_system.get_node_or_null("TopDownCamera") == null:
			print("FAIL _test_scene_wiring: PlanetSystem/TopDownCamera missing")
			result = 1
		var top_down := planet_system.get_node_or_null("TopDownCamera") as Camera3D
		if top_down != null and top_down.current:
			print("FAIL _test_scene_wiring: TopDownCamera is current; it would compete with the cockpit's PilotCamera")
			result = 1
		if torus_station != null and planet != null:
			var resolved_planet: Node = torus_station.get_node_or_null(torus_station.planet_node)
			if resolved_planet != planet:
				print("FAIL _test_scene_wiring: TorusStation.planet_node did not resolve to Planet after reparenting")
				result = 1
		if torus_station != null:
			# PlanetSystem's offset must stay consistent with TorusStation's own
			# geometry, not be a second hand-copied literal that can silently
			# drift out of sync with it (they did, once: rescaling the station
			# without updating this offset left a 2km-radius station ~7000km
			# from a 4cm ship, and every existing test still passed).
			var clearance := 10000.0
			var section_clearance := 2.0
			var planet_radius: float = torus_station.planet_radius
			var orbit_altitude: float = torus_station.orbit_altitude
			var section_radius: float = torus_station.section_radius
			var expected_z: float = -(planet_radius + orbit_altitude + clearance)
			var expected_y: float = -(section_clearance * section_radius)
			var actual: Vector3 = (planet_system as Node3D).position
			if not is_equal_approx(actual.z, expected_z) or not is_equal_approx(actual.y, expected_y):
				print("FAIL _test_scene_wiring: PlanetSystem position=%s not consistent with TorusStation geometry (expected y=%f z=%f)" % [actual, expected_y, expected_z])
				result = 1

	if rebase == null:
		print("FAIL _test_scene_wiring: WorldOriginRebase node missing")
		result = 1
	else:
		var resolved_tracked: Node = rebase.get_node_or_null(rebase.tracked_node)
		if resolved_tracked != void_cruiser:
			print("FAIL _test_scene_wiring: WorldOriginRebase.tracked_node did not resolve to VoidCruiser")
			result = 1

	scene.free()
	return result
