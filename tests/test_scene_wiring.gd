extends SceneTree

func _init():
	var failures := 0
	failures += _test_scene_wiring()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

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
	elif not (planet_system as Node3D).position.is_equal_approx(Vector3(0.0, -4000.0, -6959600.0)):
		print("FAIL _test_scene_wiring: PlanetSystem position=%s" % (planet_system as Node3D).position)
		result = 1

	if void_cruiser == null:
		print("FAIL _test_scene_wiring: VoidCruiser node missing")
		result = 1
	elif not (void_cruiser as Node3D).position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_scene_wiring: VoidCruiser position=%s" % (void_cruiser as Node3D).position)
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
		if torus_station != null and planet != null:
			var resolved_planet: Node = torus_station.get_node_or_null(torus_station.planet_node)
			if resolved_planet != planet:
				print("FAIL _test_scene_wiring: TorusStation.planet_node did not resolve to Planet after reparenting")
				result = 1

	if rebase == null:
		print("FAIL _test_scene_wiring: WorldOriginRebase node missing")
		result = 1
	else:
		var resolved_tracked: Node = rebase.get_node_or_null(rebase.tracked_node)
		var resolved_rebasing: Node = rebase.get_node_or_null(rebase.rebasing_node)
		if resolved_tracked != void_cruiser:
			print("FAIL _test_scene_wiring: WorldOriginRebase.tracked_node did not resolve to VoidCruiser")
			result = 1
		if resolved_rebasing != planet_system:
			print("FAIL _test_scene_wiring: WorldOriginRebase.rebasing_node did not resolve to PlanetSystem")
			result = 1

	scene.free()
	return result
