extends SceneTree

# The flight computer: the NAV panel's numbers, the arrival guidance and the
# route's leg. Pure math.

const FlightComputer = preload("res://scripts/flight_computer.gd")

const BRAKE := 1500.0
const DELTA := 1.0 / 60.0

func _init():
	var failures := 0
	failures += _test_stop_and_brake_in()
	failures += _test_brake_now_and_no_eta_going_away()
	failures += _test_arrives_from_rest_without_overshoot()
	failures += _test_arrives_moving_sideways()
	failures += _test_arrives_coming_in_fast()
	failures += _test_arrives_on_a_moving_point()
	failures += _test_command_never_exceeds_the_brake()
	failures += _test_route_legs()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_stop_and_brake_in() -> int:
	# 300 m/s toward a point 100 km away, braking at 1500 m/s2: stops in
	# 30 m; brake in (100000 - 30) / 300 s; there in 333 s at this speed.
	var r := FlightComputer.readout(100000.0, 300.0, BRAKE)
	if absf(r.stop - 30.0) > 0.01 or absf(r.brake_in - (100000.0 - 30.0) / 300.0) > 0.01 or absf(r.eta - 100000.0 / 300.0) > 0.01 or r.brake_now:
		print("FAIL _test_stop_and_brake_in: %s" % r)
		return 1
	var lines := FlightComputer.lines("SELENE", "GATE TERRA", r, FlightComputer.Auto.OFF)
	if lines.nav != "NAV  SELENE via GATE TERRA" or lines.dist != "DIST  100.0 km" or lines.closing != "CLOSING  300 m/s" or lines.eta != "ETA  5:33" or lines.stop != "STOP  30 m" or lines.brake != "BRAKE IN  5:33" or lines.auto != "":
		print("FAIL _test_stop_and_brake_in: lines %s" % lines)
		return 1
	return 0

func _test_brake_now_and_no_eta_going_away() -> int:
	# 3000 m/s with 2 km to go: 3 km to stop, brake now (red).
	var fast := FlightComputer.readout(2000.0, 3000.0, BRAKE)
	var away := FlightComputer.readout(2000.0, -50.0, BRAKE)
	var fast_lines := FlightComputer.lines("DOCK", "DOCK", fast, FlightComputer.Auto.ARRIVING)
	var away_lines := FlightComputer.lines("DOCK", "DOCK", away, FlightComputer.Auto.ARRIVED)
	if not fast.brake_now or fast_lines.brake != "BRAKE NOW" or fast_lines.colors.brake != FlightComputer.BAD or fast_lines.nav != "NAV  DOCK" or fast_lines.auto != "AUTO  ARRIVING":
		print("FAIL _test_brake_now_and_no_eta_going_away: fast %s" % fast_lines)
		return 1
	if away.brake_now or away_lines.eta != "ETA  —" or away_lines.brake != "BRAKE IN  —" or away_lines.auto != "ARRIVED":
		print("FAIL _test_brake_now_and_no_eta_going_away: away %s" % away_lines)
		return 1
	return 0

# Flies the guidance from `offset` (target minus ship) at `velocity`, the
# target moving at `target_velocity`, up to `seconds`: {arrived, time,
# overshoot (how far past the point it went, along the first line), top}.
func _fly(offset: Vector3, velocity: Vector3, target_velocity: Vector3, limit: float, seconds: float) -> Dictionary:
	var ship := Vector3.ZERO
	var target := offset
	var line := offset.normalized()
	var overshoot := 0.0
	var top := 0.0
	var t := 0.0
	while t < seconds:
		var rel := target - ship
		if FlightComputer.arrived(rel, velocity - target_velocity):
			return {"arrived": true, "time": t, "overshoot": overshoot, "top": top}
		var accel := FlightComputer.command(rel, velocity, target_velocity, limit, BRAKE)
		velocity += accel * DELTA
		ship += velocity * DELTA
		target += target_velocity * DELTA
		overshoot = maxf(overshoot, -(target - ship).dot(line))
		top = maxf(top, (velocity - target_velocity).length())
		t += DELTA
	return {"arrived": false, "time": t, "overshoot": overshoot, "top": top}

func _test_arrives_from_rest_without_overshoot() -> int:
	var run := _fly(Vector3(120000.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO, 3000.0, 300.0)
	if not run.arrived or run.overshoot > 5.0 or run.top > 3000.0:
		print("FAIL _test_arrives_from_rest_without_overshoot: %s" % run)
		return 1
	return 0

func _test_arrives_moving_sideways() -> int:
	var run := _fly(Vector3(0.0, 0.0, -20000.0), Vector3(400.0, 0.0, 0.0), Vector3.ZERO, 500.0, 300.0)
	if not run.arrived or run.overshoot > 5.0:
		print("FAIL _test_arrives_moving_sideways: %s" % run)
		return 1
	return 0

func _test_arrives_coming_in_fast() -> int:
	# 500 m/s straight at a point 1 km off: brakes hard, may not stop short,
	# but comes back and settles.
	var run := _fly(Vector3(1000.0, 0.0, 0.0), Vector3(500.0, 0.0, 0.0), Vector3.ZERO, 500.0, 120.0)
	if not run.arrived:
		print("FAIL _test_arrives_coming_in_fast: %s" % run)
		return 1
	return 0

func _test_arrives_on_a_moving_point() -> int:
	# A point drifting at 1900 m/s (the moon seen from the ring), 200 km off.
	var run := _fly(Vector3(0.0, 0.0, 200000.0), Vector3.ZERO, Vector3(1900.0, 0.0, 0.0), 3000.0, 600.0)
	if not run.arrived:
		print("FAIL _test_arrives_on_a_moving_point: %s" % run)
		return 1
	return 0

func _test_command_never_exceeds_the_brake() -> int:
	var a := FlightComputer.command(Vector3(1.0e6, 0.0, 0.0), Vector3(-3000.0, 2000.0, 0.0), Vector3.ZERO, 3000.0, BRAKE)
	if a.length() > BRAKE + 0.001:
		print("FAIL _test_command_never_exceeds_the_brake: %.1f" % a.length())
		return 1
	return 0

func _test_route_legs() -> int:
	# Target on the moon's side and the ship not: GATE TERRA first; the
	# other way round GATE LUNA; same side: the target itself.
	var cases := [
		["SELENE", false, "GATE TERRA"],
		["GATE LUNA", false, "GATE TERRA"],
		["SELENE", true, "SELENE"],
		["TELESCOPE", false, "GATE TERRA"],
		["AREA 2", true, "AREA 2"],
		["DOCK", true, "GATE LUNA"],
		["GATE TERRA", true, "GATE LUNA"],
		["DOCK", false, "DOCK"],
		["GATE TERRA", false, "GATE TERRA"],
	]
	for c in cases:
		var leg := FlightComputer.leg(c[0], c[1])
		if leg != c[2]:
			print("FAIL _test_route_legs: %s with the ship near the moon %s gave %s" % [c[0], c[1], leg])
			return 1
	if FlightComputer.TARGETS != ["DOCK", "GATE TERRA", "GATE LUNA", "SELENE", "TELESCOPE", "AREA 2"] or FlightComputer.next_target("") != "DOCK" or FlightComputer.next_target("AREA 2") != "" or FlightComputer.next_target("DOCK") != "GATE TERRA":
		print("FAIL _test_route_legs: the target list")
		return 1
	return 0
