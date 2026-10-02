extends SceneTree

# The patch of fine ground under the ship: three square rings on a lattice
# fixed on the moon (a cube face's plane), each vertex carrying its full
# height and the next ring's (or the whole moon's) to morph to by distance;
# no cracks between rings; rebuilt as the ship moves, heights cached.

const MoonPatch = preload("res://scripts/moon_patch.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonMesh = preload("res://scripts/moon_mesh.gd")
const MoonScript = preload("res://scripts/moon.gd")

var _failures := 0

func _initialize():
	MoonTerrain.load_heights()
	_failures += _test_rings_cover_their_windows()
	_failures += _test_vertices_on_the_ground()
	_failures += _test_same_point_same_vertex_after_a_move()
	_failures += _test_edges_meet_the_next_ring()
	_failures += _test_outer_edge_on_the_whole_moon()
	_failures += _test_morph_targets_lie_on_the_coarser_surface()
	_failures += _test_normals_point_up()
	_failures += _test_cache_reused_on_a_small_move()
	_failures += await _test_node_follows_the_ship()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _centre() -> Vector3:
	return MoonScript.direction_of(-20.0, 40.0)

func _build(direction: Vector3) -> Array:
	var face := MoonPatch.face_of(direction, -1)
	return MoonPatch.build_rings(face, MoonPatch.plane_coords(direction, face))

func _world(ring: Dictionary, i: int) -> Vector3:
	return (ring.vertices as PackedVector3Array)[i] + (ring.origin as Vector3)

func _test_rings_cover_their_windows() -> int:
	var rings := _build(_centre())
	if rings.size() != MoonPatch.SPACINGS.size():
		print("FAIL _test_rings_cover_their_windows: %d rings" % rings.size())
		return 1
	for k in range(rings.size()):
		var ring: Dictionary = rings[k]
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
			var uv := MoonPatch.plane_coords(_world(ring, i).normalized(), ring.face)
			low = low.min(uv)
			high = high.max(uv)
		var expected: float = MoonPatch.SPACINGS[k] * MoonPatch.CELLS
		if absf((high - low).x - expected) > 0.5 or absf((high - low).y - expected) > 0.5:
			print("FAIL _test_rings_cover_their_windows: ring %d spans %s, expected %.0f" % [k, high - low, expected])
			return 1
	return 0

func _test_vertices_on_the_ground() -> int:
	# The inner ring's own heights: MoonTerrain with every crater (its outer
	# edge aside, which lies on the next ring).
	var ring: Dictionary = _build(_centre())[0]
	var edge: PackedByteArray = ring.edge
	var worst := 0.0
	for i in range(0, (MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1), 7):
		if edge[i] == 1:
			continue
		var p := _world(ring, i)
		worst = maxf(worst, absf(p.length() - MoonOrbit.RADIUS - MoonTerrain.height(p.normalized())))
	if worst > 0.05:
		print("FAIL _test_vertices_on_the_ground: %.3f m off" % worst)
		return 1
	return 0

func _test_same_point_same_vertex_after_a_move() -> int:
	# A move of a few hundred metres: the vertices still on the moon's
	# lattice where the rings overlap: each old point is a new point too.
	var a: Dictionary = _build(_centre())[0]
	var moved := (_centre() + Vector3(0.0003, 0.0002, 0.0)).normalized()
	var b: Dictionary = _build(moved)[0]
	var found := 0
	var points := {}
	for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
		if (b.edge as PackedByteArray)[i] == 0:
			points[_key(_world(b, i))] = _world(b, i)
	for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
		if (a.edge as PackedByteArray)[i] == 1:
			continue
		var p := _world(a, i)
		if points.has(_key(p)):
			found += 1
			if (points[_key(p)] as Vector3).distance_to(p) > 0.01:
				print("FAIL _test_same_point_same_vertex_after_a_move: %s moved" % p)
				return 1
	if found < 100:
		print("FAIL _test_same_point_same_vertex_after_a_move: only %d shared points" % found)
		return 1
	return 0

func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))

