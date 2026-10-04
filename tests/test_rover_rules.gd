extends SceneTree

# Where the rover comes out of the ship and when the pilot can board again.

const RoverRules = preload("res://scripts/rover_rules.gd")

func _init():
	var failures := 0
	failures += _test_spots_beside_the_ship()
	failures += _test_spots_clear_of_the_pad()
	failures += _test_board_near_and_slow()
	failures += _test_board_by_the_pad()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_spots_beside_the_ship() -> int:
	# Ship nose -Z, right +X, tilted a little: the spots lie on the level.
	var ship := Transform3D(Basis(Vector3.FORWARD, 0.1), Vector3(100.0, 5.0, 0.0))
	var spots: Array = RoverRules.spawn_spots(ship, Vector3.UP, false, Vector3.ZERO)
	# Behind and ahead past the hull's ends (15 m from its centre).
	var expected := [Vector3(115.0, 5.0, 0.0), Vector3(85.0, 5.0, 0.0), Vector3(100.0, 5.0, 25.0), Vector3(100.0, 5.0, -25.0)]
	for i in range(4):
		if (spots[i] as Vector3).distance_to(expected[i]) > 1e-3:
			print("FAIL _test_spots_beside_the_ship: %s" % [spots])
			return 1
	return 0

func _test_spots_clear_of_the_pad() -> int:
	# Ship 10 m off the pad's centre toward a corner: every spot past the
	# square's corners (30 * sqrt 2 = 42.4 m from the centre).
	var ship := Transform3D(Basis(), Vector3(7.0, 2.0, 7.0))
	var spots: Array = RoverRules.spawn_spots(ship, Vector3.UP, true, Vector3(0.0, 2.0, 0.0))
	for spot in spots:
		var flat := Vector2(spot.x, spot.z)
		if absf(flat.x) <= 30.0 and absf(flat.y) <= 30.0 or flat.length() < 52.0 - 1e-3:
			print("FAIL _test_spots_clear_of_the_pad: %s" % spot)
			return 1
	return 0

func _test_board_near_and_slow() -> int:
	var ship := Vector3.ZERO
	var near_slow: bool = RoverRules.can_board(Vector3(29.0, 0.0, 0.0), 0.5, ship, false, Vector3.ZERO)
	var far: bool = RoverRules.can_board(Vector3(31.0, 0.0, 0.0), 0.5, ship, false, Vector3.ZERO)
	var fast: bool = RoverRules.can_board(Vector3(10.0, 0.0, 0.0), 1.0, ship, false, Vector3.ZERO)
	if not near_slow or far or fast:
		print("FAIL _test_board_near_and_slow: near and slow %s, far %s, fast %s" % [near_slow, far, fast])
		return 1
	return 0

func _test_board_by_the_pad() -> int:
	var pad := Vector3(0.0, 2.0, 0.0)
	var by_pad: bool = RoverRules.can_board(Vector3(55.0, 0.0, 0.0), 0.0, pad, true, pad)
	var away: bool = RoverRules.can_board(Vector3(65.0, 0.0, 0.0), 0.0, pad, true, pad)
	if not by_pad or away:
		print("FAIL _test_board_by_the_pad: by the pad %s, away %s" % [by_pad, away])
		return 1
	return 0
