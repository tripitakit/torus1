extends SceneTree

# Life on the dock platform: people walking round it clear of the landing
# square in the middle, service carts round its edge, cargo drones circling
# above its corners. All on the platform's plane (dock frame).

const DockCrowd = preload("res://scripts/dock_crowd.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")

const TOP := -596.0
const HALF := 30.0

var _failures := 0

func _initialize():
	_failures += _test_people_on_the_platform_off_the_landing_square()
	_failures += _test_carts_round_the_edge()
	_failures += _test_drones_above_the_corners()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# The widest and narrowest of max(|x|, |z|) round a loop, and its heights.
func _extent(loop: Dictionary) -> Vector4:
	var low := INF
	var high := -INF
	var y_low := INF
	var y_high := -INF
	var s := 0.0
	while s < LoopTraffic.loop_length(loop):
		var p := LoopTraffic.pose(loop, s).origin
		var d := maxf(absf(p.x), absf(p.z))
		low = minf(low, d)
		high = maxf(high, d)
		y_low = minf(y_low, p.y)
		y_high = maxf(y_high, p.y)
		s += 0.5
	return Vector4(low, high, y_low, y_high)

func _test_people_on_the_platform_off_the_landing_square() -> int:
	var people := DockCrowd.people(TOP, 3)
	if people.size() != DockCrowd.PEOPLE:
		print("FAIL _test_people_on_the_platform_off_the_landing_square: %d people" % people.size())
		return 1
	for loop: Dictionary in people:
		var e := _extent(loop)
		if e.x < DockCrowd.LANDING_HALF + 0.5 or e.y > HALF - 0.5 or absf(e.z - TOP) > 0.001 or absf(e.w - TOP) > 0.001:
			print("FAIL _test_people_on_the_platform_off_the_landing_square: loop from %.1f to %.1f at %.1f" % [e.x, e.y, e.z])
			return 1
	return 0

func _test_carts_round_the_edge() -> int:
	var carts := DockCrowd.carts(TOP)
	var people_out := 0.0
	for loop: Dictionary in DockCrowd.people(TOP, 3):
		people_out = maxf(people_out, _extent(loop).y)
	for loop: Dictionary in carts:
		var e := _extent(loop)
		if e.x < people_out + 1.5 or e.y > HALF - 1.0:
			print("FAIL _test_carts_round_the_edge: cart loop from %.1f to %.1f (people out to %.1f)" % [e.x, e.y, people_out])
			return 1
	if carts.size() != DockCrowd.CARTS:
		print("FAIL _test_carts_round_the_edge: %d carts" % carts.size())
		return 1
	return 0

func _test_drones_above_the_corners() -> int:
	var drones := DockCrowd.drones(TOP, 3)
	if drones.size() != DockCrowd.DRONES:
		print("FAIL _test_drones_above_the_corners: %d drones" % drones.size())
		return 1
	for loop: Dictionary in drones:
		var e := _extent(loop)
		if e.z < TOP + DockCrowd.DRONE_HEIGHTS.x - 0.01 or e.w > TOP + DockCrowd.DRONE_HEIGHTS.y + 0.01 or e.x < DockCrowd.LANDING_HALF:
			print("FAIL _test_drones_above_the_corners: drone loop %s" % e)
			return 1
	return 0