func _test_edges_meet_the_next_ring() -> int:
	# A fine ring's outer edge lies on the next ring's triangles: its morph
	# target there is itself, and on the coarse lattice points the two rings
	# share the very vertex.
	var rings := _build(_centre())
	for k in range(rings.size() - 1):
		var fine: Dictionary = rings[k]
		var coarse: Dictionary = rings[k + 1]
		var shared := {}
		for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
			shared[_key(_world(coarse, i))] = _world(coarse, i)
		var matched := 0
		for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
			if (fine.edge as PackedByteArray)[i] == 0:
				continue
			if (fine.morph as PackedFloat32Array)[i * 4] != 0.0 or (fine.morph as PackedFloat32Array)[i * 4 + 1] != 0.0 or (fine.morph as PackedFloat32Array)[i * 4 + 2] != 0.0:
				print("FAIL _test_edges_meet_the_next_ring: ring %d edge vertex %d morphs" % [k, i])
				return 1
			var p := _world(fine, i)
			if shared.has(_key(p)):
				matched += 1
				if (shared[_key(p)] as Vector3).distance_to(p) > 0.05:
					print("FAIL _test_edges_meet_the_next_ring: ring %d edge %.3f m off ring %d" % [k, (shared[_key(p)] as Vector3).distance_to(p), k + 1])
					return 1
		if matched < 60:
			print("FAIL _test_edges_meet_the_next_ring: ring %d shares only %d edge points" % [k, matched])
			return 1
	return 0

func _test_outer_edge_on_the_whole_moon() -> int:
	var ring: Dictionary = _build(_centre())[-1]
	var worst := 0.0
	for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
		if (ring.edge as PackedByteArray)[i] == 1:
			var p := _world(ring, i)
			worst = maxf(worst, absf(p.length() - MoonMesh.mesh_radius(p.normalized())))
	if worst > 0.1:
		print("FAIL _test_outer_edge_on_the_whole_moon: %.2f m off" % worst)
		return 1
	return 0

func _test_morph_targets_lie_on_the_coarser_surface() -> int:
	# Every inner-ring vertex's target is on the middle ring's surface: on
	# a shared lattice point, exactly that ring's vertex.
	var rings := _build(_centre())
	var fine: Dictionary = rings[0]
	var coarse: Dictionary = rings[1]
	var shared := {}
	for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
		shared[_key(_world(coarse, i))] = _world(coarse, i)
	var matched := 0
	var morph: PackedFloat32Array = fine.morph
	for i in range((MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1)):
		var p := _world(fine, i)
		var target := p + Vector3(morph[i * 4], morph[i * 4 + 1], morph[i * 4 + 2])
		if absf(morph[i * 4 + 3] - MoonPatch.SPACINGS[0] * MoonPatch.CELLS * 0.5) > 0.001:
			print("FAIL _test_morph_targets_lie_on_the_coarser_surface: half width %.1f" % morph[i * 4 + 3])
			return 1
		if shared.has(_key(p)):
			matched += 1
			if (shared[_key(p)] as Vector3).distance_to(target) > 0.05:
				print("FAIL _test_morph_targets_lie_on_the_coarser_surface: %.3f m off" % (shared[_key(p)] as Vector3).distance_to(target))
				return 1
	if matched < 200:
		print("FAIL _test_morph_targets_lie_on_the_coarser_surface: only %d shared points" % matched)
		return 1
	return 0

func _test_normals_point_up() -> int:
	var ring: Dictionary = _build(_centre())[0]
	var normals: PackedVector3Array = ring.normals
	for i in range(0, normals.size(), 53):
		var up := _world(ring, i).normalized()
		if normals[i].dot(up) < 0.3:
			print("FAIL _test_normals_point_up: normal %s against up %s" % [normals[i], up])
			return 1
	return 0

func _test_cache_reused_on_a_small_move() -> int:
	# One snap step (64 m) over: most heights come from the cache.
	var direction := _centre()
	var face := MoonPatch.face_of(direction, -1)
	var plane := MoonPatch.plane_coords(direction, face)
	MoonPatch.build_rings(face, plane)
	var before := MoonPatch.samples_taken()
	MoonPatch.build_rings(face, plane + Vector2(MoonPatch.SPACINGS[0] * MoonPatch.SNAP_CELLS, 0.0))
	var taken := MoonPatch.samples_taken() - before
	var all := (MoonPatch.CELLS + 1) * (MoonPatch.CELLS + 1) * MoonPatch.SPACINGS.size()
	if taken > all / 4:
		print("FAIL _test_cache_reused_on_a_small_move: %d new samples of %d" % [taken, all])
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
	var window: Vector2i = patch.window
	# A move inside one snap step: no rebuild; past it: one.
	var face: int = patch.face
	var side := Vector3.ZERO
	side[(face / 2 + 1) % 3] = 1.0
	patch.follow(first + side * 5.0)
	var rebuilt_small: bool = patch.building
	patch.follow(first + side * 200.0)
	if rebuilt_small or not await _until_built(patch) or patch.window == window:
		print("FAIL _test_node_follows_the_ship: small move rebuilt %s, window still %s" % [rebuilt_small, patch.window])
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
