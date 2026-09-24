extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")

var _failures := 0

func _initialize():
	await process_frame
	_failures += await _test_bounces_off_the_terrain()
	_failures += await _test_cannot_fly_through_the_far_cap()
	_failures += await _test_its_camera_is_the_live_camera()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_world_with_cruiser(start: Vector3, start_velocity: Vector3) -> Array:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	var cruiser: CharacterBody3D = InternalCruiserScript.new()
	cruiser.name = "InternalCruiser"
	cruiser.linear_damping = 0.0
	cruiser.position = start
	cruiser.velocity = start_velocity
	world.add_child(cruiser)
	root.add_child(world)
	return [world, cruiser]

func _test_bounces_off_the_terrain() -> int:
	var center_z: float = -(1834.0 + 20000.0) * 0.5
	var nodes := _make_world_with_cruiser(Vector3(0.0, -(2000.0 - 30.0), center_z), Vector3(0.0, -30.0, 0.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var deepest := 0.0
	for tick in range(180):
		await physics_frame
		deepest = maxf(deepest, Vector2(cruiser.position.x, cruiser.position.y).length())
	var result := 0
	if cruiser.velocity.y <= 0.0 or deepest > 2000.0:
		print("FAIL _test_bounces_off_the_terrain: velocity %s, deepest %.2f m from the axis (floor at 2000)" % [cruiser.velocity, deepest])
		result = 1
	world.free()
	return result

func _test_cannot_fly_through_the_far_cap() -> int:
	var far_cap_z: float = -(1834.0 * 0.5 + 20000.0)
	var nodes := _make_world_with_cruiser(Vector3(0.0, 0.0, far_cap_z + 200.0), Vector3(0.0, 0.0, -100.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var furthest := 0.0
	for tick in range(240):
		await physics_frame
		furthest = minf(furthest, cruiser.position.z)
	var result := 0
	if furthest < far_cap_z or cruiser.velocity.z <= 0.0:
		print("FAIL _test_cannot_fly_through_the_far_cap: reached z %.2f (cap at %.2f), velocity %s" % [furthest, far_cap_z, cruiser.velocity])
		result = 1
	world.free()
	return result

func _test_its_camera_is_the_live_camera() -> int:
	var nodes := _make_world_with_cruiser(Vector3(0.0, -500.0, 0.0), Vector3.ZERO)
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	await process_frame
	var result := 0
	if root.get_camera_3d() != cruiser.get_node("Camera"):
		print("FAIL _test_its_camera_is_the_live_camera: the window renders %s" % root.get_camera_3d())
		result = 1
	world.free()
	return result
