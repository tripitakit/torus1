extends SceneTree

# The ground vehicle's driving (GroundVehicle): speed, steering, slopes, and
# (with a made-up ground) the ground, the air and the tilt.

const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const DT := 1.0 / 60.0
const MOON_G := 1.62

# A made-up ground: a plane rising `angle` toward -Z (nose ahead), dropping
# `step` metres for z < step_at; up is always +Y.
class FakeGround:
	var angle := 0.0
	var step := 0.0
	var step_at := -INF
	# Past this the ramp tops out flat (a crest).
	var crest_at := -INF

	func surface(p: Vector3) -> float:
		var y := -maxf(p.z, crest_at) * tan(angle)
		if p.z < step_at:
			y -= step
		return y

	func ground_altitude(p: Vector3) -> float:
		return p.y - surface(p)

	func up_at(_p: Vector3) -> Vector3:
		return Vector3.UP

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
	failures += _test_drives_straight_on_flat_ground()
	failures += _test_d_turns_right()
	failures += _test_climbs_a_ramp_on_its_surface()
	failures += _test_leans_onto_the_ramp()
	failures += _test_drop_flies_then_lands()
	failures += _test_handbrake_holds_on_a_20_degree_ramp()
	failures += _test_crest_makes_a_small_jump()

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

# One tick: drive, move (no walls here), settle.
func _tick(body: Dictionary, controls: Dictionary, ground: FakeGround) -> Dictionary:
	body = GroundVehicle.drive(body, controls, ground, MOON_G, DT)
	body.transform = Transform3D(body.transform.basis, body.transform.origin + body.motion)
	return GroundVehicle.settle(body, ground, DT)

func _controls(throttle: float, steer := 0.0, handbrake := false) -> Dictionary:
	return {"throttle": throttle, "steer": steer, "handbrake": handbrake}

# On `ground` at `z`, nose to -Z, leaned onto the ground at once.
func _start(ground: FakeGround, z: float) -> Dictionary:
	var point := Vector3(0.0, ground.surface(Vector3(0.0, 0.0, z)), z)
	var body: Dictionary = GroundVehicle.new_body(Transform3D(GroundVehicle.heading_basis(Vector3.FORWARD, Vector3.UP), point))
	return GroundVehicle.settle(body, ground, 1.0)

func _test_drives_straight_on_flat_ground() -> int:
	var ground := FakeGround.new()
	var body := _start(ground, 0.0)
	for i in range(120):
		body = _tick(body, _controls(1.0), ground)
	var at: Vector3 = body.transform.origin
	# 2 s at 3 m/s²: about 6 m ahead, on the ground.
	if absf(at.z + 6.0) > 0.2 or absf(at.x) > 1e-6 or absf(at.y) > 1e-6 or body.airborne:
		print("FAIL _test_drives_straight_on_flat_ground: at %s, airborne %s" % [at, body.airborne])
		return 1
	return 0

func _test_d_turns_right() -> int:
	var ground := FakeGround.new()
	var body := _start(ground, 0.0)
	body.speed = 10.0
	for i in range(60):
		body = _tick(body, _controls(1.0, 1.0), ground)
	var nose: Vector3 = -body.transform.basis.z
	if nose.x <= 0.2 or body.transform.origin.x <= 0.0:
		print("FAIL _test_d_turns_right: nose %s, at %s" % [nose, body.transform.origin])
		return 1
	return 0

func _test_climbs_a_ramp_on_its_surface() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(20.0)
	var body := _start(ground, 0.0)
	var worst := 0.0
	for i in range(180):
		body = _tick(body, _controls(1.0), ground)
		worst = maxf(worst, absf(ground.ground_altitude(body.transform.origin)))
	if worst > 0.01 or body.transform.origin.y < 2.0 or body.airborne:
		print("FAIL _test_climbs_a_ramp_on_its_surface: %.3f m off the ground at worst, %.2f m up, airborne %s" % [worst, body.transform.origin.y, body.airborne])
		return 1
	return 0

func _test_leans_onto_the_ramp() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(20.0)
	var body := _start(ground, -10.0)
	var up: Vector3 = body.transform.basis.y.normalized()
	var expected := Vector3(0.0, cos(ground.angle), sin(ground.angle))
	if up.distance_to(expected) > 0.01:
		print("FAIL _test_leans_onto_the_ramp: up %s, expected %s" % [up, expected])
		return 1
	return 0

func _test_drop_flies_then_lands() -> int:
	var ground := FakeGround.new()
	ground.step = 1.0
	ground.step_at = -5.0
	var body := _start(ground, 0.0)
	body.speed = 20.0
	var flew := false
	var landed_again := false
	for i in range(240):
		body = _tick(body, _controls(1.0), ground)
		if body.airborne:
			flew = true
		elif flew:
			landed_again = true
			break
	var height := ground.ground_altitude(body.transform.origin)
	# Leaning over the edge first, it loses a little speed into the drop.
	if not flew or not landed_again or absf(height) > 1e-6 or body.speed < 17.0:
		print("FAIL _test_drop_flies_then_lands: flew %s, landed again %s, %.3f m over the ground, %.2f m/s" % [flew, landed_again, height, body.speed])
		return 1
	return 0

func _test_handbrake_holds_on_a_20_degree_ramp() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(20.0)
	var body := _start(ground, -10.0)
	var start: Vector3 = body.transform.origin
	for i in range(180):
		body = _tick(body, _controls(0.0, 0.0, true), ground)
	if body.transform.origin.distance_to(start) > 0.01:
		print("FAIL _test_handbrake_holds_on_a_20_degree_ramp: moved %.3f m" % body.transform.origin.distance_to(start))
		return 1
	return 0

# Over the top of a 34-degree ramp at full speed: a small hop under a
# second, not a flight (the climb's 11 m/s straight up would send it 40 m
# high for 14 s).
func _test_crest_makes_a_small_jump() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(34.0)
	ground.crest_at = -20.0
	var body := _start(ground, -5.0)
	body.speed = 20.0
	var launch := 0.0
	var air_ticks := 0
	for i in range(600):
		body = _tick(body, _controls(1.0), ground)
		if body.airborne:
			if air_ticks == 0:
				launch = body.vertical
			air_ticks += 1
		elif air_ticks > 0:
			break
	if air_ticks == 0 or launch > GroundVehicle.MAX_LAUNCH + 1e-6 or air_ticks > 60:
		print("FAIL _test_crest_makes_a_small_jump: off at %.2f m/s up, %.2f s in the air" % [launch, air_ticks / 60.0])
		return 1
	return 0
