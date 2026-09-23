extends SceneTree

# RayCast3D only reports hits after real physics frames, which the off-tree
# tests in test_void_cruiser.gd never process. Same in-tree technique as
# test_torus_station_physics.gd.

const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

var _failures := 0

func _initialize():
	await process_frame
	await physics_frame

	_failures += await _test_bow_sensor_measures_gap_from_hull_to_obstacle()
	_failures += await _test_sensor_with_nothing_in_range_reports_no_hit()
	_failures += await _test_sensors_follow_ship_rotation()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_cruiser_in_tree() -> CharacterBody3D:
	var cruiser: CharacterBody3D = VoidCruiserScript.new()
	root.add_child(cruiser)
	# Keep the ship still and skip per-frame work unrelated to the sensors.
	cruiser.set_physics_process(false)
	cruiser.set_process(false)
	return cruiser

func _make_obstacle(center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 10.0)
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = center
	root.add_child(body)
	return body

func _test_bow_sensor_measures_gap_from_hull_to_obstacle() -> int:
	var cruiser := _make_cruiser_in_tree()
	# Obstacle's near face at z = -115; bow hull face at z = -15: 100 m gap.
	var obstacle := _make_obstacle(Vector3(0.0, 0.0, -120.0))
	await physics_frame
	await physics_frame
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	if not is_equal_approx(distances["bow"], 100.0):
		print("FAIL _test_bow_sensor_measures_gap_from_hull_to_obstacle: bow=%s expected 100.0" % distances["bow"])
		result = 1
	cruiser.free()
	obstacle.free()
	return result

func _test_sensor_with_nothing_in_range_reports_no_hit() -> int:
	var cruiser := _make_cruiser_in_tree()
	var obstacle := _make_obstacle(Vector3(0.0, 0.0, -120.0))
	await physics_frame
	await physics_frame
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	if not is_equal_approx(distances["stern"], -1.0):
		print("FAIL _test_sensor_with_nothing_in_range_reports_no_hit: stern=%s expected -1.0" % distances["stern"])
		result = 1
	cruiser.free()
	obstacle.free()
	return result

func _test_sensors_follow_ship_rotation() -> int:
	var cruiser := _make_cruiser_in_tree()
	# Yaw +90°: the bow (-Z local) now points to world -X.
	cruiser.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	var obstacle := _make_obstacle(Vector3(-120.0, 0.0, 0.0))
	await physics_frame
	await physics_frame
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	if not is_equal_approx(distances["bow"], 100.0):
		print("FAIL _test_sensors_follow_ship_rotation: bow=%s expected 100.0 (sensors must use the ship's axes, not world axes)" % distances["bow"])
		result = 1
	cruiser.free()
	obstacle.free()
	return result
