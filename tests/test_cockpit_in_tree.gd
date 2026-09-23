extends SceneTree

# Which camera actually renders is only decided inside a processed tree.

const CockpitScript = preload("res://scripts/cockpit.gd")

var _failures := 0

func _initialize():
	await process_frame

	_failures += await _test_pilot_camera_renders_from_the_moving_eye()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_pilot_camera_renders_from_the_moving_eye() -> int:
	var ship := Node3D.new()
	root.add_child(ship)
	var cockpit: Node3D = CockpitScript.new()
	cockpit.position = Vector3(0.0, 0.5, -8.0)
	ship.add_child(cockpit)
	cockpit.build()
	ship.position = Vector3(100.0, 20.0, -300.0)
	ship.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	await process_frame
	var result := 0
	var camera: Camera3D = cockpit.get_node("PilotCamera")
	if root.get_camera_3d() != camera:
		print("FAIL _test_pilot_camera_renders_from_the_moving_eye: the window renders %s, expected PilotCamera" % root.get_camera_3d())
		result = 1
	if not camera.global_transform.origin.is_equal_approx(cockpit.global_transform.origin):
		print("FAIL _test_pilot_camera_renders_from_the_moving_eye: camera at %s, eye at %s" % [camera.global_transform.origin, cockpit.global_transform.origin])
		result = 1
	if not (-camera.global_transform.basis.z).is_equal_approx(-ship.global_transform.basis.z):
		print("FAIL _test_pilot_camera_renders_from_the_moving_eye: camera looks %s, ship bow %s" % [-camera.global_transform.basis.z, -ship.global_transform.basis.z])
		result = 1
	ship.free()
	return result
