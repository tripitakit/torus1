extends SceneTree

# The speed limit by zone, and how it holds the ship to it: pure math.

const SpeedLimit = preload("res://scripts/speed_limit.gd")

func _init():
	var failures := 0
	failures += _test_zones()
	failures += _test_braking_curves_stop_in_time()
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
	# Near Torus1 or a gate 1000 m/s; low over the moon 800; far from all,
	# 50000 (15000 in the moon's frame); between, the braking curves.
	var curve := func(low: float, d: float) -> float: return sqrt(low * low + 2.0 * SpeedLimit.SAFE_BRAKE * d)
	var cases := [
		[5000.0, INF, false, INF, 1000.0],
		[INF, 15000.0, false, INF, 1000.0],
		[INF, INF, true, 1000.0, 800.0],
		[INF, INF, true, 30000.0, curve.call(800.0, 28000.0)],
		[INF, INF, true, 400000.0, 15000.0],
		[INF, INF, false, INF, 50000.0],
		[120000.0, INF, false, INF, curve.call(1000.0, 100000.0)],
		[INF, INF, false, 50000.0, curve.call(800.0, 48000.0)],
		# The moon's gate low over the moon: the slower wins.
		[INF, 10000.0, true, 1500.0, 800.0],
	]
	if SpeedLimit.NEAR_LIMIT != 1000.0 or SpeedLimit.MOON_LOW != 800.0 or SpeedLimit.MOON_TOP != 15000.0 or SpeedLimit.OPEN_LIMIT != 50000.0:
		print("FAIL _test_zones: the limits")
		return 1
	for c in cases:
		var limit := SpeedLimit.limit(c[0], c[1], c[2], c[3])
		if absf(limit - c[4]) > 0.01:
			print("FAIL _test_zones: ring %.0f, gate %.0f, moon frame %s, altitude %.0f gave %.0f, expected %.0f" % [c[0], c[1], c[2], c[3], limit, c[4]])
			return 1
	return 0

# Diving at the limit with the brake (1500 m/s2) holding the ship to it:
# low over the moon no faster than 800, at Torus1's zone no faster than 1000.
func _test_braking_curves_stop_in_time() -> int:
	var dt := 1.0 / 60.0
	var h := 400000.0
	var v := SpeedLimit.limit(INF, INF, true, h)
	while h > SpeedLimit.MOON_LOW_ALTITUDE:
		var before := v
		v = SpeedLimit.cap(Vector3(v, 0.0, 0.0), before, SpeedLimit.limit(INF, INF, true, h), 1500.0, dt).x
		h -= v * dt
	var d := 2.0e6
	var w := SpeedLimit.limit(d, INF, false, INF)
	while d > SpeedLimit.NEAR_RANGE:
		var before := w
		w = SpeedLimit.cap(Vector3(w, 0.0, 0.0), before, SpeedLimit.limit(d, INF, false, INF), 1500.0, dt).x
		d -= w * dt
	if v > SpeedLimit.MOON_LOW + 30.0 or w > SpeedLimit.NEAR_LIMIT + 30.0:
		print("FAIL _test_braking_curves_stop_in_time: %.0f m/s at 2 km over the moon, %.0f m/s into Torus1's zone" % [v, w])
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
