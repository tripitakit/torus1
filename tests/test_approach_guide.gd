extends SceneTree

const ApproachGuide = preload("res://scripts/approach_guide.gd")

# A bridge like the real one, in its own frame (axis = Y): sections of
# 2000 m radius begin 917 m either side of the pad; the bridge is a 64-sided
# prism of 600 m radius and the pad lies on its face 15.
const SECTION_RADIUS := 2000.0
const HALF_GAP := 917.0
const BRIDGE_RADIUS := 600.0
var PAD_ANGLE := 15.5 * TAU / 64.0
var PAD_RADIUS := BRIDGE_RADIUS * cos(PI / 64.0) + 0.3

func _init():
	var failures := 0
	failures += _test_gate_distances_by_length()
	failures += _test_squares_are_30_m_across_the_line()
	failures += _test_squares_stay_square_when_up_is_along_the_line()
	failures += _test_squares_follow_a_bent_path()
	failures += _test_path_runs_from_the_ship_to_the_pad()
	failures += _test_path_leaves_along_the_nose()
	failures += _test_path_meets_the_pad_square_on()
	failures += _test_path_never_enters_the_station()
	failures += _test_path_has_no_sharp_bends()
	failures += _test_path_is_straight_when_lined_up()
	failures += _test_path_curves_down_into_the_gap()
	failures += _test_rim_choice_holds_near_the_switch()
	failures += _test_path_follows_the_rim_choice()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_gate_distances_by_length() -> int:
	var result := 0
	# [path length, gate count, first gate, spacing]. The range is the
	# ship's business: a path longer than it still gets its first gates.
	for c in [[20000.0, 40, 100.0, 500.0], [10000.0, 40, 100.0, 250.0], [1000.0, 18, 100.0, 50.0], [150.0, 1, 100.0, 0.0], [30000.0, 40, 100.0, 500.0]]:
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
		var centre := _square_centre(segments, g)
		if not centre.is_equal_approx(ship + along * gates[g]):
			print("FAIL %s: gate %d centred at %s, expected %s" % [test_name, g, centre, ship + along * gates[g]])
			return 1
		if not _is_square_across(segments, g, along, ApproachGuide.GATE_SIZE):
			print("FAIL %s: gate %d is not a 30 m square across the line" % [test_name, g])
			return 1
	return 0

