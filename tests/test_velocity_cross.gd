extends SceneTree

const VelocityCross = preload("res://scripts/velocity_cross.gd")

func _init():
	var failures := 0
	failures += _test_components_along_the_ship_axes()
	failures += _test_bars_are_logarithmic()
	failures += _test_set_velocity_keeps_values()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_components_along_the_ship_axes() -> int:
	var result := 0
	# Not turned: starboard = +x, dorsal = +y, forward = -z.
	var still: Vector3 = VelocityCross.ship_components(Basis(), Vector3(3.0, -4.0, -5.0))
	if not still.is_equal_approx(Vector3(3.0, -4.0, 5.0)):
		print("FAIL _test_components_along_the_ship_axes: %s, expected (3, -4, 5)" % still)
		result = 1
	# Yawed 90 degrees left: the ship's forward is world -x.
	var yawed: Vector3 = VelocityCross.ship_components(Basis(Vector3.UP, PI / 2.0), Vector3(-10.0, 0.0, 0.0))
	if not yawed.is_equal_approx(Vector3(0.0, 0.0, 10.0)):
		print("FAIL _test_components_along_the_ship_axes: yawed %s, expected (0, 0, 10)" % yawed)
		result = 1
	return result

func _test_bars_are_logarithmic() -> int:
	var result := 0
	if VelocityCross.bar_fraction(0.4) != 0.0 or VelocityCross.bar_fraction(-0.4) != 0.0:
		print("FAIL _test_bars_are_logarithmic: bars under 0.5 m/s")
		result = 1
	if not is_equal_approx(VelocityCross.bar_fraction(100000.0), 1.0) or not is_equal_approx(VelocityCross.bar_fraction(250000.0), 1.0):
		print("FAIL _test_bars_are_logarithmic: not full at 100 km/s and beyond")
		result = 1
	var docking: float = VelocityCross.bar_fraction(20.0)
	var ramp: float = VelocityCross.bar_fraction(45000.0)
	if not is_equal_approx(docking, log(21.0) / log(100001.0)) or not is_equal_approx(VelocityCross.bar_fraction(-20.0), docking) or ramp <= docking or ramp >= 1.0:
		print("FAIL _test_bars_are_logarithmic: 20 m/s -> %f, 45 km/s -> %f" % [docking, ramp])
		result = 1
	return result

func _test_set_velocity_keeps_values() -> int:
	var cross: Control = VelocityCross.new()
	var result := 0
	cross.set_velocity(Vector3(1.0, 2.0, 3.0), true)
	if not cross.components.is_equal_approx(Vector3(1.0, 2.0, 3.0)) or not cross.cruise or cross.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("FAIL _test_set_velocity_keeps_values: %s cruise %s mouse %d" % [cross.components, cross.cruise, cross.mouse_filter])
		result = 1
	cross.free()
	return result
