extends SceneTree

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

func _init():
	var failures := 0
	failures += _test_format_speed_rounds_to_whole_metres_per_second()
	failures += _test_format_speed_zero()
	failures += _test_format_distance_negative_means_no_reading()
	failures += _test_format_distance_below_a_kilometre_in_metres()
	failures += _test_format_distance_zero_metres()
	failures += _test_format_distance_rounds_up_into_kilometres()
	failures += _test_format_distance_kilometres_one_decimal()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _check(test_name: String, actual: String, expected: String) -> int:
	if actual != expected:
		print("FAIL %s: got '%s' expected '%s'" % [test_name, actual, expected])
		return 1
	return 0

func _test_format_speed_rounds_to_whole_metres_per_second() -> int:
	return _check("_test_format_speed_rounds_to_whole_metres_per_second", CockpitHudFormat.format_speed(1240.4), "1240 m/s")

func _test_format_speed_zero() -> int:
	return _check("_test_format_speed_zero", CockpitHudFormat.format_speed(0.0), "0 m/s")

func _test_format_distance_negative_means_no_reading() -> int:
	return _check("_test_format_distance_negative_means_no_reading", CockpitHudFormat.format_distance(-1.0), "—")

func _test_format_distance_below_a_kilometre_in_metres() -> int:
	return _check("_test_format_distance_below_a_kilometre_in_metres", CockpitHudFormat.format_distance(819.6), "820 m")

func _test_format_distance_zero_metres() -> int:
	return _check("_test_format_distance_zero_metres", CockpitHudFormat.format_distance(0.0), "0 m")

func _test_format_distance_rounds_up_into_kilometres() -> int:
	# 999.6 m rounds to 1000 m: must switch to km, never print "1000 m".
	var failures := 0
	failures += _check("_test_format_distance_rounds_up_into_kilometres(999.4)", CockpitHudFormat.format_distance(999.4), "999 m")
	failures += _check("_test_format_distance_rounds_up_into_kilometres(999.6)", CockpitHudFormat.format_distance(999.6), "1.0 km")
	failures += _check("_test_format_distance_rounds_up_into_kilometres(1000)", CockpitHudFormat.format_distance(1000.0), "1.0 km")
	return 1 if failures > 0 else 0

func _test_format_distance_kilometres_one_decimal() -> int:
	return _check("_test_format_distance_kilometres_one_decimal", CockpitHudFormat.format_distance(3140.0), "3.1 km")
