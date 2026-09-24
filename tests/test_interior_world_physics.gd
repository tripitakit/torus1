extends SceneTree

# Same failure mode as the station "teleport" bug, on the interior terrain's
# trimesh shape: a still hull turning while resting on the floor.

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

var _failures := 0

func _initialize():
	await process_frame
	_failures += await _test_rotating_hull_resting_on_terrain_does_not_jump()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_rotating_hull_resting_on_terrain_does_not_jump() -> int:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	root.add_child(world)
	var hull := CharacterBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 8.0)
	shape_node.shape = box
	hull.add_child(shape_node)
	root.add_child(hull)
	# Floor at the bottom of the ahead section, halfway along it.
	var center_z: float = -(world.bridge_length + world.section_length) * 0.5
	hull.global_position = Vector3(0.0, -(world.section_radius - 1.0 - 0.05), center_z)
	await physics_frame
	var biggest := 0.0
	for tick in range(240):
		var before: Vector3 = hull.global_position
		hull.move_and_collide(Vector3.ZERO)
		hull.rotate_object_local(Vector3.RIGHT, -0.7 / 60.0)
		hull.rotate_object_local(Vector3.UP, -1.4 / 60.0)
		await physics_frame
		biggest = maxf(biggest, hull.global_position.distance_to(before))
	var result := 0
	if biggest > 2.0:
		print("FAIL _test_rotating_hull_resting_on_terrain_does_not_jump: a still, turning hull was shoved %.1f m in one tick" % biggest)
		result = 1
	hull.free()
	world.free()
	return result
