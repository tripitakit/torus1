extends SceneTree

const DockingAssist = preload("res://scripts/docking_assist.gd")

func _init():
	var failures := 0
	failures += _test_precision_eases_off_near_a_dock()
	failures += _test_thrust_ramps_far_and_scales_near()
	failures += _test_brake_is_limited_per_tick()
	failures += _test_advised_speed_brakes_steadily()
	failures += _test_speed_rating()
	failures += _test_time_format()
	failures += _test_readout_lines_and_status()
	failures += _test_too_fast_to_dock_reads_red()
	failures += _test_ready_to_dock_reads_green()

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

func _test_advised_speed_brakes_steadily() -> int:
	# The speed from which braking at 1 m/s^2 stops on the pad.
	var result := 0
	for c in [[20000.0, 200.0], [1000.0, sqrt(2000.0)], [150.0, sqrt(300.0)], [0.0, 0.0]]:
		if not is_equal_approx(DockingAssist.advised_speed(c[0]), c[1]):
			print("FAIL _test_advised_speed_brakes_steadily: %.0f m gave %f, expected %f" % [c[0], DockingAssist.advised_speed(c[0]), c[1]])
			result = 1
	return result

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
	# 1.2 km to go: advised 49 m/s; 55 m/s is a caution; closing at 60 m/s,
	# 20 s to go.
	var far: Dictionary = DockingAssist.readout(1200.0, 55.0, 60.0, 900.0)
	if far.dist != "DIST  1.2 km" or far.speed != "REL SPEED  55 m/s" or far.advised != "ADVISED  49 m/s" or far.eta != "ETA  20 s" or far.status != "" or far.rating != DockingAssist.Rating.CAUTION or far.ready:
		print("FAIL _test_readout_lines_and_status: far %s" % far)
		result = 1
	# Moving away: no time of arrival.
	if DockingAssist.readout(1200.0, 5.0, -5.0, 900.0).eta != "ETA  —":
		print("FAIL _test_readout_lines_and_status: an ETA while moving away")
		result = 1
	# In range: ready when slow enough, too fast otherwise.
	var slow: Dictionary = DockingAssist.readout(120.0, 12.0, 12.0, 120.0)
	var fast: Dictionary = DockingAssist.readout(120.0, 25.0, 25.0, 120.0)
	if slow.status != DockingAssist.READY_TEXT or not slow.ready or fast.status != DockingAssist.TOO_FAST_TEXT or fast.ready:
		print("FAIL _test_readout_lines_and_status: in range slow %s, fast %s" % [slow.status, fast.status])
		result = 1
	return result

func _test_too_fast_to_dock_reads_red() -> int:
	# 120 m out: advised 15 m/s; 21 m/s is over the 20 m/s docking limit, so
	# it reads as too fast even though it is within the caution ratio, while
	# 18.5 m/s can dock and reads green.
	var near: Dictionary = DockingAssist.readout(120.0, 18.5, 18.5, 120.0)
	var over: Dictionary = DockingAssist.readout(120.0, 21.0, 21.0, 120.0)
	if near.rating != DockingAssist.Rating.OK or over.rating != DockingAssist.Rating.OVER or over.status != DockingAssist.TOO_FAST_TEXT:
		print("FAIL _test_too_fast_to_dock_reads_red: 18.5 m/s rated %d, 21 m/s rated %d (%s)" % [near.rating, over.rating, over.status])
		return 1
	return 0

func _test_ready_to_dock_reads_green() -> int:
	# Docking is a key press: slow enough and close enough is all that counts.
	# 30 m out at 10 m/s the advised speed is 8 m/s, but the panel says DOCK
	# READY, so the speed must not read red beside it.
	var result := 0
	for c in [[30.0, 10.0], [150.0, 18.0], [10.0, 5.0]]:
		var readout: Dictionary = DockingAssist.readout(c[0], c[1], c[1], c[0])
		if not readout.ready or readout.rating != DockingAssist.Rating.OK:
			print("FAIL _test_ready_to_dock_reads_green: %.0f m at %.0f m/s rated %d, ready %s" % [c[0], c[1], readout.rating, readout.ready])
			result = 1
	return result
