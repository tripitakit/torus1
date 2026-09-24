extends SceneTree

const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

func _init():
	var failures := 0
	failures += _test_first_person_camera()
	failures += _test_no_hud()
	failures += _test_small_hull()
	failures += _test_top_speed_about_101_without_ramp()
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

func _test_no_hud() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.find_children("*", "CanvasLayer", true, false).size() > 0 or cruiser.get_node_or_null("Cockpit") != null:
		print("FAIL _test_no_hud: the internal-cruiser must have no HUD")
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

func _test_top_speed_about_101_without_ramp() -> int:
	# thrust 70, damping 0.5: v = 70 / ln 2 ~ 101 m/s. With the void-cruiser's
	# 10x ramp it would pass 1000 m/s.
	var cruiser := _make_cruiser()
	Input.action_press("move_forward")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 95.0 or speed > 105.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_top_speed_about_101_without_ramp: velocity %s (speed %.1f), expected about 101 m/s toward -Z" % [cruiser.velocity, speed])
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
