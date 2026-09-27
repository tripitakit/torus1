extends SceneTree

const ApproachGuide = preload("res://scripts/approach_guide.gd")

# A bridge like the real one, in its own frame (axis = Y): sections of
# 2000 m radius begin 917 m either side of the pad, which sits 580 m out.
const SECTION_RADIUS := 2000.0
const HALF_GAP := 917.0
const PAD_ANGLE := 0.3
const PAD_RADIUS := 580.0

func _init():
	var failures := 0
	failures += _test_gate_distances_by_length()
	failures += _test_squares_are_30_m_across_the_line()
	failures += _test_squares_stay_square_when_up_is_along_the_line()
	failures += _test_squares_follow_a_bent_path()
	failures += _test_path_runs_from_the_ship_to_the_pad()
	failures += _test_path_ends_straight_along_the_pad_normal()
	failures += _test_path_never_enters_a_section()
	failures += _test_path_is_straight_inside_the_gap()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_gate_distances_by_length() -> int:
	var result := 0
	# [path length, gate count, first gate, spacing]. The 10 km range is the
	# ship's business: a path longer than that still gets its first gates.
	for c in [[10000.0, 20, 100.0, 500.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [5000.0, 20, 100.0, 250.0], [15000.0, 20, 100.0, 500.0]]:
		var gates: PackedFloat64Array = ApproachGuide.gate_distances(c[0])
		var ok: bool = gates.size() == c[1] and is_equal_approx(gates[0], c[2])
		if ok and gates.size() > 1:
			ok = is_equal_approx(gates[1] - gates[0], c[3]) and gates[gates.size() - 1] < c[0]
		if not ok:
			print("FAIL _test_gate_distances_by_length: at %.0f m got %s" % [c[0], gates])
			result = 1
	for short in [80.0, 100.0, 0.0]:
		if ApproachGuide.gate_distances(short).size() != 0:
			print("FAIL _test_gate_distances_by_length: gates at %.0f m, expected none" % short)
			result = 1
	return result

func _check_squares(test_name: String, ship: Vector3, port: Vector3, up_hint: Vector3) -> int:
	var path := PackedVector3Array([ship, port])
	var segments: PackedVector3Array = ApproachGuide.gates_along(path, up_hint)
	var along := (port - ship).normalized()
	var gates := ApproachGuide.gate_distances(ship.distance_to(port))
	if segments.size() != gates.size() * 8 or segments.is_empty():
		print("FAIL %s: %d points for %d gates" % [test_name, segments.size(), gates.size()])
		return 1
	for g in range(gates.size()):
		var centre := _gate_centre(segments, g)
		if not centre.is_equal_approx(ship + along * gates[g]):
			print("FAIL %s: gate %d centred at %s, expected %s" % [test_name, g, centre, ship + along * gates[g]])
			return 1
		if not _is_square_across(segments, g, along):
			print("FAIL %s: gate %d is not a 30 m square across the line" % [test_name, g])
			return 1
	return 0

func _gate_centre(segments: PackedVector3Array, g: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += segments[g * 8 + k]
	return centre / 8.0

func _is_square_across(segments: PackedVector3Array, g: int, along: Vector3) -> bool:
	var centre := _gate_centre(segments, g)
	for k in range(0, 8, 2):
		var a := segments[g * 8 + k]
		var b := segments[g * 8 + k + 1]
		if absf(a.distance_to(b) - ApproachGuide.GATE_SIZE) > 1e-3 or absf((a - centre).dot(along)) > 1e-3:
			return false
	return true

func _test_squares_are_30_m_across_the_line() -> int:
	return _check_squares("_test_squares_are_30_m_across_the_line", Vector3(10.0, -20.0, 30.0), Vector3(3000.0, 400.0, -2500.0), Vector3.UP)

func _test_squares_stay_square_when_up_is_along_the_line() -> int:
	# Flying straight up at the dock: the ship's up is the line itself.
	return _check_squares("_test_squares_stay_square_when_up_is_along_the_line", Vector3.ZERO, Vector3(0.0, 4000.0, 0.0), Vector3.UP)

func _test_squares_follow_a_bent_path() -> int:
	# 1000 m east, then 1000 m north: gates measured along the bend, each
	# facing along its own leg.
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1000.0, 0.0, 0.0), Vector3(1000.0, 0.0, -1000.0)])
	var segments: PackedVector3Array = ApproachGuide.gates_along(path, Vector3.UP)
	var gates := ApproachGuide.gate_distances(2000.0)
	if segments.size() != gates.size() * 8:
		print("FAIL _test_squares_follow_a_bent_path: %d points for %d gates" % [segments.size(), gates.size()])
		return 1
	for g in range(gates.size()):
		var d: float = gates[g]
		var expected := Vector3(d, 0.0, 0.0) if d <= 1000.0 else Vector3(1000.0, 0.0, 1000.0 - d)
		var along := Vector3.RIGHT if d <= 1000.0 else Vector3.FORWARD
		if not _gate_centre(segments, g).is_equal_approx(expected) or not _is_square_across(segments, g, along):
			print("FAIL _test_squares_follow_a_bent_path: gate %d at %s, expected %s across %s" % [g, _gate_centre(segments, g), expected, along])
			return 1
	return 0