func _square_centre(segments: PackedVector3Array, g: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += segments[g * 8 + k]
	return centre / 8.0

func _is_square_across(segments: PackedVector3Array, g: int, along: Vector3, size: float) -> bool:
	var centre := _square_centre(segments, g)
	for k in range(0, 8, 2):
		var a := segments[g * 8 + k]
		var b := segments[g * 8 + k + 1]
		if absf(a.distance_to(b) - size) > 1e-3 or absf((a - centre).dot(along)) > 1e-3:
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
		if not _square_centre(segments, g).is_equal_approx(expected) or not _is_square_across(segments, g, along, ApproachGuide.GATE_SIZE):
			print("FAIL _test_squares_follow_a_bent_path: gate %d at %s, expected %s across %s" % [g, _square_centre(segments, g), expected, along])
			return 1
	return 0

func _pad() -> Vector3:
	return Vector3(sin(PAD_ANGLE), 0.0, cos(PAD_ANGLE)) * PAD_RADIUS

func _at(radius: float, turn: float, y: float) -> Vector3:
	return Vector3(sin(PAD_ANGLE + turn) * radius, y, cos(PAD_ANGLE + turn) * radius)

func _toward_pad(ship: Vector3) -> Vector3:
	return (_pad() - ship).normalized()

func _path(c: Array) -> PackedVector3Array:
	return ApproachGuide.approach_path(c[1], c[2], _pad(), SECTION_RADIUS, HALF_GAP, BRIDGE_RADIUS)

# Ships well clear of the station, nose free: [name, ship, nose].
func _clear_ships() -> Array:
	var cases := []
	for c in [["in front, nose at the pad", _at(5000.0, 0.0, 0.0)], ["along the ring, behind a section", _at(2500.0, 0.0, 6000.0)],
			["other side of the bridge", _at(3000.0, PI, 0.0)], ["20 km out", _at(19000.0, -1.0, -6000.0)],
			["planet side", _at(12000.0, PI, 3000.0)], ["in the gap, other side", _at(1000.0, 2.5, 200.0)],
			["far along the axis", _at(3000.0, 0.2, 10500.0)], ["close in front", _at(1000.0, 0.0, 0.0)]]:
		cases.append([c[0], c[1], _toward_pad(c[1])])
	var back := _at(8000.0, 0.5, 2000.0)
	cases.append(["nose turned back", back, -_toward_pad(back)])
	return cases

# Ships whose nose points into the station, or that are already inside a
# margin: the path turns at once, but must still keep off the station.
func _awkward_ships() -> Array:
	var into := _at(2400.0, 0.3, 3000.0)
	var skim := _at(2050.0, 1.0, 4000.0)
	return [
		["nose into a section", into, -Vector3(into.x, 0.0, into.z).normalized()],
		["skimming a section", skim, _toward_pad(skim)],
		["nose at a section's end", _at(1500.0, 0.8, 800.0), Vector3.UP],
	]

func _test_path_runs_from_the_ship_to_the_pad() -> int:
	for c in _clear_ships() + _awkward_ships():
		var path := _path(c)
		if path.size() < 3 or not path[0].is_equal_approx(c[1]) or not path[path.size() - 1].is_equal_approx(_pad()):
			print("FAIL _test_path_runs_from_the_ship_to_the_pad (%s): %d points" % [c[0], path.size()])
			return 1
	return 0

func _test_path_leaves_along_the_nose() -> int:
	# The first gates sit in the middle of the pilot's view.
	for c in _clear_ships():
		var path := _path(c)
		var leaving := (path[1] - path[0]).normalized()
		if leaving.dot(c[2]) < 0.99:
			print("FAIL _test_path_leaves_along_the_nose (%s): leaves along %s, nose %s" % [c[0], leaving, c[2]])
			return 1
	return 0

func _test_path_meets_the_pad_square_on() -> int:
	var inward := -_pad().normalized()
	for c in _clear_ships() + _awkward_ships():
		var path := _path(c)
		var arriving := (path[path.size() - 1] - path[path.size() - 2]).normalized()
		if arriving.dot(inward) < 0.99:
			print("FAIL _test_path_meets_the_pad_square_on (%s): arrives along %s" % [c[0], arriving])
			return 1
	return 0

# Inside a section, or inside the bridge's prism (its faces are
# cos(pi/64) of the radius from the axis).
func _in_station(p: Vector3) -> bool:
	var r := Vector2(p.x, p.z).length()
	if absf(p.y) > HALF_GAP:
		return r < SECTION_RADIUS
	return r < BRIDGE_RADIUS * cos(PI / 64.0) - 0.5

func _test_path_never_enters_the_station() -> int:
	for c in _clear_ships() + _awkward_ships():
		var path := _path(c)
		for i in range(1, path.size()):
			for k in range(21):
				var p: Vector3 = path[i - 1].lerp(path[i], k / 20.0)
				if _in_station(p):
					print("FAIL _test_path_never_enters_the_station (%s): %s is inside" % [c[0], p])
					return 1
	return 0

func _test_path_has_no_sharp_bends() -> int:
	for c in _clear_ships():
		var path := _path(c)
		for i in range(2, path.size()):
			var bend := rad_to_deg((path[i - 1] - path[i - 2]).angle_to(path[i] - path[i - 1]))
			if bend > 15.0:
				print("FAIL _test_path_has_no_sharp_bends (%s): %.1f degrees at point %d" % [c[0], bend, i - 1])
				return 1
	return 0

func _test_path_is_straight_when_lined_up() -> int:
	# Straight out in front of the pad, nose on it: nothing to go round.
	var c: Array = _clear_ships()[0]
	var path := _path(c)
	var line: Vector3 = _toward_pad(c[1])
	for p in path:
		var off: Vector3 = (p - c[1]) - line * (p - c[1]).dot(line)
		if off.length() > 1.0:
			print("FAIL _test_path_is_straight_when_lined_up: %s is %.1f m off the line" % [p, off.length()])
			return 1
	return 0

func _test_path_curves_down_into_the_gap() -> int:
	# Behind a section there is no long straight run down to the pad: a
	# kilometre out along the path it is still turning toward the normal.
	var path := _path(_clear_ships()[1])
	var inward := -_pad().normalized()
	var walked := 0.0
	var i := path.size() - 1
	while i > 1 and walked < 1000.0:
		walked += path[i].distance_to(path[i - 1])
		i -= 1
	var there := (path[i + 1] - path[i]).normalized()
	if there.dot(inward) > cos(deg_to_rad(10.0)):
		print("FAIL _test_path_curves_down_into_the_gap: straight along the normal for the last kilometre")
		return 1
	return 0

# Counts how often the rim choice flips along `ships` ([ship, nose] each),
# carrying the choice from one to the next as the ship does frame to frame.
func _rim_flips(ships: Array) -> int:
	var flips := 0
	var over := false
	for i in range(ships.size()):
		var now: bool = ApproachGuide.over_rim(ships[i][0], ships[i][1], _pad(), SECTION_RADIUS, HALF_GAP, over)
		if i > 0 and now != over:
			flips += 1
		over = now
	return flips

func _test_rim_choice_holds_near_the_switch() -> int:
	var result := 0
	# Closing in 1 m at a time: without a margin the path flipped between
	# its two shapes, moving far gates by over a kilometre in one frame.
	var closing := []
	for step in range(4001):
		var ship := _at(4000.0, 1.5, 4000.0 - step)
		closing.append([ship, _toward_pad(ship)])
	var flips := _rim_flips(closing)
	if flips > 1:
		print("FAIL _test_rim_choice_holds_near_the_switch: %d flips closing in along the ring" % flips)
		result = 1
	# The nose wandering a degree either side of the pad, as a pilot's does.
	var wandering := []
	var ship := _at(5000.0, 0.0, 3000.0)
	var side := _toward_pad(ship).cross(Vector3.UP).normalized()
	for step in range(320):
		var degrees := -1.0 + 0.05 * float(pingpong(step, 40))
		wandering.append([ship, _toward_pad(ship).rotated(side, deg_to_rad(degrees))])
	flips = _rim_flips(wandering)
	if flips > 1:
		print("FAIL _test_rim_choice_holds_near_the_switch: %d flips with the nose wandering 1 degree" % flips)
		result = 1
	return result

# A ship whose single curve clears the rim, but by less than the margin
# that ends the rim shape: [ship, nose], or [] if none is found.
func _ship_in_the_rim_margin() -> Array:
	for step in range(4001):
		var ship := _at(4000.0, 1.5, 4000.0 - step)
		var nose := _toward_pad(ship)
		if not ApproachGuide.over_rim(ship, nose, _pad(), SECTION_RADIUS, HALF_GAP, false) and ApproachGuide.over_rim(ship, nose, _pad(), SECTION_RADIUS, HALF_GAP, true):
			return [ship, nose]
	return []

func _test_path_follows_the_rim_choice() -> int:
	var c := _ship_in_the_rim_margin()
	if c.is_empty():
		print("FAIL _test_path_follows_the_rim_choice: no ship in the rim margin")
		return 1
	var single: PackedVector3Array = ApproachGuide.approach_path(c[0], c[1], _pad(), SECTION_RADIUS, HALF_GAP, BRIDGE_RADIUS, false)
	var over: PackedVector3Array = ApproachGuide.approach_path(c[0], c[1], _pad(), SECTION_RADIUS, HALF_GAP, BRIDGE_RADIUS, true)
	if single.size() != ApproachGuide.PATH_SAMPLES + 1 or over.size() != ApproachGuide.PATH_SAMPLES + ApproachGuide.SHOULDER_SAMPLES + 1:
		print("FAIL _test_path_follows_the_rim_choice: %d and %d points" % [single.size(), over.size()])
		return 1
	for path in [single, over]:
		for i in range(1, path.size()):
			for k in range(21):
				if _in_station(path[i - 1].lerp(path[i], k / 20.0)):
					print("FAIL _test_path_follows_the_rim_choice: a path enters the station")
					return 1
	return 0
