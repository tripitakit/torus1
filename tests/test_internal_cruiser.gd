extends SceneTree

const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

func _init():
	var failures := 0
	failures += _test_first_person_camera()
	failures += _test_hud_is_only_the_flight_markers()
	failures += _test_small_hull()
	failures += _test_ramp_stops_at_10x()
	failures += _test_top_speed_about_1_km_s_after_the_ramp()
	failures += _test_same_mouse_sensitivity_as_void_cruiser()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cruiser() -> Node3D:
	var cruiser: Node3D = InternalCruiserScript.new()
	cruiser.build_collision_shape()
	cruiser.build_camera()
	return cruiser

func _test_first_person_camera() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	var camera := cruiser.get_node_or_null("Camera") as Camera3D
	if camera == null or not camera.current or camera.keep_aspect != Camera3D.KEEP_WIDTH or not is_equal_approx(camera.fov, 90.0):
		print("FAIL _test_first_person_camera: need a current Camera with KEEP_WIDTH and fov 90")
		result = 1
	cruiser.free()
	return result

func _test_hud_is_only_the_flight_markers() -> int:
	# No cockpit panels inside: just the boresight and the motion marker.
	var cruiser := _make_cruiser()
	cruiser.build_hud()
	var result := 0
	var layers := cruiser.find_children("*", "CanvasLayer", true, false)
	var markers := cruiser.get_node_or_null("Hud/FlightMarkers") as Control
	if layers.size() != 1 or markers == null or cruiser.get_node("Hud").get_child_count() != 1 or cruiser.get_node_or_null("Cockpit") != null or markers.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("FAIL _test_hud_is_only_the_flight_markers: the internal-cruiser's HUD must be the flight markers alone")
		result = 1
	cruiser.free()
	return result

func _test_small_hull() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	var shape_node := cruiser.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not (shape_node.shape is BoxShape3D) or not (shape_node.shape as BoxShape3D).size.is_equal_approx(Vector3(4.0, 2.0, 8.0)):
		print("FAIL _test_small_hull: expected a 4 x 2 x 8 box")
		result = 1
	cruiser.free()
	return result

func _test_ramp_stops_at_10x() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.forward_thrust_steps != PackedFloat64Array([10.0]) or not is_equal_approx(cruiser.forward_thrust_step_duration, 5.0):
		print("FAIL _test_ramp_stops_at_10x: steps %s every %f s, expected [10] every 5 s" % [cruiser.forward_thrust_steps, cruiser.forward_thrust_step_duration])
		result = 1
	cruiser.free()
	return result

func _test_top_speed_about_1_km_s_after_the_ramp() -> int:
	# thrust 70 x 10, damping 0.5: v = 700 / ln 2 ~ 1010 m/s (1016 with 60 Hz
	# steps). Without the ramp it would stay near 101 m/s.
	var cruiser := _make_cruiser()
	Input.action_press("move_forward")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 990.0 or speed > 1040.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_top_speed_about_1_km_s_after_the_ramp: velocity %s (speed %.1f), expected about 1016 m/s toward -Z" % [cruiser.velocity, speed])
		result = 1
	cruiser.free()
	return result

func _test_same_mouse_sensitivity_as_void_cruiser() -> int:
	var cruiser := _make_cruiser()
	var void_cruiser: Node3D = VoidCruiserScript.new()
	var result := 0
	if not is_equal_approx(cruiser.mouse_sensitivity, void_cruiser.mouse_sensitivity):
		print("FAIL _test_same_mouse_sensitivity_as_void_cruiser: %f vs %f" % [cruiser.mouse_sensitivity, void_cruiser.mouse_sensitivity])
		result = 1
	cruiser.free()
	void_cruiser.free()
	return result