func _pad() -> Vector3:
	return Vector3(sin(PAD_ANGLE), 0.0, cos(PAD_ANGLE)) * PAD_RADIUS

func _ship(radius: float, turn: float, y: float) -> Vector3:
	return Vector3(sin(PAD_ANGLE + turn) * radius, y, cos(PAD_ANGLE + turn) * radius)

func _path(ship: Vector3) -> PackedVector3Array:
	return ApproachGuide.approach_path(ship, _pad(), SECTION_RADIUS, HALF_GAP)

# Ships around the bridge: [name, ship]. All outside the gap between the two
# sections, so the path must curve to the entry point.
func _ships_outside_the_gap() -> Array:
	return [
		["in front, far", _ship(5000.0, 0.0, 0.0)],
		["along the ring, behind a section", _ship(2500.0, 0.0, 6000.0)],
		["other side of the bridge", _ship(3000.0, PI, 0.0)],
		["skimming a section", _ship(2050.0, 1.0, 4000.0)],
		["far and to the side", _ship(8000.0, -1.0, -6000.0)],
		["just past the rim", _ship(2100.0, 0.5, 1000.0)],
	]

func _test_path_runs_from_the_ship_to_the_pad() -> int:
	for c in _ships_outside_the_gap():
		var path := _path(c[1])
		if path.size() < 3 or not path[0].is_equal_approx(c[1]) or not path[path.size() - 1].is_equal_approx(_pad()):
			print("FAIL _test_path_runs_from_the_ship_to_the_pad (%s): %d points, from %s to %s" % [c[0], path.size(), path[0] if path.size() > 0 else null, path[path.size() - 1] if path.size() > 0 else null])
			return 1
	return 0

func _test_path_ends_straight_along_the_pad_normal() -> int:
	var normal := _pad().normalized()
	var entry := normal * (SECTION_RADIUS + ApproachGuide.ENTRY_MARGIN)
	for c in _ships_outside_the_gap():
		var path := _path(c[1])
		var last := path.size() - 1
		# The last leg: straight in from the entry point, 300 m past the
		# sections' radius, along the pad's normal.
		if not path[last - 1].is_equal_approx(entry):
			print("FAIL _test_path_ends_straight_along_the_pad_normal (%s): last leg starts at %s, expected %s" % [c[0], path[last - 1], entry])
			return 1
		# Arriving from outside the entry radius, the curve already runs
		# along the normal as it reaches the entry point: no kink.
		if Vector2(c[1].x, c[1].z).length() > entry.length():
			var arriving: Vector3 = (path[last - 1] - path[last - 2]).normalized()
			if arriving.dot(-normal) < 0.99:
				print("FAIL _test_path_ends_straight_along_the_pad_normal (%s): the curve meets the last leg at an angle (%s)" % [c[0], arriving])
				return 1
	return 0

func _test_path_never_enters_a_section() -> int:
	for c in _ships_outside_the_gap():
		var path := _path(c[1])
		for i in range(1, path.size()):
			for k in range(11):
				var p: Vector3 = path[i - 1].lerp(path[i], k / 10.0)
				if absf(p.y) > HALF_GAP and Vector2(p.x, p.z).length() < SECTION_RADIUS:
					print("FAIL _test_path_never_enters_a_section (%s): point %s is inside a section" % [c[0], p])
					return 1
	return 0

func _test_path_is_straight_inside_the_gap() -> int:
	# Between the two sections and inside the entry radius nothing stands in
	# the way of the sections: straight to the pad.
	var ship := _ship(1500.0, 0.5, 300.0)
	var path := _path(ship)
	if path.size() != 2 or not path[0].is_equal_approx(ship) or not path[1].is_equal_approx(_pad()):
		print("FAIL _test_path_is_straight_inside_the_gap: got %s" % [path])
		return 1
	return 0
