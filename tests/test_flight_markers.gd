extends SceneTree

# The boresight and motion markers (scripts/flight_markers.gd): where the
# motion marker lands for a camera, and the void-cruiser's on the real scene.

const FlightMarkers = preload("res://scripts/flight_markers.gd")

var _failures := 0

func _initialize():
	root.size = Vector2i(1280, 720)
	_failures += await _test_motion_marker_placement()
	_failures += _test_two_contrasting_colours()
	_failures += await _test_void_cruiser_marker_centred_flying_straight()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_motion_marker_placement() -> int:
	# A camera at the origin looking down -Z.
	var camera := Camera3D.new()
	camera.fov = 90.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(camera)
	camera.make_current()
	await process_frame
	var centre := Vector2(root.size) * 0.5
	var result := 0
	var ahead: Dictionary = FlightMarkers.motion_marker(camera, Vector3(0.0, 0.0, -30.0))
	if ahead.kind != FlightMarkers.Motion.PROGRADE or ahead.point.distance_to(centre) > 1.0:
		print("FAIL _test_motion_marker_placement: straight ahead gave %s at %s" % [ahead.kind, ahead.point])
		result = 1
	var right: Dictionary = FlightMarkers.motion_marker(camera, Vector3(10.0, 0.0, -30.0))
	if right.kind != FlightMarkers.Motion.PROGRADE or right.point.x <= centre.x + 10.0 or absf(right.point.y - centre.y) > 1.0:
		print("FAIL _test_motion_marker_placement: ahead and to the right gave %s at %s" % [right.kind, right.point])
		result = 1
	var back: Dictionary = FlightMarkers.motion_marker(camera, Vector3(0.0, 0.0, 30.0))
	if back.kind != FlightMarkers.Motion.RETROGRADE or back.point.distance_to(centre) > 1.0:
		print("FAIL _test_motion_marker_placement: backwards gave %s at %s, expected retrograde at the centre" % [back.kind, back.point])
		result = 1
	if FlightMarkers.motion_marker(camera, Vector3(0.3, 0.0, 0.0)).kind != FlightMarkers.Motion.NONE:
		print("FAIL _test_motion_marker_placement: a marker under 0.5 m/s")
		result = 1
	camera.queue_free()
	await process_frame
	return result

func _test_two_contrasting_colours() -> int:
	# White boresight, magenta motion marker, both with a dark rim.
	var b := FlightMarkers.BORESIGHT_COLOR
	var m := FlightMarkers.MOTION_COLOR
	if not (b.r > 0.9 and b.g > 0.9 and b.b > 0.9) or not (m.r > 0.8 and m.g < 0.4 and m.b > 0.6):
		print("FAIL _test_two_contrasting_colours: boresight %s, motion %s" % [b, m])
		return 1
	# A dark rim under every line keeps both readable on white clouds too.
	if FlightMarkers.OUTLINE_COLOR.get_luminance() > 0.2 or FlightMarkers.OUTLINE_WIDTH <= FlightMarkers.LINE_WIDTH:
		print("FAIL _test_two_contrasting_colours: no dark outline wider than the lines")
		return 1
	return 0

func _test_void_cruiser_marker_centred_flying_straight() -> int:
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	var cruiser: CharacterBody3D = scene.get_node("VoidCruiser")
	cruiser.set_physics_process(false)
	cruiser.velocity = -cruiser.global_transform.basis.z * 40.0
	for i in range(2):
		await process_frame
	var markers: Control = cruiser.get_node("Cockpit/Hud/FlightMarkers")
	var result := 0
	if markers.motion != FlightMarkers.Motion.PROGRADE or markers.motion_point.distance_to(markers.size * 0.5) > 2.0:
		print("FAIL _test_void_cruiser_marker_centred_flying_straight: %s at %s, screen centre %s" % [markers.motion, markers.motion_point, markers.size * 0.5])
		result = 1
	scene.queue_free()
	await process_frame
	return result
