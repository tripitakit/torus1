extends SceneTree

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

func _init():
	var failures := 0
	failures += _test_section_count()
	failures += _test_section_zero_theta()
	failures += _test_ring_closes()
	failures += _test_degenerate_num_sections()
	failures += _test_negative_bridge_length_does_not_crash()
	failures += _test_section_angular_velocity_gives_1g()
	failures += _test_section_angular_velocity_zero_radius_does_not_crash()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_section_count() -> int:
	var transforms = TorusGeometry.compute_section_transforms(500.0, 1500.0, 4)
	if transforms.size() != 4:
		print("FAIL _test_section_count: expected 4 transforms, got %d" % transforms.size())
		return 1
	return 0

func _test_section_zero_theta() -> int:
	# At theta=0: position=(torus_radius,0,0), tangent=(0,0,1),
	# basis.x=UP=(0,1,0), basis.y=tangent=(0,0,1), basis.z=UP.cross(tangent)=(1,0,0)
	var transforms = TorusGeometry.compute_section_transforms(500.0, 1500.0, 4)
	var t: Transform3D = transforms[0]
	var failed := false
	if not t.origin.is_equal_approx(Vector3(2000.0, 0.0, 0.0)):
		print("FAIL _test_section_zero_theta: origin=%s" % t.origin)
		failed = true
	if not t.basis.x.is_equal_approx(Vector3(0.0, 1.0, 0.0)):
		print("FAIL _test_section_zero_theta: basis.x=%s" % t.basis.x)
		failed = true
	if not t.basis.y.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		print("FAIL _test_section_zero_theta: basis.y=%s" % t.basis.y)
		failed = true
	if not t.basis.z.is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		print("FAIL _test_section_zero_theta: basis.z=%s" % t.basis.z)
		failed = true
	return 1 if failed else 0

func _test_ring_closes() -> int:
	# N sections must produce N bridges (last section connects back to the first).
	var bridges = TorusGeometry.compute_bridge_transforms(500.0, 1500.0, 100, 80.0)
	if bridges.size() != 100:
		print("FAIL _test_ring_closes: expected 100 bridges, got %d" % bridges.size())
		return 1
	return 0

func _test_degenerate_num_sections() -> int:
	var zero = TorusGeometry.compute_section_transforms(500.0, 1500.0, 0)
	var one = TorusGeometry.compute_section_transforms(500.0, 1500.0, 1)
	if zero.size() != 0:
		print("FAIL _test_degenerate_num_sections: num_sections=0 should give 0 transforms, got %d" % zero.size())
		return 1
	if one.size() != 1:
		print("FAIL _test_degenerate_num_sections: num_sections=1 should give 1 transform, got %d" % one.size())
		return 1
	return 0

func _test_negative_bridge_length_does_not_crash() -> int:
	# At num_sections=4, torus_radius=2000 -> step_arc_length = TAU*2000/4 ~= 3141.6.
	# section_length (5000) exceeds that -> negative bridge length.
	var length = TorusGeometry.compute_bridge_length(500.0, 1500.0, 4, 5000.0)
	if length >= 0.0:
		print("FAIL _test_negative_bridge_length_does_not_crash: expected a negative length, got %f" % length)
		return 1
	var bridges = TorusGeometry.compute_bridge_transforms(500.0, 1500.0, 4, 5000.0)
	if bridges.size() != 4:
		print("FAIL _test_negative_bridge_length_does_not_crash: expected 4 bridges even when overlapping, got %d" % bridges.size())
		return 1
	return 0

func _test_section_angular_velocity_gives_1g() -> int:
	# omega = sqrt(g / r); centripetal accel at radius r is omega^2 * r, which must equal g.
	var section_radius := 30.0
	var omega: float = TorusGeometry.compute_section_angular_velocity(section_radius)
	var resulting_accel: float = omega * omega * section_radius
	if not is_equal_approx(resulting_accel, TorusGeometry.GRAVITY_1G):
		print("FAIL _test_section_angular_velocity_gives_1g: resulting_accel=%f expected=%f" % [resulting_accel, TorusGeometry.GRAVITY_1G])
		return 1
	return 0

func _test_section_angular_velocity_zero_radius_does_not_crash() -> int:
	var omega: float = TorusGeometry.compute_section_angular_velocity(0.0)
	if omega != 0.0:
		print("FAIL _test_section_angular_velocity_zero_radius_does_not_crash: expected 0.0, got %f" % omega)
		return 1
	return 0
