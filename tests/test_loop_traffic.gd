extends SceneTree

# Rounded-rectangle loops flown (or driven, or walked) by the shader alone:
# the path is continuous and closed, the object faces its way either way
# round, the GPU data gives the same pose as the GDScript copy, and TIME's
# restart every hour never shows.

const LoopTraffic = preload("res://scripts/loop_traffic.gd")

var _failures := 0

func _initialize():
	_failures += _test_continuous_closed_and_facing()
	_failures += _test_reverse_goes_the_other_way()
	_failures += _test_data_matches_pose()
	_failures += _test_same_an_hour_later()
	_failures += _test_stops_at_its_stop_each_lap()
	_failures += _test_stop_data_matches_pose()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _loops() -> Array:
	return [
		LoopTraffic.make_loop(LoopTraffic.FLAT, -20.0, -15.0, 40.0, 30.0, 4.0, 1.5, 0.3, -596.0, 7),
		LoopTraffic.make_loop(LoopTraffic.CYLINDER, 9000.0, -3000.0, 500.0, 300.0, 30.0, 10.0, 0.7, 2000.0, 11),
	]

func _test_continuous_closed_and_facing() -> int:
	for loop: Dictionary in _loops():
		var length := LoopTraffic.loop_length(loop)
		var step := 0.5
		var last := LoopTraffic.pose(loop, 0.0)
		var s := step
		while s <= length + 0.0001:
			var now := LoopTraffic.pose(loop, s)
			var moved := last.origin.distance_to(now.origin)
			if moved > step * 1.02 or moved < step * 0.95:
				print("FAIL _test_continuous_closed_and_facing: jump %.3f at s %.1f (mode %d)" % [moved, s, loop.mode])
				return 1
			if now.basis.z.dot((now.origin - last.origin).normalized()) < 0.99:
				print("FAIL _test_continuous_closed_and_facing: not facing its way at s %.1f (mode %d)" % [s, loop.mode])
				return 1
			last = now
			s += step
		if LoopTraffic.pose(loop, 0.0).origin.distance_to(LoopTraffic.pose(loop, length).origin) > 0.001:
			print("FAIL _test_continuous_closed_and_facing: not closed (mode %d)" % loop.mode)
			return 1
	return 0

func _test_reverse_goes_the_other_way() -> int:
	var loop: Dictionary = _loops()[0]
	var back := loop.duplicate()
	back.laps = -loop.laps
	var a := LoopTraffic.pose_at(back, 10.0)
	var b := LoopTraffic.pose_at(back, 10.2)
	var forward_a := LoopTraffic.pose_at(loop, 10.0)
	if a.basis.z.dot((b.origin - a.origin).normalized()) < 0.99 or a.basis.z.dot(LoopTraffic.pose(back, LoopTraffic.pose_s(back, 10.0)).basis.z) < 0.99:
		print("FAIL _test_reverse_goes_the_other_way: not facing its way backwards")
		return 1
	if forward_a.origin.is_equal_approx(a.origin) and forward_a.basis.z.is_equal_approx(a.basis.z):
		print("FAIL _test_reverse_goes_the_other_way: same as forwards")
		return 1
	return 0

func _test_data_matches_pose() -> int:
	var loops := _loops()
	var data := LoopTraffic.instance_buffer(loops)
	for i in range(loops.size()):
		for t in [0.0, 33.3, 1234.5]:
			var expected := LoopTraffic.pose_at(loops[i], t)
			var got := LoopTraffic.pose_from_data(data, i, t, loops[i].corner)
			if got.origin.distance_to(expected.origin) > 0.01 or not got.basis.z.is_equal_approx(expected.basis.z):
				print("FAIL _test_data_matches_pose: loop %d at %.1f s: %s against %s" % [i, t, got.origin, expected.origin])
				return 1
	return 0

func _test_same_an_hour_later() -> int:
	var loops := _loops()
	var data := LoopTraffic.instance_buffer(loops)
	for i in range(loops.size()):
		if LoopTraffic.pose_from_data(data, i, 5.0, loops[i].corner).origin.distance_to(LoopTraffic.pose_from_data(data, i, 3605.0, loops[i].corner).origin) > 0.02:
			print("FAIL _test_same_an_hour_later: loop %d" % i)
			return 1
	return 0

func _stopping() -> Dictionary:
	var loop := LoopTraffic.make_loop(LoopTraffic.CYLINDER, 9000.0, -3000.0, 500.0, 300.0, 30.0, 10.0, 0.0, 2000.0, 11)
	return LoopTraffic.with_stop(loop, 123.0, 10.0, 17.0)

func _test_stops_at_its_stop_each_lap() -> int:
	# Over one lap: still at the stop for STOP_DWELL, never jumping, the lap
	# a whole fraction of an hour.
	var loop := _stopping()
	var lap := LoopTraffic.lap_time(loop)
	if absf(3600.0 / lap - roundf(3600.0 / lap)) > 0.0001:
		print("FAIL _test_stops_at_its_stop_each_lap: lap of %.3f s" % lap)
		return 1
	var stop_point := LoopTraffic.pose(loop, loop.stop).origin
	var still := 0.0
	var step := 0.1
	var last := LoopTraffic.pose_at(loop, 0.0).origin
	var t := step
	var top := LoopTraffic.cruise_speed(loop)
	while t <= lap:
		var now := LoopTraffic.pose_at(loop, t).origin
		if now.distance_to(last) > top * step * 1.02 + 0.001:
			print("FAIL _test_stops_at_its_stop_each_lap: jump %.2f m at %.1f s" % [now.distance_to(last), t])
			return 1
		if now.distance_to(stop_point) < 0.001:
			still += step
		last = now
		t += step
	if absf(still - LoopTraffic.STOP_DWELL) > 0.3 or top < 5.0 or top > 10.0:
		print("FAIL _test_stops_at_its_stop_each_lap: still %.1f s, cruising at %.1f m/s" % [still, top])
		return 1
	return 0

func _test_stop_data_matches_pose() -> int:
	var loops := [_stopping()]
	var data := LoopTraffic.instance_buffer(loops)
	for t in [3.0, 80.0, 400.0]:
		var expected := LoopTraffic.pose_at(loops[0], t)
		var got := LoopTraffic.pose_from_data(data, 0, t, loops[0].corner)
		if got.origin.distance_to(expected.origin) > 0.01:
			print("FAIL _test_stop_data_matches_pose: %.1f s: %s against %s" % [t, got.origin, expected.origin])
			return 1
	if LoopTraffic.pose_from_data(data, 0, 7.0, 30.0).origin.distance_to(LoopTraffic.pose_from_data(data, 0, 3607.0, 30.0).origin) > 0.02:
		print("FAIL _test_stop_data_matches_pose: moved after an hour")
		return 1
	return 0
