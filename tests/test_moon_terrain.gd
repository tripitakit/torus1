extends SceneTree

# The moon's ground height: NASA's heights, small craters, the flat ground
# under Base Selene.

const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")

func _init():
	var failures := 0
	failures += _test_nasa_heights_follow_the_map()
	failures += _test_flat_round_the_base()
	failures += _test_a_fresh_crater_has_a_bowl_and_a_rim()
	failures += _test_same_answer_every_time()
	failures += _test_no_jumps_between_neighbours()
	failures += _test_detail_fades_the_craters()
	failures += _test_craters_cross_the_cube_edges()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# A direction `metres` from `from` toward `toward` (along the surface).
func _walk(from: Vector3, toward: Vector3, metres: float) -> Vector3:
	var side := (toward - from * toward.dot(from)).normalized()
	var angle := metres / MoonOrbit.RADIUS
	return from * cos(angle) + side * sin(angle)

func _test_nasa_heights_follow_the_map() -> int:
	# Plato's floor below its rim; the South Pole-Aitken basin (53 S,
	# 169 W) deep, the far side's highlands (5 N, 158 W) high (scaled).
	var plato := MoonTerrain.nasa_height(MoonScript.direction_of(51.6, -9.4))
	var rim := MoonTerrain.nasa_height(MoonScript.direction_of(51.6, -9.4 + 1.9 / cos(deg_to_rad(51.6))))
	var mare := MoonTerrain.nasa_height(MoonScript.direction_of(-53.0, -169.0))
	var highland := MoonTerrain.nasa_height(MoonScript.direction_of(5.0, -158.0))
	if rim - plato < 150.0 or mare > -700.0 or highland < 800.0:
		print("FAIL _test_nasa_heights_follow_the_map: Plato %.0f rim %.0f, Aitken %.0f far highlands %.0f" % [plato, rim, mare, highland])
		return 1
	return 0

func _test_flat_round_the_base() -> int:
	var base := MoonScript.base_direction()
	var level := MoonTerrain.base_height()
	var result := 0
	for metres in [0.0, 300.0, 800.0, 1150.0]:
		for toward in [Vector3.UP, Vector3.RIGHT, Vector3.BACK]:
			var h := MoonTerrain.height(_walk(base, toward, metres))
			if absf(h - level) > 0.001:
				print("FAIL _test_flat_round_the_base: %.3f m off at %.0f m" % [h - level, metres])
				result = 1
	if absf(level - MoonTerrain.nasa_height(base)) > 0.001:
		print("FAIL _test_flat_round_the_base: the base's level is not Plato's floor there")
		result = 1
	return result

func _test_a_fresh_crater_has_a_bowl_and_a_rim() -> int:
	var crater := MoonTerrain.find_crater(true, MoonScript.direction_of(-20.0, 40.0))
	if crater.is_empty():
		print("FAIL _test_a_fresh_crater_has_a_bowl_and_a_rim: none found")
		return 1
	var centre: Vector3 = crater.centre
	var radius: float = crater.radius
	var middle := MoonTerrain.crater_height(centre)
	var rim := MoonTerrain.crater_height(_walk(centre, Vector3.UP if absf(centre.y) < 0.9 else Vector3.RIGHT, radius))
	var depth := rim - middle
	var expected := 0.24 * radius * 2.0  # 0.2 D deep, 0.04 D rim
	if depth < expected * 0.7 or depth > expected * 1.3 or radius < 10.0 or radius > 200.0:
		print("FAIL _test_a_fresh_crater_has_a_bowl_and_a_rim: %.0f m crater, rim %.1f m above the middle (expected ~%.1f)" % [radius * 2.0, depth, expected])
		return 1
	return 0

func _test_same_answer_every_time() -> int:
	var d := MoonScript.direction_of(12.3, -45.6)
	if MoonTerrain.height(d) != MoonTerrain.height(d):
		print("FAIL _test_same_answer_every_time")
		return 1
	return 0

func _test_no_jumps_between_neighbours() -> int:
	# 25 cm steps across 3 km: no jump, only slopes (overlapping crater
	# walls reach a slope of ~1.5: 0.4 m a step).
	var start := MoonScript.direction_of(-10.0, 20.0)
	var previous := MoonTerrain.height(start)
	var worst := 0.0
	for step in range(1, 12000):
		var h := MoonTerrain.height(_walk(start, Vector3.RIGHT, step * 0.25))
		worst = maxf(worst, absf(h - previous))
		previous = h
	if worst > 0.5:
		print("FAIL _test_no_jumps_between_neighbours: %.2f m in one 25 cm step" % worst)
		return 1
	return 0

func _test_detail_fades_the_craters() -> int:
	var d := MoonScript.direction_of(-20.0, 40.0)
	if absf(MoonTerrain.height(d, 0.0) - MoonTerrain.nasa_height(d)) > 0.001:
		print("FAIL _test_detail_fades_the_craters: detail 0 still has craters")
		return 1
	return 0

func _test_craters_cross_the_cube_edges() -> int:
	# Along a line across a cube edge (x = z at the equator) the ground
	# stays continuous.
	var start := Vector3(-1.0, 0.0, 0.985).normalized()
	var previous := MoonTerrain.height(start)
	for step in range(1, 12000):
		var h := MoonTerrain.height(_walk(start, Vector3(-1.0, 0.0, 1.03).normalized(), step * 0.25))
		if absf(h - previous) > 0.5:
			print("FAIL _test_craters_cross_the_cube_edges: %.2f m jump at step %d" % [absf(h - previous), step])
			return 1
		previous = h
	return 0
