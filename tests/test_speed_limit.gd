extends SceneTree

# The speed limit by zone, and how it holds the ship to it: pure math.

const SpeedLimit = preload("res://scripts/speed_limit.gd")

func _init():
	var failures := 0
	failures += _test_zones()
	failures += _test_ring_distance()
	failures += _test_under_the_limit_untouched()
	failures += _test_thrust_stops_at_the_limit()
	failures += _test_turning_at_the_limit_keeps_the_speed()
	failures += _test_over_the_limit_brakes_down_to_it()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_zones() -> int:
	# Near Torus1 or a gate 500 m/s, in the moon's frame 800, else 3000.
	var cases := [
		[5000.0, 90000.0, false, SpeedLimit.NEAR_LIMIT, 500.0],
		[90000.0, 15000.0, false, SpeedLimit.NEAR_LIMIT, 500.0],
		[90000.0, 90000.0, true, SpeedLimit.MOON_LIMIT, 800.0],
		[90000.0, 90000.0, false, SpeedLimit.OPEN_LIMIT, 3000.0],
		# A gate near the moon (the moon portal): the slower wins.
		[INF, 10000.0, true, SpeedLimit.NEAR_LIMIT, 500.0],
	]
	for c in cases:
		var limit := SpeedLimit.limit(c[0], c[1], c[2])
		if limit != c[3] or c[3] != c[4]:
			print("FAIL _test_zones: ring %.0f, gate %.0f, moon %s gave %.0f" % [c[0], c[1], c[2], limit])
			return 1
	return 0

func _test_ring_distance() -> int:
	# From the ring's surface: the tube of SECTION_RADIUS round the circle of
	# `ring_radius` about the planet's axis.
	var on_top := SpeedLimit.ring_distance(Vector3(0.0, 2000.0 + 7000.0, 6949600.0), Vector3.UP, 6949600.0, 2000.0)
	var outside := SpeedLimit.ring_distance(Vector3(6949600.0 + 32000.0, 0.0, 0.0), Vector3.UP, 6949600.0, 2000.0)
	if absf(on_top - 7000.0) > 0.01 or absf(outside - 30000.0) > 0.01:
		print("FAIL _test_ring_distance: %.2f, %.2f" % [on_top, outside])
		return 1
	return 0

func _test_under_the_limit_untouched() -> int:
	var v := Vector3(100.0, 0.0, 0.0)
	var capped := SpeedLimit.cap(v, 90.0, 500.0, 1500.0, 1.0 / 60.0)
	if not capped.is_equal_approx(v):
		print("FAIL _test_under_the_limit_untouched: %s" % capped)
		return 1
	return 0

func _test_thrust_stops_at_the_limit() -> int:
	# 495 m/s pushed to 520 in a tick: held at 500.
	var capped := SpeedLimit.cap(Vector3(520.0, 0.0, 0.0), 495.0, 500.0, 1500.0, 1.0 / 60.0)
	if not capped.is_equal_approx(Vector3(500.0, 0.0, 0.0)):
		print("FAIL _test_thrust_stops_at_the_limit: %s" % capped)
		return 1
	return 0

func _test_turning_at_the_limit_keeps_the_speed() -> int:
	# At the limit, a push across turns the motion without adding speed.
	var capped := SpeedLimit.cap(Vector3(500.0, 30.0, 0.0), 500.0, 500.0, 1500.0, 1.0 / 60.0)
	if absf(capped.length() - 500.0) > 0.001 or capped.y <= 0.0:
		print("FAIL _test_turning_at_the_limit_keeps_the_speed: %s" % capped)
		return 1
	return 0

func _test_over_the_limit_brakes_down_to_it() -> int:
	# 3000 m/s into the 500 zone: down by the brake each tick, never under
	# the limit.
	var delta := 1.0 / 60.0
	var v := Vector3(3000.0, 0.0, 0.0)
	var capped := SpeedLimit.cap(v, 3000.0, 500.0, 1500.0, delta)
	if absf(capped.length() - (3000.0 - 1500.0 * delta)) > 0.001:
		print("FAIL _test_over_the_limit_brakes_down_to_it: one tick to %.2f" % capped.length())
		return 1
	var speed := 3000.0
	for tick in range(200):
		v = SpeedLimit.cap(v, speed, 500.0, 1500.0, delta)
		speed = v.length()
	if absf(speed - 500.0) > 0.001 or not SpeedLimit.braking(510.0, 500.0) or SpeedLimit.braking(500.5, 500.0):
		print("FAIL _test_over_the_limit_brakes_down_to_it: settled at %.2f" % speed)
		return 1
	return 0
