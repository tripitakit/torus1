extends SceneTree

const DockingAssist = preload("res://scripts/docking_assist.gd")
const ApproachGuide = preload("res://scripts/approach_guide.gd")

# The real bridge, in its own frame (see test_approach_guide.gd), turning
# like the real one.
const SECTION_RADIUS := 2000.0
const HALF_GAP := 917.0
const BRIDGE_RADIUS := 600.0
const SPIN := 0.0586
var PAD_ANGLE := 15.5 * TAU / 64.0
var PAD_RADIUS := BRIDGE_RADIUS * cos(PI / 64.0) + 0.3

func _init():
	var failures := 0
	failures += _test_precision_eases_off_near_a_dock()
	failures += _test_thrust_ramps_far_and_scales_near()
	failures += _test_brake_is_limited_per_tick()
	failures += _test_brake_turns_with_the_bridge_only_near_a_dock()
	failures += _test_arrival_time_brakes_steadily()
	failures += _test_plan_holds_between_early_and_late()
	failures += _test_plan_waits_for_the_pad_to_come_round()
	failures += _test_advised_speed_arrives_on_time()
	failures += _test_future_pad_turns_with_the_bridge()
	failures += _test_speed_rating()
	failures += _test_time_format()
	failures += _test_readout_lines_and_status()
	failures += _test_advised_speed_capped_in_docking_range()
	failures += _test_plan_dropped_when_the_way_grows()
	failures += _test_planned_arrival_keeps_the_path_still()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_precision_eases_off_near_a_dock() -> int:
	var result := 0
	# [distance, factor]: 1x from 2 km out, 0.1x from 200 m in, straight between.
	for c in [[20000.0, 1.0], [2000.0, 1.0], [1100.0, 0.55], [200.0, 0.1], [50.0, 0.1], [0.0, 0.1]]:
		if not is_equal_approx(DockingAssist.precision_factor(c[0]), c[1]):
			print("FAIL _test_precision_eases_off_near_a_dock: %.0f m gave %f, expected %f" % [c[0], DockingAssist.precision_factor(c[0]), c[1]])
			result = 1
	return result

func _test_thrust_ramps_far_and_scales_near() -> int:
	var result := 0
	var input := Vector3(1.0, -1.0, -1.0)
	# Far: only forward thrust takes the ramp.
	if not DockingAssist.scaled_thrust(input, 10.0, 1.0).is_equal_approx(Vector3(1.0, -1.0, -10.0)):
		print("FAIL _test_thrust_ramps_far_and_scales_near: far thrust %s" % DockingAssist.scaled_thrust(input, 10.0, 1.0))
		result = 1
	# Near: every axis scaled, no ramp.
	if not DockingAssist.scaled_thrust(input, 10.0, 0.4).is_equal_approx(input * 0.4):
		print("FAIL _test_thrust_ramps_far_and_scales_near: near thrust %s" % DockingAssist.scaled_thrust(input, 10.0, 0.4))
		result = 1
	return result

func _test_brake_is_limited_per_tick() -> int:
	var result := 0
	var target := Vector3(0.0, 35.0, 0.0)
	# 1000 m/s off at 500 m/s^2: 5 m/s off after a hundredth of a second...
	var braked := DockingAssist.brake_velocity(Vector3(1000.0, 35.0, 0.0), target, 500.0, 0.01)
	if not braked.is_equal_approx(Vector3(995.0, 35.0, 0.0)):
		print("FAIL _test_brake_is_limited_per_tick: one tick gave %s" % braked)
		result = 1
	# ...and exactly on target once within reach, not past it.
	braked = DockingAssist.brake_velocity(Vector3(3.0, 35.0, 0.0), target, 500.0, 0.01)
	if not braked.is_equal_approx(target):
		print("FAIL _test_brake_is_limited_per_tick: the last tick gave %s" % braked)
		result = 1
	return result

func _test_arrival_time_brakes_steadily() -> int:
	# Braking at 1 m/s^2 over 20 km takes 200 s (from 200 m/s).
	if not is_equal_approx(DockingAssist.arrival_time(20000.0), 200.0) or not is_equal_approx(DockingAssist.arrival_time(0.0), 0.0):
		print("FAIL _test_arrival_time_brakes_steadily: 20 km in %f s" % DockingAssist.arrival_time(20000.0))
		return 1
	return 0

func _test_plan_holds_between_early_and_late() -> int:
	var result := 0
	# 20 km takes 200 s braking steadily: with the bridge still, plans from
	# 60 s to 600 s hold; turning, a turn's wait (107 s) more is fine too.
	for c in [[200.0, 0.0, true], [61.0, 0.0, true], [59.0, 0.0, false], [599.0, 0.0, true], [601.0, 0.0, false], [-5.0, 0.0, false], [650.0, SPIN, true], [710.0, SPIN, false]]:
		if DockingAssist.keeps_plan(c[0], 20000.0, c[1], 20000.0) != c[2]:
			print("FAIL _test_plan_holds_between_early_and_late: %.0f s left for 20 km at spin %.4f, expected %s" % [c[0], c[1], c[2]])
			result = 1
	return result

