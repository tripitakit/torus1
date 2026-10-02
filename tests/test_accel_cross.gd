extends SceneTree

# The acceleration cross: the ship's own share, the outside pulls and the
# net, along the ship's axes, on a log scale; values in m/s2 and g.

const AccelCross = preload("res://scripts/accel_cross.gd")

func _init():
	var failures := 0
	failures += _test_log_scale()
	failures += _test_values()
	failures += _test_node()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_log_scale() -> int:
	# Nothing under MIN, full at TOP; the moon's 0.98 m/s2 and the brake's
	# 1500 m/s2 both clearly visible and clearly apart.
	var none := AccelCross.reach(Vector3(0.0, 0.005, 0.0))
	var full := AccelCross.reach(Vector3(0.0, 0.0, AccelCross.TOP))
	var moon := AccelCross.reach(Vector3(0.0, -0.98, 0.0))
	var brake := AccelCross.reach(Vector3(0.0, 0.0, -1500.0))
	if not none.is_zero_approx() or absf(full.z - 1.0) > 0.001 or moon.y > -0.25 or brake.z > -0.7 or absf(moon.y) > absf(brake.z) - 0.2:
		print("FAIL _test_log_scale: none %s full %s moon %s brake %s" % [none, full, moon, brake])
		return 1
	return 0

func _test_values() -> int:
	if AccelCross.format_accel(1500.0) != "1500 m/s² 153 g" or AccelCross.format_accel(0.976) != "0.98 m/s² 0.10 g" or AccelCross.format_accel(12.34) != "12.3 m/s² 1.26 g":
		print("FAIL _test_values: %s / %s / %s" % [AccelCross.format_accel(1500.0), AccelCross.format_accel(0.976), AccelCross.format_accel(12.34)])
		return 1
	var rows := AccelCross.readout(Vector3(0.0, 0.0, 1500.0), Vector3(0.0, -0.98, 0.0), Vector3(0.0, -0.98, 1500.0))
	if rows != ["THR 1500 m/s² 153 g", "EXT 0.98 m/s² 0.10 g", "NET 1500 m/s² 153 g"]:
		print("FAIL _test_values: %s" % [rows])
		return 1
	return 0

func _test_node() -> int:
	var cross: Control = AccelCross.new()
	cross.set_accelerations(Vector3(1.0, 2.0, 3.0), Vector3(0.0, -1.0, 0.0), Vector3(1.0, 1.0, 3.0))
	var result := 0
	if cross.size != AccelCross.PANEL_SIZE or cross.mouse_filter != Control.MOUSE_FILTER_IGNORE or cross.vectors.size() != 3:
		print("FAIL _test_node: size %s" % cross.size)
		result = 1
	cross.free()
	return result
