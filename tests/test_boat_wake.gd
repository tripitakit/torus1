extends SceneTree

# The boats' wakes: points where the boat was `lag` seconds ago, fading with
# the lag and with the boat's speed then, lifted off the water more the
# farther the camera.

const BoatWake = preload("res://scripts/boat_wake.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")

func _initialize():
	var failures := 0
	failures += _test_point_where_the_boat_was()
	failures += _test_fades_with_the_lag()
	failures += _test_stopped_boat_leaves_no_wake()
	failures += _test_lift_grows_with_distance()
	failures += _test_mesh_lags_in_range()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _cruising() -> Dictionary:
	return LoopTraffic.make_loop(LoopTraffic.FLAT, 0.0, 0.0, 400.0, 200.0, 30.0, 10.0, 0.0, 0.0, 0)

func _test_point_where_the_boat_was() -> int:
	var loop := _cruising()
	var then := LoopTraffic.pose_at(loop, 98.0)
	var expected := then.origin + then.basis.x * 2.0 + then.basis.z * -5.0 + then.basis.y * 0.15
	var got: Vector3 = BoatWake.wake_point(loop, 100.0, 2.0, 2.0, -5.0, 0.15)
	if got.distance_to(expected) > 1e-6:
		print("FAIL _test_point_where_the_boat_was: %s, expected %s" % [got, expected])
		return 1
	return 0

func _test_fades_with_the_lag() -> int:
	var loop := _cruising()
	var early: float = BoatWake.wake_alpha(loop, 100.0, 1.0, 6.0, 1.0)
	var late: float = BoatWake.wake_alpha(loop, 100.0, 5.0, 6.0, 1.0)
	var gone: float = BoatWake.wake_alpha(loop, 100.0, 6.0, 6.0, 1.0)
	if not (early > late and late > 0.0 and gone == 0.0):
		print("FAIL _test_fades_with_the_lag: %.3f, %.3f, %.3f" % [early, late, gone])
		return 1
	return 0

# A loop with a stop: halfway through the dwell the boat has been still
# for 10 s, so even its freshest wake is gone.
func _test_stopped_boat_leaves_no_wake() -> int:
	var loop := LoopTraffic.with_stop(_cruising(), 100.0, 10.0, 0.0)
	var lap := LoopTraffic.lap_time(loop)
	var t := lap - LoopTraffic.STOP_DWELL * 0.5
	var alpha: float = BoatWake.wake_alpha(loop, t, 0.5, 6.0, 1.0)
	var moving: float = BoatWake.wake_alpha(loop, lap * 0.4, 0.5, 6.0, 1.0)
	if alpha != 0.0 or moving <= 0.5:
		print("FAIL _test_stopped_boat_leaves_no_wake: at the stop %.3f, cruising %.3f" % [alpha, moving])
		return 1
	return 0

func _test_lift_grows_with_distance() -> int:
	var near: float = BoatWake.wake_lift(10.0)
	var far: float = BoatWake.wake_lift(1000.0)
	if absf(near - 0.15) > 1e-6 or absf(far - 0.6) > 1e-6:
		print("FAIL _test_lift_grows_with_distance: %.3f, %.3f" % [near, far])
		return 1
	return 0

func _test_mesh_lags_in_range() -> int:
	var arrays: Array = BoatWake.wake_mesh().surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var longest := 0.0
	for uv in uvs:
		if uv.x < 0.0 or uv.x > BoatWake.ARM_TIME + 1e-6:
			print("FAIL _test_mesh_lags_in_range: lag %.2f" % uv.x)
			return 1
		longest = maxf(longest, uv.x)
	if uvs.is_empty() or absf(longest - BoatWake.ARM_TIME) > 1e-6:
		print("FAIL _test_mesh_lags_in_range: %d vertices, longest lag %.2f" % [uvs.size(), longest])
		return 1
	return 0
