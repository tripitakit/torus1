extends SceneTree

# The patch of fine ground under the ship: three square rings (8, 32 and
# 128 m apart) on the ground's heights, no cracks between them, rebuilt as
# the ship moves.

const MoonPatch = preload("res://scripts/moon_patch.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonScript = preload("res://scripts/moon.gd")

var _failures := 0

func _initialize():
	MoonTerrain.load_heights()
	_failures += _test_rings_cover_the_square()
	_failures += _test_inner_vertices_on_the_ground()
	_failures += _test_ring_edges_meet()
	_failures += _test_normals_point_up()
	_failures += _test_outer_edge_on_the_whole_moon()
	_failures += await _test_node_follows_the_ship()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _centre() -> Vector3:
	return MoonScript.direction_of(-20.0, 40.0)

func _test_rings_cover_the_square() -> int:
	var rings := MoonPatch.build_rings(_centre())
	if rings.size() != MoonPatch.SPACINGS.size():
		print("FAIL _test_rings_cover_the_square: %d rings" % rings.size())
		return 1
	var frame := MoonPatch.tangent_frame(_centre())
	for k in range(rings.size()):
		var reach := 0.0
		for v in (rings[k].vertices as PackedVector3Array):
			var p: Vector3 = v + (rings[k].origin as Vector3)
			var flat := p - frame.basis.y * p.dot(frame.basis.y)
			reach = maxf(reach, maxf(absf(flat.dot(frame.basis.x)), absf(flat.dot(frame.basis.z))))
		var expected: float = MoonPatch.SPACINGS[k] * MoonPatch.CELLS * 0.5
		if absf(reach - expected) > expected * 0.02:
			print("FAIL _test_rings_cover_the_square: ring %d reaches %.0f m, expected %.0f" % [k, reach, expected])
			return 1
	return 0

func _test_inner_vertices_on_the_ground() -> int:
	# In the inner ring's middle half (round the ship, where it touches
	# down), every vertex sits on MoonTerrain.height, all craters in; toward
	# the edge the smallest fade out.
	var ring: Dictionary = MoonPatch.build_rings(_centre())[0]
	var vertices: PackedVector3Array = ring.vertices
	var origin: Vector3 = ring.origin
	var frame := MoonPatch.tangent_frame(_centre())
	var quarter: float = MoonPatch.SPACINGS[0] * MoonPatch.CELLS * 0.25
	var worst := 0.0
	for i in range(0, (MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1), 7):
		var p: Vector3 = vertices[i] + origin
		var flat: Vector3 = p * (MoonOrbit.RADIUS / p.dot(frame.basis.y)) - frame.origin
		if absf(flat.dot(frame.basis.x)) > quarter or absf(flat.dot(frame.basis.z)) > quarter:
			continue
		var expected := MoonOrbit.RADIUS + MoonTerrain.height(p.normalized())
		worst = maxf(worst, absf(p.length() - expected))
	if worst > 0.05:
		print("FAIL _test_inner_vertices_on_the_ground: %.3f m off" % worst)
		return 1
	return 0

func _test_ring_edges_meet() -> int:
	# Each fine ring's outer edge lies on the next ring's surface: sample
	# the edge vertices against the coarse ring's triangles along the edge.
	var rings := MoonPatch.build_rings(_centre())
	for k in range(rings.size() - 1):
		var fine: Dictionary = rings[k]
		var gap := MoonPatch.edge_gap(fine, rings[k + 1])
		if gap > 0.05:
			print("FAIL _test_ring_edges_meet: ring %d's edge %.3f m off ring %d" % [k, gap, k + 1])
			return 1
	return 0

func _test_outer_edge_on_the_whole_moon() -> int:
	# The outer ring's edge lies on the whole moon's mesh (no step where the
	# two meet).
	const MoonMesh = preload("res://scripts/moon_mesh.gd")
	var ring: Dictionary = MoonPatch.build_rings(_centre())[-1]
	var vertices: PackedVector3Array = ring.vertices
	var edge: PackedByteArray = ring.edge
	var origin: Vector3 = ring.origin
	var worst := 0.0
	for i in range(edge.size()):
		if edge[i] == 1:
			var p: Vector3 = vertices[i] + origin
			worst = maxf(worst, absf(p.length() - MoonMesh.mesh_radius(p.normalized())))
	if worst > 0.1:
		print("FAIL _test_outer_edge_on_the_whole_moon: %.2f m off" % worst)
		return 1
	return 0

func _test_normals_point_up() -> int:
	var ring: Dictionary = MoonPatch.build_rings(_centre())[0]
	var normals: PackedVector3Array = ring.normals
	var vertices: PackedVector3Array = ring.vertices
	var origin: Vector3 = ring.origin
	for i in range(0, normals.size(), 53):
		var up := (vertices[i] + origin).normalized()
		if normals[i].dot(up) < 0.3:
			print("FAIL _test_normals_point_up: normal %s against up %s" % [normals[i], up])
			return 1
	return 0

func _test_node_follows_the_ship() -> int:
	var patch: Node3D = MoonPatch.new()
	root.add_child(patch)
	var first := _centre() * (MoonOrbit.RADIUS + 500.0)
	patch.follow(first)
	if not await _until_built(patch):
		print("FAIL _test_node_follows_the_ship: never built")
		patch.queue_free()
		return 1
	var centre_a: Vector3 = patch.centre
	# A small move: no rebuild; a move past a quarter of the inner ring: one.
	var side := MoonPatch.tangent_frame(_centre()).basis.x
	patch.follow(first + side * 20.0)
	var rebuilt_small: bool = patch.building
	patch.follow(first + side * 200.0)
	if rebuilt_small or not await _until_built(patch) or patch.centre.is_equal_approx(centre_a):
		print("FAIL _test_node_follows_the_ship: small move rebuilt %s, centre still %s" % [rebuilt_small, patch.centre])
		patch.queue_free()
		return 1
	var meshes := patch.find_children("Ring*", "MeshInstance3D", false, false)
	if meshes.size() != MoonPatch.SPACINGS.size() or not patch.visible:
		print("FAIL _test_node_follows_the_ship: %d ring meshes" % meshes.size())
		patch.queue_free()
		return 1
	patch.stop()
	if patch.visible:
		print("FAIL _test_node_follows_the_ship: still shown after stop")
		patch.queue_free()
		return 1
	patch.queue_free()
	return 0

func _until_built(patch: Node3D) -> bool:
	for frame in range(600):
		await process_frame
		if not patch.building and patch.built:
			return true
	return false
