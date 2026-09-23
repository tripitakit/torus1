extends SceneTree

# A SubViewport breaks the 3D transform chain, so the exterior cameras only
# follow the ship through their RemoteTransform3D mounts, which update only
# inside a processed tree. Off-tree tests cannot see this.

const CockpitScript = preload("res://scripts/cockpit.gd")

var _failures := 0

func _initialize():
	await process_frame

	_failures += await _test_exterior_cameras_follow_the_pilot_eye()
	_failures += await _test_side_cameras_look_sixty_degrees_off_the_bow()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_moved_ship_with_cockpit() -> Array:
	var ship := Node3D.new()
	root.add_child(ship)
	var cockpit: Node3D = CockpitScript.new()
	cockpit.position = Vector3(0.0, 0.5, -8.0)
	ship.add_child(cockpit)
	cockpit.build()
	# Move and turn the ship after the cockpit is built, as flight (and a
	# world-origin rebase) does.
	ship.position = Vector3(100.0, 20.0, -300.0)
	ship.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	return [ship, cockpit]

func _test_exterior_cameras_follow_the_pilot_eye() -> int:
	var nodes := _make_moved_ship_with_cockpit()
	var ship: Node3D = nodes[0]
	var cockpit: Node3D = nodes[1]
	await process_frame
	await physics_frame
	var result := 0
	for prefix in ["Front", "Left", "Right"]:
		var camera: Camera3D = cockpit.get_node("%sViewport/Camera" % prefix)
		if not camera.global_transform.origin.is_equal_approx(cockpit.global_transform.origin):
			print("FAIL _test_exterior_cameras_follow_the_pilot_eye: %s camera at %s, eye at %s" % [prefix, camera.global_transform.origin, cockpit.global_transform.origin])
			result = 1
	ship.free()
	return result

func _test_side_cameras_look_sixty_degrees_off_the_bow() -> int:
	var nodes := _make_moved_ship_with_cockpit()
	var ship: Node3D = nodes[0]
	var cockpit: Node3D = nodes[1]
	await process_frame
	await physics_frame
	var ship_forward: Vector3 = -ship.global_transform.basis.z
	var ship_left: Vector3 = -ship.global_transform.basis.x
	var sin_60: float = sin(deg_to_rad(60.0))
	# prefix: [expected dot with ship forward, expected dot with ship left]
	var expected := {"Front": [1.0, 0.0], "Left": [0.5, sin_60], "Right": [0.5, -sin_60]}
	var result := 0
	for prefix in expected:
		var camera: Camera3D = cockpit.get_node("%sViewport/Camera" % prefix)
		var looks: Vector3 = -camera.global_transform.basis.z
		if not is_equal_approx(looks.dot(ship_forward), expected[prefix][0]) or not is_equal_approx(looks.dot(ship_left), expected[prefix][1]):
			print("FAIL _test_side_cameras_look_sixty_degrees_off_the_bow: %s looks %s (forward·=%f left·=%f) expected forward·=%f left·=%f" % [prefix, looks, looks.dot(ship_forward), looks.dot(ship_left), expected[prefix][0], expected[prefix][1]])
			result = 1
	ship.free()
	return result
