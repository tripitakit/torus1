extends SceneTree

const CockpitLayout = preload("res://scripts/cockpit_layout.gd")

const CENTER_WIDTH := 1.6
const SIDE_WIDTH := 0.9
const SCREEN_DISTANCE := 1.6
const TILT := 30.0

func _init():
	var failures := 0
	failures += _test_left_screen_inner_edge_touches_center_screen_left_edge()
	failures += _test_right_screen_inner_edge_touches_center_screen_right_edge()
	failures += _test_side_screens_face_the_pilot()
	failures += _test_side_screens_are_tilted_toward_the_center_by_tilt_angle()
	failures += _test_left_camera_yaws_left_by_one_fov()
	failures += _test_right_camera_yaws_right_by_one_fov()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_left_screen_inner_edge_touches_center_screen_left_edge() -> int:
	var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, -1.0)
	# The left screen's inner edge is its local +X edge.
	var inner_edge: Vector3 = t * Vector3(SIDE_WIDTH * 0.5, 0.0, 0.0)
	var center_left_edge := Vector3(-CENTER_WIDTH * 0.5, 0.0, -SCREEN_DISTANCE)
	if not inner_edge.is_equal_approx(center_left_edge):
		print("FAIL _test_left_screen_inner_edge_touches_center_screen_left_edge: inner_edge=%s expected=%s" % [inner_edge, center_left_edge])
		return 1
	return 0

func _test_right_screen_inner_edge_touches_center_screen_right_edge() -> int:
	var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, 1.0)
	# The right screen's inner edge is its local -X edge.
	var inner_edge: Vector3 = t * Vector3(-SIDE_WIDTH * 0.5, 0.0, 0.0)
	var center_right_edge := Vector3(CENTER_WIDTH * 0.5, 0.0, -SCREEN_DISTANCE)
	if not inner_edge.is_equal_approx(center_right_edge):
		print("FAIL _test_right_screen_inner_edge_touches_center_screen_right_edge: inner_edge=%s expected=%s" % [inner_edge, center_right_edge])
		return 1
	return 0

func _test_side_screens_face_the_pilot() -> int:
	var result := 0
	for side in [-1.0, 1.0]:
		var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, side)
		# A QuadMesh shows its front face along local +Z; the eye is at the origin.
		var to_eye: Vector3 = Vector3.ZERO - t.origin
		if t.basis.z.dot(to_eye) <= 0.0:
			print("FAIL _test_side_screens_face_the_pilot: side=%s normal=%s to_eye=%s" % [side, t.basis.z, to_eye])
			result = 1
	return result

func _test_side_screens_are_tilted_toward_the_center_by_tilt_angle() -> int:
	var result := 0
	for side in [-1.0, 1.0]:
		var t: Transform3D = CockpitLayout.compute_side_screen_transform(CENTER_WIDTH, SIDE_WIDTH, SCREEN_DISTANCE, TILT, side)
		var angle: float = rad_to_deg(t.basis.z.angle_to(Vector3(0.0, 0.0, 1.0)))
		if not is_equal_approx(angle, TILT):
			print("FAIL _test_side_screens_are_tilted_toward_the_center_by_tilt_angle: side=%s angle=%f expected=%f" % [side, angle, TILT])
			result = 1
		# Turned toward the center: the left screen's normal points to +X, the right one's to -X.
		if sign(t.basis.z.x) != -side:
			print("FAIL _test_side_screens_are_tilted_toward_the_center_by_tilt_angle: side=%s normal=%s turned away from the center" % [side, t.basis.z])
			result = 1
	return result

func _test_left_camera_yaws_left_by_one_fov() -> int:
	var yaw: float = CockpitLayout.compute_side_camera_yaw_degrees(60.0, -1.0)
	var result := 0
	if not is_equal_approx(yaw, 60.0):
		print("FAIL _test_left_camera_yaws_left_by_one_fov: yaw=%f expected=60.0" % yaw)
		result = 1
	var looks: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.0, 0.0, -1.0)
	if looks.x >= 0.0:
		print("FAIL _test_left_camera_yaws_left_by_one_fov: camera looks toward %s, expected negative X (left)" % looks)
		result = 1
	return result

func _test_right_camera_yaws_right_by_one_fov() -> int:
	var yaw: float = CockpitLayout.compute_side_camera_yaw_degrees(60.0, 1.0)
	var result := 0
	if not is_equal_approx(yaw, -60.0):
		print("FAIL _test_right_camera_yaws_right_by_one_fov: yaw=%f expected=-60.0" % yaw)
		result = 1
	var looks: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.0, 0.0, -1.0)
	if looks.x <= 0.0:
		print("FAIL _test_right_camera_yaws_right_by_one_fov: camera looks toward %s, expected positive X (right)" % looks)
		result = 1
	return result
