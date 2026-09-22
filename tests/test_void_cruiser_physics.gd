extends SceneTree

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

func _init():
	var failures := 0
	failures += _test_pure_thrust_no_damping()
	failures += _test_pure_damping_no_thrust()
	failures += _test_zero_damping_is_pure_newtonian()
	failures += _test_high_damping_no_overshoot()
	failures += _test_large_delta_stays_finite()
	failures += _test_thrust_applied_in_world_space_via_orientation()
	failures += _test_angular_pure_torque_no_damping()
	failures += _test_angular_pure_damping_no_torque()
	failures += _test_angular_large_delta_stays_finite()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_pure_thrust_no_damping() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_velocity(Vector3.ZERO, Vector3(0, 0, -1), Basis.IDENTITY, 50.0, 0.0, 0.1)
	var expected := Vector3(0, 0, -5.0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_pure_thrust_no_damping: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_pure_damping_no_thrust() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_velocity(Vector3(10, 0, 0), Vector3.ZERO, Basis.IDENTITY, 999.0, 0.5, 1.0)
	var expected := Vector3(5.0, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_pure_damping_no_thrust: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_zero_damping_is_pure_newtonian() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_velocity(Vector3(3, 4, 5), Vector3.ZERO, Basis.IDENTITY, 0.0, 0.0, 2.0)
	var expected := Vector3(3, 4, 5)
	if not result.is_equal_approx(expected):
		print("FAIL _test_zero_damping_is_pure_newtonian: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_high_damping_no_overshoot() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_velocity(Vector3(10, 0, 0), Vector3.ZERO, Basis.IDENTITY, 0.0, 0.99, 1.0)
	if result.x <= 0.0 or result.x >= 10.0:
		print("FAIL _test_high_damping_no_overshoot: result.x=%f expected in (0, 10)" % result.x)
		return 1
	return 0

func _test_large_delta_stays_finite() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_velocity(Vector3(5, 0, 0), Vector3(1, 0, 0), Basis.IDENTITY, 10.0, 0.3, 1000.0)
	if is_nan(result.x) or is_inf(result.x) or is_nan(result.y) or is_inf(result.y) or is_nan(result.z) or is_inf(result.z):
		print("FAIL _test_large_delta_stays_finite: result=%s" % result)
		return 1
	return 0

func _test_thrust_applied_in_world_space_via_orientation() -> int:
	# 90 deg yaw around Y: forward (0,0,-1) rotates to (-1,0,0) by the standard
	# right-handed Y-rotation matrix (independent of the function under test):
	# x' = x*cos(t) + z*sin(t); z' = -x*sin(t) + z*cos(t); t=PI/2 -> x'=z=-1, z'=-x=0.
	var orientation := Basis(Vector3.UP, PI / 2.0)
	var result: Vector3 = VoidCruiserPhysics.compute_new_velocity(Vector3.ZERO, Vector3(0, 0, -1), orientation, 1.0, 0.0, 1.0)
	var expected := Vector3(-1, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_thrust_applied_in_world_space_via_orientation: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_angular_pure_torque_no_damping() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_angular_velocity(Vector3.ZERO, Vector3(1, 0, 0), 2.0, 0.0, 0.5)
	var expected := Vector3(1.0, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_angular_pure_torque_no_damping: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_angular_pure_damping_no_torque() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_angular_velocity(Vector3(2, 0, 0), Vector3.ZERO, 999.0, 0.5, 1.0)
	var expected := Vector3(1.0, 0, 0)
	if not result.is_equal_approx(expected):
		print("FAIL _test_angular_pure_damping_no_torque: result=%s expected=%s" % [result, expected])
		return 1
	return 0

func _test_angular_large_delta_stays_finite() -> int:
	var result: Vector3 = VoidCruiserPhysics.compute_new_angular_velocity(Vector3(5, 0, 0), Vector3(1, 0, 0), 10.0, 0.3, 1000.0)
	if is_nan(result.x) or is_inf(result.x):
		print("FAIL _test_angular_large_delta_stays_finite: result=%s" % result)
		return 1
	return 0
