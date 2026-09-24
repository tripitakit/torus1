extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

var _failures := 0

func _initialize():
	await process_frame
	_failures += await _test_bounces_off_the_terrain()
	_failures += await _test_cannot_fly_through_the_far_cap()
	_failures += await _test_its_camera_is_the_live_camera()
	_failures += await _test_hits_a_building_and_bounces()
	_failures += await _test_flies_over_a_lake_without_hitting_anything()
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

# World position (in the interior) of plan point (x, z) at `height` above the
# ahead section's floor.
func _ahead_point(x: float, z: float, height: float) -> Vector3:
	var start_z: float = -(1834.0 * 0.5 + 20000.0)
	var angle: float = x / 2000.0
	var r: float = 2000.0 - height
	return Vector3(cos(angle) * r, sin(angle) * r, start_z + z)

func _test_hits_a_building_and_bounces() -> int:
	# Toward the tallest tower, just below its roof, along +Z.
	var probe: Node3D = InteriorWorldScript.new()
	probe.build()
	var plan = probe.get_section_plan(-1.0)
	probe.free()
	var tallest := 0
	for b in range(plan.building_count()):
		if plan.building_size[b].y > plan.building_size[tallest].y:
			tallest = b
	var size: Vector3 = plan.building_size[tallest]
	var face_z: float = plan.building_z[tallest] - size.z * 0.5
	var start: Vector3 = _ahead_point(plan.building_x[tallest], face_z - 100.0, size.y - 3.0)
	var nodes := _make_world_with_cruiser(start, Vector3(0.0, 0.0, 50.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var face_world_z: float = _ahead_point(0.0, face_z, 0.0).z
	var deepest := -INF
	for tick in range(240):
		await physics_frame
		deepest = maxf(deepest, cruiser.position.z + 4.0)
	var result := 0
	if deepest > face_world_z + 0.5 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_hits_a_building_and_bounces: bow reached z %.2f (face at %.2f), velocity %s" % [deepest, face_world_z, cruiser.velocity])
		result = 1
	world.free()
	return result

func _test_flies_over_a_lake_without_hitting_anything() -> int:
	var probe: Node3D = InteriorWorldScript.new()
	probe.build()
	var plan = probe.get_section_plan(-1.0)
	probe.free()
	var lake := Vector2.ZERO
	for along in range(SectionPlan.LOTS_ALONG):
		for around in range(SectionPlan.LOTS_AROUND):
			if plan.zone_at(around, along) == SectionPlan.Zone.WATER and lake == Vector2.ZERO:
				lake = plan.lot_center(around, along)
	var nodes := _make_world_with_cruiser(_ahead_point(lake.x, lake.y - 30.0, 20.0), Vector3(0.0, 0.0, 30.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	for tick in range(120):
		await physics_frame
	var result := 0
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, 30.0)):
		print("FAIL _test_flies_over_a_lake_without_hitting_anything: velocity changed to %s" % cruiser.velocity)
		result = 1
	world.free()
	return result
