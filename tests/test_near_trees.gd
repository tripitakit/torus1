extends SceneTree

# The detailed trees round the camera (NearTrees): which trees of a chunk's
# buffer are taken, into which variant, and the node building them in the
# chunks near the camera.

const NearTrees = preload("res://scripts/near_trees.gd")
const TreeModels = preload("res://scripts/tree_models.gd")
const TerrainDressing = preload("res://scripts/terrain_dressing.gd")

const RADIUS := 2000.0

func _initialize():
	var failures := 0
	failures += _test_select_takes_the_trees_in_reach()
	failures += await _test_node_builds_round_the_camera()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# A row of trees along z on the wall (chunk frame: the wall at RADIUS from
# the axis, up toward it), 20 m tall, 7 m across.
func _row(count: int, step: float) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for k in range(count):
		var up := Vector3(0.0, -1.0, 0.0)
		var side := Vector3(1.0, 0.0, 0.0) * (7.0 / 0.6)
		var front := Vector3(0.0, 0.0, 1.0) * (7.0 / 0.6)
		var by := up * 20.0
		var origin := Vector3(0.0, RADIUS - 100.0 + TerrainDressing.TREE_SINK, k * step)
		data.append_array(PackedFloat32Array([side.x, by.x, front.x, origin.x, side.y, by.y, front.y, origin.y, side.z, by.z, front.z, origin.z, 0.2, 0.4, 0.1, 1.0]))
	return data

func _test_select_takes_the_trees_in_reach() -> int:
	var buffer := _row(100, 17.0)
	var camera := Vector3(0.0, RADIUS - 101.7, 300.0)
	var parts := NearTrees.select(buffer, false, camera, 200.0, RADIUS)
	var taken := 0
	var within := 0
	for k in range(100):
		if Vector3(0.0, RADIUS - 100.0 + TerrainDressing.TREE_SINK, k * 17.0).distance_to(camera) <= 200.0:
			within += 1
	if parts.size() != TreeModels.variants().size():
		print("FAIL _test_select_takes_the_trees_in_reach: %d parts" % parts.size())
		return 1
	for part: PackedFloat32Array in parts:
		taken += part.size() / 12
		for i in range(part.size() / 12):
			var b := i * 12
			var origin := Vector3(part[b + 3], part[b + 7], part[b + 11])
			var by := Vector3(part[b + 1], part[b + 5], part[b + 9])
			var bx := Vector3(part[b], part[b + 4], part[b + 8])
			# Kept where it stood, scaled evenly to its height (the model keeps
			# its own proportions).
			if origin.distance_to(camera) > 200.0 or absf(by.length() - 20.0) > 0.01 or absf(bx.length() - 20.0) > 0.01:
				print("FAIL _test_select_takes_the_trees_in_reach: %s, height %.2f, across %.2f" % [origin, by.length(), bx.length()])
				return 1
	if taken != within or within == 0:
		print("FAIL _test_select_takes_the_trees_in_reach: took %d of %d" % [taken, within])
		return 1
	return 0

# A fake chunk with trees, a camera among them: the node builds the detailed
# trees there; the camera far away again: they go.
func _test_node_builds_round_the_camera() -> int:
	var world := Node3D.new()
	root.add_child(world)
	var chunk := Node3D.new()
	world.add_child(chunk)
	var trees := Node3D.new()
	trees.name = "Trees"
	chunk.add_child(trees)
	NearTrees.register(trees, _row(100, 17.0), PackedFloat32Array(), RADIUS, AABB(Vector3(-50.0, RADIUS - 150.0, -10.0), Vector3(100.0, 160.0, 1720.0)))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, RADIUS - 101.7, 300.0)
	camera.current = true
	var near: Node3D = NearTrees.new()
	world.add_child(near)
	for i in range(30):
		await process_frame
	var built := _count(trees)
	camera.position = Vector3(0.0, RADIUS - 101.7, 5000.0)
	for i in range(30):
		await process_frame
	var after := _count(trees)
	world.free()
	var expected := 0
	for k in range(100):
		if Vector3(0.0, RADIUS - 100.0 + TerrainDressing.TREE_SINK, k * 17.0).distance_to(Vector3(0.0, RADIUS - 101.7, 300.0)) <= NearTrees.REACH:
			expected += 1
	if built != expected or after != 0:
		print("FAIL _test_node_builds_round_the_camera: %d built (%d expected), %d left far away" % [built, expected, after])
		return 1
	return 0

func _count(trees: Node3D) -> int:
	var total := 0
	for node in trees.find_children("*", "MultiMeshInstance3D", true, false):
		if String(node.name).begins_with("Near"):
			total += (node as MultiMeshInstance3D).multimesh.instance_count
	return total
