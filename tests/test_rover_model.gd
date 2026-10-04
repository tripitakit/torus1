extends SceneTree

# The Moon Buggy's looks: the nodes the driving moves, its size, and a
# clear view ahead from the driver's eye.

const RoverModel = preload("res://scripts/rover_model.gd")
const EYE := Vector3(0.0, 1.3, -0.2)
# Glass the driver looks through.
const SEE_THROUGH := ["Dome", "DomeRing"]

func _initialize():
	var rover := Node3D.new()
	root.add_child(rover)
	RoverModel.build(rover)
	await process_frame
	var failures := 0
	failures += _test_driving_nodes(rover)
	failures += _test_size(rover)
	failures += _test_view_ahead_is_clear(rover)
	failures += _test_buggy_parts(rover)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _meshes(rover: Node3D) -> Array:
	return rover.find_children("*", "MeshInstance3D", true, false)

func _box(mesh: MeshInstance3D) -> AABB:
	return mesh.global_transform * mesh.get_aabb()

func _test_driving_nodes(rover: Node3D) -> int:
	for wheel in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		if rover.get_node_or_null(wheel + "/Spin") == null:
			print("FAIL _test_driving_nodes: no %s/Spin" % wheel)
			return 1
	return 0

func _test_size(rover: Node3D) -> int:
	var all := AABB()
	var first := true
	for mesh in _meshes(rover):
		all = _box(mesh) if first else all.merge(_box(mesh))
		first = false
	if all.position.x < -1.1 or all.end.x > 1.1 or all.position.y < -0.01 or all.end.y > 2.4 or all.position.z < -1.7 or all.end.z > 1.7:
		print("FAIL _test_size: %s" % all)
		return 1
	return 0

func _test_view_ahead_is_clear(rover: Node3D) -> int:
	for mesh in _meshes(rover):
		if String(mesh.name) in SEE_THROUGH:
			continue
		if _box(mesh).intersects_segment(EYE, EYE + Vector3(0.0, 0.0, -3.0)):
			print("FAIL _test_view_ahead_is_clear: %s in the way" % mesh.name)
			return 1
	return 0

func _test_buggy_parts(rover: Node3D) -> int:
	for part in ["Dome", "DomeRing", "Console", "SeatL", "SeatR", "FenderFL", "LampL", "LampR", "Cargo", "Antenna"]:
		if rover.get_node_or_null(part) == null:
			print("FAIL _test_buggy_parts: no %s" % part)
			return 1
	return 0
