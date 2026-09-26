extends SceneTree

const ApproachGuide = preload("res://scripts/approach_guide.gd")

func _init():
	var failures := 0
	failures += _test_gate_distances_by_range()
	failures += _test_squares_are_30_m_across_the_line()
	failures += _test_squares_stay_square_when_up_is_along_the_line()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_gate_distances_by_range() -> int:
	var result := 0
	# [distance to the dock, gate count, first gate, spacing]
	for c in [[10000.0, 20, 100.0, 500.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [5000.0, 20, 100.0, 250.0]]:
		var gates: PackedFloat64Array = ApproachGuide.gate_distances(c[0])
		var ok: bool = gates.size() == c[1] and is_equal_approx(gates[0], c[2])
		if ok and gates.size() > 1:
			ok = is_equal_approx(gates[1] - gates[0], c[3]) and gates[gates.size() - 1] < c[0]
		if not ok:
			print("FAIL _test_gate_distances_by_range: at %.0f m got %s" % [c[0], gates])
			result = 1
	for far in [10001.0, 80.0, 100.0, 0.0]:
		if ApproachGuide.gate_distances(far).size() != 0:
			print("FAIL _test_gate_distances_by_range: gates at %.0f m, expected none" % far)
			result = 1
	return result

func _check_squares(test_name: String, ship: Vector3, port: Vector3, up_hint: Vector3) -> int:
	var segments: PackedVector3Array = ApproachGuide.gate_segments(ship, port, up_hint)
	var along := (port - ship).normalized()
	var gates := ApproachGuide.gate_distances(ship.distance_to(port))
	if segments.size() != gates.size() * 8 or segments.is_empty():
		print("FAIL %s: %d points for %d gates" % [test_name, segments.size(), gates.size()])
		return 1
	for g in range(gates.size()):
		var centre := Vector3.ZERO
		for k in range(8):
			centre += segments[g * 8 + k]
		centre /= 8.0
		if not centre.is_equal_approx(along * gates[g]):
			print("FAIL %s: gate %d centred at %s, expected %s" % [test_name, g, centre, along * gates[g]])
			return 1
		for k in range(0, 8, 2):
			var a := segments[g * 8 + k]
			var b := segments[g * 8 + k + 1]
			if absf(a.distance_to(b) - ApproachGuide.GATE_SIZE) > 1e-3 or absf((a - centre).dot(along)) > 1e-3:
				print("FAIL %s: gate %d side %s-%s is not 30 m across the line" % [test_name, g, a, b])
				return 1
	return 0

func _test_squares_are_30_m_across_the_line() -> int:
	return _check_squares("_test_squares_are_30_m_across_the_line", Vector3(10.0, -20.0, 30.0), Vector3(3000.0, 400.0, -2500.0), Vector3.UP)

func _test_squares_stay_square_when_up_is_along_the_line() -> int:
	# Flying straight up at the dock: the ship's up is the line itself.
	return _check_squares("_test_squares_stay_square_when_up_is_along_the_line", Vector3.ZERO, Vector3(0.0, 4000.0, 0.0), Vector3.UP)