func _test_plan_waits_for_the_pad_to_come_round() -> int:
	var result := 0
	var pad := Vector3(0.0, 0.0, 600.0)
	# 50 m to go brakes in 10 s. [ship's angle about the axis, spin, planned time]
	for c in [[2.0, 0.1, 20.0], [0.0, 0.1, 10.0 + (TAU - 1.0) / 0.1], [2.0, 0.0, 10.0]]:
		var ship := Vector3(sin(c[0]), 0.0, cos(c[0])) * 3000.0
		var planned: float = DockingAssist.plan_arrival(ship, pad, c[1], 50.0)
		if not is_equal_approx(planned, c[2]):
			print("FAIL _test_plan_waits_for_the_pad_to_come_round: ship at %.1f rad, spin %.1f: %f s, expected %f" % [c[0], c[1], planned, c[2]])
			result = 1
		elif c[1] > 0.0:
			var met := DockingAssist.future_pad(pad, c[1], planned)
			if absf(wrapf(atan2(met.x, met.z) - c[0], -PI, PI)) > 1e-6:
				print("FAIL _test_plan_waits_for_the_pad_to_come_round: the pad is not below the ship then")
				result = 1
	return result

func _test_advised_speed_arrives_on_time() -> int:
	var result := 0
	# 20 km in 200 s braking steadily: start at 200 m/s.
	if not is_equal_approx(DockingAssist.advised_speed(20000.0, 200.0), 200.0):
		print("FAIL _test_advised_speed_arrives_on_time: %f m/s" % DockingAssist.advised_speed(20000.0, 200.0))
		result = 1
	# Late on the plan: faster. Time up: nothing sensible, so 0.
	if not is_equal_approx(DockingAssist.advised_speed(20000.0, 100.0), 400.0) or DockingAssist.advised_speed(500.0, 0.0) != 0.0:
		print("FAIL _test_advised_speed_arrives_on_time: late %f, time up %f" % [DockingAssist.advised_speed(20000.0, 100.0), DockingAssist.advised_speed(500.0, 0.0)])
		result = 1
	return result

func _test_future_pad_turns_with_the_bridge() -> int:
	var pad := Vector3(0.0, 0.0, 600.0)
	var later := DockingAssist.future_pad(pad, 0.5, PI)
	# Half a radian a second for pi seconds: a quarter turn about +Y.
	if not later.is_equal_approx(pad.rotated(Vector3.UP, PI * 0.5)):
		print("FAIL _test_future_pad_turns_with_the_bridge: got %s" % later)
		return 1
	return 0

func _test_speed_rating() -> int:
	var result := 0
	for c in [[40.0, 50.0, DockingAssist.Rating.OK], [50.0, 50.0, DockingAssist.Rating.OK], [62.0, 50.0, DockingAssist.Rating.CAUTION], [63.0, 50.0, DockingAssist.Rating.OVER]]:
		if DockingAssist.speed_rating(c[0], c[1]) != c[2]:
			print("FAIL _test_speed_rating: %.0f against %.0f advised gave %d" % [c[0], c[1], DockingAssist.speed_rating(c[0], c[1])])
			result = 1
	return result

func _test_time_format() -> int:
	var result := 0
	for c in [[42.4, "42 s"], [59.4, "59 s"], [185.0, "3:05"], [-1.0, "—"]]:
		if DockingAssist.format_time(c[0]) != c[1]:
			print("FAIL _test_time_format: %f gave '%s', expected '%s'" % [c[0], DockingAssist.format_time(c[0]), c[1]])
			result = 1
	return result

func _test_readout_lines_and_status() -> int:
	var result := 0
	# 1.2 km to go, 40 s left: advised 60 m/s; 70 m/s is a caution.
	var far: Dictionary = DockingAssist.readout(1200.0, 40.0, 70.0, 60.0, 900.0)
	if far.dist != "DIST  1.2 km" or far.speed != "REL SPEED  70 m/s" or far.advised != "ADVISED  60 m/s" or far.eta != "ETA  20 s" or far.status != "" or far.rating != DockingAssist.Rating.CAUTION or far.ready:
		print("FAIL _test_readout_lines_and_status: far %s" % far)
		result = 1
	# Moving away: no time of arrival.
	if DockingAssist.readout(1200.0, 40.0, 5.0, -5.0, 900.0).eta != "ETA  —":
		print("FAIL _test_readout_lines_and_status: an ETA while moving away")
		result = 1
	# In range: ready when slow enough, too fast otherwise.
	var slow: Dictionary = DockingAssist.readout(120.0, 10.0, 12.0, 12.0, 120.0)
	var fast: Dictionary = DockingAssist.readout(120.0, 10.0, 25.0, 25.0, 120.0)
	if slow.status != DockingAssist.READY_TEXT or not slow.ready or fast.status != DockingAssist.TOO_FAST_TEXT or fast.ready:
		print("FAIL _test_readout_lines_and_status: in range slow %s, fast %s" % [slow.status, fast.status])
		result = 1
	return result

