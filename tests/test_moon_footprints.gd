extends SceneTree

# Boot prints: one every 0.7 m walking, 1.4 m jogging, left and right in
# turn; two side by side at a jump's take-off, two wide ones at landing; on
# the real moon five seconds of walking leave about eleven.

const MoonFootprints = preload("res://scripts/moon_footprints.gd")
const MoonScript = preload("res://scripts/moon.gd")
const MoonWalkerScript = preload("res://scripts/moon_walker.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

func _initialize():
	var failures := 0
	failures += _test_walk_stride()
	failures += _test_jog_stride()
	failures += _test_sides_alternate()
	failures += _test_jump_prints()
	failures += await _test_walker_leaves_prints()
	failures += await _test_long_walk_keeps_prints_in_near_blocks()
	failures += await _test_prints_face_up()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# Prints over `metres` in 1 cm steps.
func _walk(gait, metres: float, jogging: bool) -> Array:
	var prints := []
	for i in range(roundi(metres / 0.01)):
		prints.append_array(gait.step(0.01, jogging, false, false))
	return prints

func _test_walk_stride() -> int:
	var prints := _walk(MoonFootprints.Gait.new(), 7.0, false)
	if prints.size() != 10 or prints[0].kind != MoonFootprints.WALK:
		print("FAIL _test_walk_stride: %d prints over 7 m" % prints.size())
		return 1
	return 0

func _test_jog_stride() -> int:
	var prints := _walk(MoonFootprints.Gait.new(), 14.0, true)
	if prints.size() != 10 or prints[0].kind != MoonFootprints.JOG:
		print("FAIL _test_jog_stride: %d prints over 14 m" % prints.size())
		return 1
	return 0

func _test_sides_alternate() -> int:
	var prints := _walk(MoonFootprints.Gait.new(), 7.0, false)
	for k in range(1, prints.size()):
		if prints[k].side == prints[k - 1].side or absf(prints[k].side) != 1.0:
			print("FAIL _test_sides_alternate: %s" % [prints])
			return 1
	return 0

func _test_jump_prints() -> int:
	var gait = MoonFootprints.Gait.new()
	var off: Array = gait.step(0.0, false, true, false)
	var air: Array = gait.step(2.0, false, false, false)
	var down: Array = gait.step(0.0, false, false, true)
	if off.size() != 2 or off[0].kind != MoonFootprints.TAKEOFF or off[0].side == off[1].side or not air.is_empty() or down.size() != 2 or down[0].kind != MoonFootprints.LANDING:
		print("FAIL _test_jump_prints: %s / %s / %s" % [off, air, down])
		return 1
	return 0

func _test_walker_leaves_prints() -> int:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var system := Node3D.new()
	system.name = "PlanetSystem"
	system.position = Vector3(0.0, -4000.0, -6959600.0)
	world.add_child(system)
	var planet := Node3D.new()
	planet.name = "Planet"
	system.add_child(planet)
	var moon: Node3D = MoonScript.new()
	moon.name = "Moon"
	system.add_child(moon)
	var walker: CharacterBody3D = MoonWalkerScript.new()
	walker.name = "MoonWalker"
	world.add_child(walker)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../MoonWalker")
	world.add_child(rebase)
	await physics_frame
	var r: float = MoonScript.ground_radius()
	var base: Transform3D = moon.base_transform()
	var point: Vector3 = base * Vector3(400.0, sqrt(r * r - 400.0 * 400.0 - 150.0 * 150.0) - r, 150.0)
	walker.place(point, base * Vector3(400.0, 0.0, 0.0) - point)
	walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	for i in range(300):
		await physics_frame
	var count: int = moon.get_node("Footprints").print_count()
	if count < 10 or count > 12:
		print("FAIL _test_walker_leaves_prints: %d prints after 5 s (7.5 m)" % count)
		return 1
	return 0

func _prints_node() -> Node3D:
	var node: Node3D = MoonFootprints.new()
	root.add_child(node)
	await process_frame
	return node

# 200 m in a straight line: the newest print's block starts near it, so the
# block is drawn (visibility by the block's middle) while you stand there.
func _test_long_walk_keeps_prints_in_near_blocks() -> int:
	var node := await _prints_node()
	for k in range(286):
		node.add(Vector3(0.0, 0.0, -k * 0.7), Vector3(0.0, 0.0, -1.0), Vector3.UP, 1.0 if k % 2 == 0 else -1.0, MoonFootprints.WALK)
	var last: Node3D = node.get_child(node.get_child_count() - 1)
	var gap: float = last.position.distance_to(Vector3(0.0, 0.0, -285 * 0.7))
	node.free()
	if gap > 41.0:
		print("FAIL _test_long_walk_keeps_prints_in_near_blocks: the newest print %.0f m from its block's origin" % gap)
		return 1
	return 0

# Not mirrored: lit from above as the ground is. (Headless, a MultiMesh
# keeps no instances to read back: the transform is checked as built.)
func _test_prints_face_up() -> int:
	var det: float = MoonFootprints.print_transform(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP, 1.0, MoonFootprints.WALK).basis.determinant()
	if det <= 0.0:
		print("FAIL _test_prints_face_up: a print's basis is mirrored (determinant %.4f)" % det)
		return 1
	return 0
