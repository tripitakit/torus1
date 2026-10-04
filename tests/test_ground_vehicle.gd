extends SceneTree

# The ground vehicle's driving (GroundVehicle): speed, steering, slopes, and
# (with a made-up ground) the ground, the air and the tilt.

const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const DT := 1.0 / 60.0
const MOON_G := 1.62

func _init():
	var failures := 0
	failures += _test_throttle_reaches_top_speed_and_no_more()
	failures += _test_coasting_slows_down()
	failures += _test_back_brakes_then_reverses()
	failures += _test_turn_radius_grows_with_speed()
	failures += _test_reverse_turns_like_a_car()
	failures += _test_steering_eases_in_and_out()
	failures += _test_engine_weakens_uphill()
	failures += _test_steep_slope_slides_back()
	failures += _test_handbrake_stops()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# `seconds` of the same controls on a slope, from `speed`.
func _speed_after(speed: float, throttle: float, handbrake: bool, slope: float, seconds: float) -> float:
	for i in range(roundi(seconds / DT)):
		speed = GroundVehicle.next_speed(speed, throttle, handbrake, slope, MOON_G, DT)
	return speed

func _test_throttle_reaches_top_speed_and_no_more() -> int:
	var after_2 := _speed_after(0.0, 1.0, false, 0.0, 2.0)
	var after_20 := _speed_after(0.0, 1.0, false, 0.0, 20.0)
	if absf(after_2 - 6.0) > 0.05 or absf(after_20 - 20.0) > 1e-6:
		print("FAIL _test_throttle_reaches_top_speed_and_no_more: %.3f after 2 s, %.3f after 20 s" % [after_2, after_20])
		return 1
	return 0

func _test_coasting_slows_down() -> int:
	var after := _speed_after(10.0, 0.0, false, 0.0, 5.0)
	if absf(after - 7.0) > 0.05:
		print("FAIL _test_coasting_slows_down: %.3f m/s, expected 7" % after)
		return 1
	return 0

func _test_back_brakes_then_reverses() -> int:
	var braked := _speed_after(12.0, -1.0, false, 0.0, 1.0)
	var stopped := _speed_after(12.0, -1.0, false, 0.0, 2.0)
	var reversing := _speed_after(12.0, -1.0, false, 0.0, 10.0)
	# After 2 s of S from 12 m/s (6 m/s²) it has just stopped: at most a tick of reverse.
	if absf(braked - 6.0) > 0.05 or stopped > 0.01 or stopped < -0.1 or absf(reversing + 5.0) > 1e-6:
		print("FAIL _test_back_brakes_then_reverses: %.3f after 1 s, %.3f after 2 s, %.3f after 10 s" % [braked, stopped, reversing])
		return 1
	return 0

func _test_turn_radius_grows_with_speed() -> int:
	var standing := GroundVehicle.turn_radius(0.0)
	var top := GroundVehicle.turn_radius(20.0)
	var rate := GroundVehicle.yaw_rate(20.0, 1.0)
	if absf(standing - 6.0) > 1e-6 or absf(top - 40.0) > 1e-6 or absf(rate + 0.5) > 1e-6:
		print("FAIL _test_turn_radius_grows_with_speed: %.2f m, %.2f m, %.3f rad/s" % [standing, top, rate])
		return 1
	return 0

# D (steer +1) going forward turns right (negative about up); going back the
# nose swings the other way, as in a car.
func _test_reverse_turns_like_a_car() -> int:
	var forward := GroundVehicle.yaw_rate(5.0, 1.0)
	var back := GroundVehicle.yaw_rate(-5.0, 1.0)
	if forward >= 0.0 or back <= 0.0:
		print("FAIL _test_reverse_turns_like_a_car: forward %.3f, back %.3f" % [forward, back])
		return 1
	return 0

func _test_steering_eases_in_and_out() -> int:
	var steer := 0.0
	for i in range(9):  # 0.15 s
		steer = GroundVehicle.next_steer(steer, 1.0, DT)
	var half := steer
	for i in range(9):
		steer = GroundVehicle.next_steer(steer, 1.0, DT)
	var full := steer
	for i in range(12):  # 0.2 s
		steer = GroundVehicle.next_steer(steer, 0.0, DT)
	if absf(half - 0.5) > 0.01 or absf(full - 1.0) > 1e-6 or absf(steer) > 1e-6:
		print("FAIL _test_steering_eases_in_and_out: %.3f, %.3f, %.3f" % [half, full, steer])
		return 1
	return 0

func _test_engine_weakens_uphill() -> int:
	var flat := _speed_after(0.0, 1.0, false, 0.0, 2.0)
	var at_30 := _speed_after(0.0, 1.0, false, deg_to_rad(30.0), 2.0)
	var at_36 := _speed_after(0.0, 1.0, false, deg_to_rad(36.0), 2.0)
	# Backing down the same 30-degree hill: full engine.
	var down := _speed_after(0.0, -1.0, false, deg_to_rad(30.0), 1.0)
	if absf(at_30 - flat * 0.5) > 0.05 or at_36 > 0.0 or absf(down + 3.0) > 0.05:
		print("FAIL _test_engine_weakens_uphill: flat %.2f, 30° %.2f, 36° %.2f, back down %.2f" % [flat, at_30, at_36, down])
		return 1
	return 0

func _test_steep_slope_slides_back() -> int:
	var slid := _speed_after(0.0, 0.0, false, deg_to_rad(40.0), 3.0)
	var held := _speed_after(0.0, 0.0, false, deg_to_rad(30.0), 3.0)
	if slid > -0.5 or held != 0.0:
		print("FAIL _test_steep_slope_slides_back: 40° %.3f, 30° %.3f" % [slid, held])
		return 1
	return 0

func _test_handbrake_stops() -> int:
	var stopped := _speed_after(16.0, 1.0, true, 0.0, 2.1)
	if stopped != 0.0:
		print("FAIL _test_handbrake_stops: %.3f m/s" % stopped)
		return 1
	return 0