# How far the points of `now` (past its first tenth) lie from the polyline
# `before`, at most.
func _drift(before: PackedVector3Array, now: PackedVector3Array) -> float:
	var worst := 0.0
	for i in range(int(now.size() * 0.1), now.size(), 8):
		var best := INF
		for j in range(1, before.size()):
			best = minf(best, Geometry3D.get_closest_point_to_segment(now[i], before[j - 1], before[j]).distance_to(now[i]))
		worst = maxf(worst, best)
	return worst

# A pilot flying the path at the advised speed, nose on the path 500 m ahead,
# with the bridge turning: the mean speed (m/s) at which the path itself
# moves in space, aiming at the pad as it is (`plan` false) or where it will
# be at the planned arrival.
func _path_drift(plan: bool) -> float:
	var pad := Vector3(sin(PAD_ANGLE), 0.0, cos(PAD_ANGLE)) * PAD_RADIUS
	var ship := Vector3(sin(PAD_ANGLE + 1.0), 0.0, cos(PAD_ANGLE + 1.0)) * 8000.0 + Vector3(0.0, 2000.0, 0.0)
	var nose := (pad - ship).normalized()
	var length := ship.distance_to(pad)
	var arrive := -1.0
	var planned := 0.0
	var over := false
	var before := PackedVector3Array()
	var total := 0.0
	var steps := 0
	var dt := 1.0
	for s in range(200):
		var t := s * dt
		var turn := -SPIN * t
		var ship_here := ship.rotated(Vector3.UP, turn)
		var nose_here := nose.rotated(Vector3.UP, turn)
		if arrive < 0.0 or not DockingAssist.keeps_plan(arrive - t, length, SPIN, planned):
			arrive = t + DockingAssist.plan_arrival(ship_here, pad, SPIN, length)
			planned = length
		var target := DockingAssist.future_pad(pad, SPIN, arrive - t) if plan else pad
		over = ApproachGuide.over_rim(ship_here, nose_here, target, SECTION_RADIUS, HALF_GAP, over)
		var path := PackedVector3Array()
		for p in ApproachGuide.approach_path(ship_here, nose_here, target, SECTION_RADIUS, HALF_GAP, BRIDGE_RADIUS, over):
			path.append(p.rotated(Vector3.UP, -turn))
		length = 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length < 300.0:
			break
		if not before.is_empty():
			total += _drift(before, path) / dt
			steps += 1
		before = path
		var walked := 0.0
		var k := 1
		while k < path.size() - 1 and walked < 500.0:
			walked += path[k - 1].distance_to(path[k])
			k += 1
		nose = (path[k] - path[0]).normalized()
		ship += nose * DockingAssist.advised_speed(length, arrive - t) * dt
	return total / maxi(steps, 1)

func _test_planned_arrival_keeps_the_path_still() -> int:
	# Aimed at the pad as it is, the path swings round with the bridge;
	# aimed at the planned meeting point it barely moves.
	var still := _path_drift(true)
	var swinging := _path_drift(false)
	if still > 15.0 or still * 5.0 > swinging:
		print("FAIL _test_planned_arrival_keeps_the_path_still: path moves %.0f m/s planned, %.0f m/s unplanned" % [still, swinging])
		return 1
	return 0

func _test_brake_turns_with_the_bridge_only_near_a_dock() -> int:
	# Within 2 km the brake holds the ship turning with the bridge, so it
	# stays over the same spot of it; farther out it stops in space and the
	# pad comes round to the planned meeting point.
	var carried := Vector3(10.0, 0.0, -40.0)
	var result := 0
	for c in [[150.0, carried], [1999.0, carried], [2000.0, Vector3.ZERO], [15000.0, Vector3.ZERO]]:
		if DockingAssist.brake_target(c[0], carried) != c[1]:
			print("FAIL _test_brake_turns_with_the_bridge_only_near_a_dock: at %.0f m got %s" % [c[0], DockingAssist.brake_target(c[0], carried)])
			result = 1
	return result

func _test_advised_speed_capped_in_docking_range() -> int:
	# 120 m out with 8 s left would advise 30 m/s: above the 20 m/s docking
	# limit, so 25 m/s would read green while the status says too fast.
	var near: Dictionary = DockingAssist.readout(120.0, 8.0, 25.0, 25.0, 120.0)
	if near.advised != "ADVISED  20 m/s" or near.rating != DockingAssist.Rating.OVER or near.status != DockingAssist.TOO_FAST_TEXT:
		print("FAIL _test_advised_speed_capped_in_docking_range: %s, rating %d, status %s" % [near.advised, near.rating, near.status])
		return 1
	return 0

func _test_plan_dropped_when_the_way_grows() -> int:
	# Planned for 10 km; the ship has since gone round the bridge and the way
	# is 20 km: the old meeting point is stale.
	if DockingAssist.keeps_plan(200.0, 20000.0, 0.0, 10000.0) or not DockingAssist.keeps_plan(200.0, 14000.0, 0.0, 10000.0):
		print("FAIL _test_plan_dropped_when_the_way_grows: 2x the planned way kept, or 1.4x dropped")
		return 1
	return 0
