extends SceneTree

const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")
const TerrainDressing = preload("res://scripts/terrain_dressing.gd")
const BuildingShapes = preload("res://scripts/building_shapes.gd")

const RADIUS := 2000.0

var _plan = SectionGenerator.generate(42, RADIUS, 20000.0)
var _dressing = TerrainDressing.new()
var _groups: Dictionary = _plan.group_buildings_by_chunk()

func _init():
	var failures := 0
	failures += _test_cell_road_picks_edges_and_crossings()
	failures += _test_ground_vertices_at_their_height_facing_the_axis()
	failures += _test_ground_area_is_the_chunk_area()
	failures += _test_flat_plan_keeps_the_level_zero_mosaic()
	failures += _test_relief_normals_lean_downhill()
	failures += _test_relief_chunk_has_no_cracks()
	failures += _test_raised_ground_colours()
	failures += _test_relief_chunk_collides_on_its_height_grid()
	failures += _test_ground_built_on_a_worker_matches_one_built_in_place()
	failures += _test_drawn_ground_lies_on_its_collision()
	failures += _test_chunks_along_share_their_border_vertices()
	failures += _test_water_only_where_the_plan_has_lakes()
	failures += _test_road_colours_where_the_plan_has_roads()
	failures += _test_building_transform_stands_on_the_wall_facing_the_axis()
	failures += _test_chunk_buildings_match_the_plan()
	failures += _test_building_colliders_match_the_drawn_buildings()
	failures += _test_building_bounds_cover_the_tallest_building()
	failures += _test_building_custom_data_carries_the_look()
	failures += _test_building_shader_reads_each_building()
	failures += _test_released_chunks_drop_only_the_shapes_nobody_uses()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _chunk_has_zone(key: Vector2i, zone: int) -> bool:
	for lot_x in range(3):
		for lot_z in range(4):
			if _plan.zone_at(key.x * 3 + lot_x, key.y * 4 + lot_z) == zone:
				return true
	return false

func _find_chunk(zone: int, wanted: bool) -> Vector2i:
	for along in range(20):
		for around in range(16):
			var key := Vector2i(around, along)
			if _chunk_has_zone(key, zone) == wanted:
				return key
	return Vector2i(-1, -1)

func _dress(key: Vector2i) -> StaticBody3D:
	var chunk := StaticBody3D.new()
	_dressing.dress_chunk(chunk, _plan, key.x, key.y, _groups.get(key, []))
	return chunk

func _ground_meshes(chunk: Node) -> Array:
	var meshes := []
	for part in ["Surface", "Water"]:
		var node := chunk.get_node_or_null(part) as MeshInstance3D
		if node:
			meshes.append(node.mesh)
	return meshes

func _test_cell_road_picks_edges_and_crossings() -> int:
	var main: int = SectionPlan.Road.MAIN
	var street: int = SectionPlan.Road.STREET
	var none: int = SectionPlan.Road.NONE
	var cases := [
		[1, 1, none],      # centre: never road
		[0, 1, main],      # west band
		[2, 1, street],    # east band
		[1, 0, street],    # south band
		[1, 2, none],      # north band
		[0, 0, main],      # south-west crossing: the bigger road wins
	]
	for c in cases:
		var got: int = TerrainDressing.cell_road(c[0], c[1], main, street, street, none)
		if got != c[2]:
			print("FAIL _test_cell_road_picks_edges_and_crossings: cell (%d, %d) got %d expected %d" % [c[0], c[1], got, c[2]])
			return 1
	return 0

func _chunk_start(key: Vector2i) -> Vector2:
	return Vector2(key.x * 3 * _plan.lot_width, key.y * 4 * _plan.lot_length)

# Section coordinates of a chunk-local vertex.
func _section_xz(key: Vector2i, v: Vector3) -> Vector2:
	return _chunk_start(key) + Vector2(atan2(v.y, v.x) * RADIUS, v.z)

func _raised_chunk() -> Vector2i:
	# The chunk with the highest grid point: surely dressed with relief.
	var best := Vector2i.ZERO
	var highest := 0.0
	for along in range(20):
		for around in range(16):
			for row in range(along * 20, along * 20 + 21, 5):
				for column in range(around * 15, around * 15 + 16, 5):
					if _plan.grid_height(column, row) > highest:
						highest = _plan.grid_height(column, row)
						best = Vector2i(around, along)
	return best

func _check_ground_heights(test_name: String, plan, key: Vector2i, chunk: Node) -> int:
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(vertices.size()):
				var v: Vector3 = vertices[i]
				var at := Vector2(key.x * 3 * plan.lot_width, key.y * 4 * plan.lot_length) + Vector2(atan2(v.y, v.x) * RADIUS, v.z)
				var expected: float = RADIUS - plan.height_at(at.x, at.y)
				if absf(Vector2(v.x, v.y).length() - expected) > 0.001 or normals[i].dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
					print("FAIL %s: vertex %s is %.3f from the axis (expected %.3f), normal %s" % [test_name, v, Vector2(v.x, v.y).length(), expected, normals[i]])
					return 1
	return 0

func _test_ground_vertices_at_their_height_facing_the_axis() -> int:
	var result := 0
	for key in [_find_chunk(SectionPlan.Zone.WATER, true), _raised_chunk()]:
		var chunk := _dress(key)
		result = maxi(result, _check_ground_heights("_test_ground_vertices_at_their_height_facing_the_axis", _plan, key, chunk))
		chunk.free()
	return result

# Area of the mesh pushed back onto the cylinder: the relief lifts vertices
# toward the axis, but the patches still tile the chunk once.
func _projected_area(mesh: Mesh) -> float:
	var area := 0.0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var flat := PackedVector3Array()
		for v in vertices:
			var r := Vector2(v.x, v.y).length()
			flat.append(Vector3(v.x * RADIUS / r, v.y * RADIUS / r, v.z))
		for t in range(0, indices.size(), 3):
			var a: Vector3 = flat[indices[t]]
			area += (flat[indices[t + 1]] - a).cross(flat[indices[t + 2]] - a).length() * 0.5
	return area

func _test_ground_area_is_the_chunk_area() -> int:
	# A mosaic with no gaps and no overlaps covers exactly the chunk (chords
	# are ~0.01% shorter than arcs). An overlap adds area; a gap removes it.
	var result := 0
	for key in [_find_chunk(SectionPlan.Zone.WATER, true), _find_chunk(SectionPlan.Zone.TOWN, true), _find_chunk(SectionPlan.Zone.CITY, true), _raised_chunk()]:
		var chunk := _dress(key)
		var area := 0.0
		for mesh: Mesh in _ground_meshes(chunk):
			area += _projected_area(mesh)
		var expected: float = 3.0 * _plan.lot_width * 4.0 * _plan.lot_length
		if absf(area - expected) > expected * 0.001:
			print("FAIL _test_ground_area_is_the_chunk_area: chunk %s covers %.1f m2, expected %.1f" % [key, area, expected])
			result = 1
		chunk.free()
	return result

func _test_flat_plan_keeps_the_level_zero_mosaic() -> int:
	# The same plan with no heights: the old path, every vertex at the radius,
	# fewer vertices than the same chunk dressed with relief.
	var flat = SectionGenerator.generate(42, RADIUS, 20000.0)
	flat.heights = PackedFloat32Array()
	var key := _raised_chunk()
	var chunk := StaticBody3D.new()
	_dressing.dress_chunk(chunk, flat, key.x, key.y, _groups.get(key, []))
	var result := _check_ground_heights("_test_flat_plan_keeps_the_level_zero_mosaic", flat, key, chunk)
	var raised := _dress(key)
	var flat_vertices := 0
	var raised_vertices := 0
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			flat_vertices += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for mesh: Mesh in _ground_meshes(raised):
		for s in range(mesh.get_surface_count()):
			raised_vertices += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("  chunk %s: %d vertices flat, %d with relief" % [key, flat_vertices, raised_vertices])
	if raised_vertices <= flat_vertices:
		print("FAIL _test_flat_plan_keeps_the_level_zero_mosaic: the relief chunk is not split finer than the flat one")
		result = 1
	chunk.free()
	raised.free()
	return result

func _test_relief_normals_lean_downhill() -> int:
	var key := _raised_chunk()
	var chunk := _dress(key)
	var result := 0
	var checked := 0
	var surface: Mesh = (chunk.get_node("Surface") as MeshInstance3D).mesh
	for s in range(surface.get_surface_count()):
		var arrays: Array = surface.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			var v: Vector3 = vertices[i]
			var at := _section_xz(key, v)
			var slope: Vector2 = _plan.slope_at(at.x, at.y)
			var angle := atan2(v.y, v.x)
			var around := Vector3(-sin(angle), cos(angle), 0.0)
			# Uphill toward +x: the face turns toward -x (and likewise for z).
			if (slope.x > 0.1 and normals[i].dot(around) >= 0.0) or (slope.x < -0.1 and normals[i].dot(around) <= 0.0) or (slope.y > 0.1 and normals[i].z >= 0.0) or (slope.y < -0.1 and normals[i].z <= 0.0):
				print("FAIL _test_relief_normals_lean_downhill: normal %s at %s with slope %s" % [normals[i], v, slope])
				result = 1
				break
			if slope.length() > 0.1:
				checked += 1
	if checked == 0:
		print("FAIL _test_relief_normals_lean_downhill: no sloped vertex in chunk %s" % key)
		result = 1
	chunk.free()
	return result

func _test_relief_chunk_has_no_cracks() -> int:
	# Every triangle edge used by only one triangle must lie on the chunk's
	# border: inside, every edge is shared by exactly two triangles, even
	# between a 6 m road band and a 250 m field.
	var key := _raised_chunk()
	var chunk := _dress(key)
	var edges := {}
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in range(0, indices.size(), 3):
				for e in range(3):
					var a: Vector3 = vertices[indices[t + e]].snappedf(0.001)
					var b: Vector3 = vertices[indices[t + (e + 1) % 3]].snappedf(0.001)
					var edge_key := [a, b] if str(a) < str(b) else [b, a]
					edges[edge_key] = edges.get(edge_key, 0) + 1
	var chunk_width: float = 3.0 * _plan.lot_width
	var chunk_length: float = 4.0 * _plan.lot_length
	var result := 0
	for edge_key in edges:
		if edges[edge_key] != 1:
			continue
		var on_border := true
		for p: Vector3 in edge_key:
			var x: float = atan2(p.y, p.x) * RADIUS
			var at_side: bool = absf(x) < 0.01 or absf(x - chunk_width) < 0.01
			var at_end: bool = absf(p.z) < 0.01 or absf(p.z - chunk_length) < 0.01
			on_border = on_border and (at_side or at_end)
		if not on_border:
			print("FAIL _test_relief_chunk_has_no_cracks: open edge %s inside chunk %s" % [edge_key, key])
			result = 1
			break
	chunk.free()
	return result

func _test_raised_ground_colours() -> int:
	var result := 0
	if not TerrainDressing.relief_color(10.0, 0.1).is_equal_approx(TerrainDressing.FOREST_COLOR) or not TerrainDressing.relief_color(700.0, 0.1).is_equal_approx(TerrainDressing.ROCK_COLOR) or not TerrainDressing.relief_color(10.0, 1.4).is_equal_approx(TerrainDressing.ROCK_COLOR):
		print("FAIL _test_raised_ground_colours: forest low and gentle, rock high or steep")
		result = 1
	# Inside a hill or mountain lot, each vertex takes the colour of its
	# height and slope.
	var key := _find_chunk(SectionPlan.Zone.HILL, true)
	var chunk := _dress(key)
	var surface: Mesh = (chunk.get_node("Surface") as MeshInstance3D).mesh
	var checked := 0
	for s in range(surface.get_surface_count()):
		var arrays: Array = surface.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in range(vertices.size()):
			var at := _section_xz(key, vertices[i])
			var lot := Vector2i(floori(at.x / _plan.lot_width), floori(at.y / _plan.lot_length))
			var inside: bool = fposmod(at.x, _plan.lot_width) > 1.0 and fposmod(at.x, _plan.lot_width) < _plan.lot_width - 1.0 and fposmod(at.y, _plan.lot_length) > 1.0 and fposmod(at.y, _plan.lot_length) < _plan.lot_length - 1.0
			if not inside or not SectionPlan.is_raised(_plan.zone_at(lot.x, lot.y)):
				continue
			var expected: Color = TerrainDressing.relief_color(_plan.height_at(at.x, at.y), _plan.slope_at(at.x, at.y).length())
			if absf(colors[i].r - expected.r) > 1.0 / 255.0 or absf(colors[i].g - expected.g) > 1.0 / 255.0 or absf(colors[i].b - expected.b) > 1.0 / 255.0:
				print("FAIL _test_raised_ground_colours: vertex %s coloured %s, expected %s" % [vertices[i], colors[i], expected])
				result = 1
				break
			checked += 1
	if checked == 0:
		print("FAIL _test_raised_ground_colours: no raised vertex found in chunk %s" % key)
		result = 1
	chunk.free()
	return result

# A chunk as InteriorWorld builds it: a Collision node with the shared shape.
func _chunk_with_shared_shape(shared: Shape3D) -> StaticBody3D:
	var chunk := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shared
	chunk.add_child(collision)
	return chunk

# Winding sign of a triangle: positive when its front (Godot's clockwise
# order, as the ground mesh uses) faces the axis.
func _faces_axis(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (c - a).cross(b - a).dot(Vector3(-a.x, -a.y, 0.0))

func _test_relief_chunk_collides_on_its_height_grid() -> int:
	# Its own trimesh on the height grid's points (15 x 20 cells, two
	# triangles each): every corner on the ground, wound like the mesh, and
	# covering the chunk once. The shared level-0 shape stays for flat chunks.
	var shared := ConcavePolygonShape3D.new()
	var key := _raised_chunk()
	var raised := _chunk_with_shared_shape(shared)
	_dressing.dress_chunk(raised, _plan, key.x, key.y, _groups.get(key, []))
	var result := 0
	var shape: Shape3D = (raised.get_node("Collision") as CollisionShape3D).shape
	var faces := PackedVector3Array() if not (shape is ConcavePolygonShape3D) else (shape as ConcavePolygonShape3D).get_faces()
	if shape == shared or faces.size() != 15 * 20 * 6:
		print("FAIL _test_relief_chunk_collides_on_its_height_grid: shape %s with %d face corners, expected %d" % [shape, faces.size(), 15 * 20 * 6])
		result = 1
	var mesh_arrays: Array = ((raised.get_node("Surface") as MeshInstance3D).mesh as Mesh).surface_get_arrays(0)
	var mesh_vertices: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	var mesh_indices: PackedInt32Array = mesh_arrays[Mesh.ARRAY_INDEX]
	var mesh_sign := signf(_faces_axis(mesh_vertices[mesh_indices[0]], mesh_vertices[mesh_indices[1]], mesh_vertices[mesh_indices[2]]))
	var area := 0.0
	for t in range(0, faces.size(), 3):
		for k in range(3):
			var v: Vector3 = faces[t + k]
			var at := _section_xz(key, v)
			if absf(Vector2(v.x, v.y).length() - (RADIUS - _plan.height_at(at.x, at.y))) > 0.001:
				print("FAIL _test_relief_chunk_collides_on_its_height_grid: corner %s off the ground" % v)
				raised.free()
				return 1
		if signf(_faces_axis(faces[t], faces[t + 1], faces[t + 2])) != mesh_sign:
			print("FAIL _test_relief_chunk_collides_on_its_height_grid: triangle %d wound the other way from the mesh" % (t / 3))
			raised.free()
			return 1
		var flat := []
		for k in range(3):
			var v: Vector3 = faces[t + k]
			var r := Vector2(v.x, v.y).length()
			flat.append(Vector3(v.x * RADIUS / r, v.y * RADIUS / r, v.z))
		area += ((flat[1] - flat[0]) as Vector3).cross(flat[2] - flat[0]).length() * 0.5
	var expected: float = 3.0 * _plan.lot_width * 4.0 * _plan.lot_length
	if absf(area - expected) > expected * 0.001:
		print("FAIL _test_relief_chunk_collides_on_its_height_grid: collision covers %.1f m2, expected %.1f" % [area, expected])
		result = 1
	# The same chunk from a plan with no heights keeps the shared shape.
	var flat_plan = SectionGenerator.generate(42, RADIUS, 20000.0)
	flat_plan.heights = PackedFloat32Array()
	var level := _chunk_with_shared_shape(shared)
	_dressing.dress_chunk(level, flat_plan, key.x, key.y, _groups.get(key, []))
	if (level.get_node("Collision") as CollisionShape3D).shape != shared:
		print("FAIL _test_relief_chunk_collides_on_its_height_grid: a flat chunk lost the shared shape")
		result = 1
	raised.free()
	level.free()
	return result

# Height of the collision surface at section (x, z): the grid cell's two
# triangles, split along its (x1, z0)-(x0, z1) diagonal as the collision is.
func _collision_height(x: float, z: float) -> float:
	var step: Vector2 = _plan.height_step()
	var gx: float = fposmod(x, _plan.circumference()) / step.x
	var gz: float = clampf(z / step.y, 0.0, 400.0)
	var column := mini(floori(gx), 239)
	var row := mini(floori(gz), 399)
	var fx: float = gx - column
	var fz: float = gz - row
	var h00: float = _plan.grid_height(column, row)
	var h10: float = _plan.grid_height(column + 1, row)
	var h01: float = _plan.grid_height(column, row + 1)
	var h11: float = _plan.grid_height(column + 1, row + 1)
	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)

# Distance from chunk-local point `p` to the plane of the collision triangle
# under it (built like TerrainDressing.relief_collision_faces).
func _collision_plane_gap(key: Vector2i, p: Vector3) -> float:
	var step: Vector2 = _plan.height_step()
	var start := _chunk_start(key)
	var at := _section_xz(key, p)
	var column := floori(at.x / step.x)
	var row := clampi(floori(at.y / step.y), 0, 399)
	var fx: float = at.x / step.x - column
	var fz: float = at.y / step.y - row
	var cells: Array = [Vector2i(column, row), Vector2i(column + 1, row), Vector2i(column, row + 1)] if fx + fz <= 1.0 else [Vector2i(column + 1, row), Vector2i(column + 1, row + 1), Vector2i(column, row + 1)]
	var corners := []
	for cell: Vector2i in cells:
		var angle: float = (cell.x * step.x - start.x) / RADIUS
		var r: float = RADIUS - _plan.grid_height(cell.x, cell.y)
		corners.append(Vector3(cos(angle) * r, sin(angle) * r, cell.y * step.y - start.y))
	var normal: Vector3 = ((corners[1] - corners[0]) as Vector3).cross(corners[2] - corners[0]).normalized()
	return absf(normal.dot(p - corners[0]))

func _steepest_chunk() -> Vector2i:
	var best := Vector2i.ZERO
	var steepest := 0.0
	var step: Vector2 = _plan.height_step()
	for row in range(401):
		for column in range(240):
			var slope: float = _plan.slope_at(column * step.x, row * step.y).length()
			if slope > steepest:
				steepest = slope
				best = Vector2i(mini(column / 15, 15), mini(row / 20, 19))
	return best

func _test_drawn_ground_lies_on_its_collision() -> int:
	# The craft stops on the collision: every drawn vertex must sit on it,
	# on the steepest ground too (bilinear vertices strayed up to 7 m from
	# the cell's two collision triangles).
	# Triangle centres too, against the plane of the collision triangle
	# under them: a drawn quad across a cell's fold strayed up to 5.5 m. The
	# collision is flat between grid points 52 m apart round the curve, so
	# drawn points between them sit up to its chord's sag (~0.3 m) above it.
	var result := 0
	var worst := 0.0
	var worst_centre := 0.0
	for key in [_raised_chunk(), _steepest_chunk()]:
		var chunk := _dress(key)
		for mesh: Mesh in _ground_meshes(chunk):
			for s in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(s)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for v: Vector3 in vertices:
					var at := _section_xz(key, v)
					worst = maxf(worst, absf(Vector2(v.x, v.y).length() - (RADIUS - _collision_height(at.x, at.y))))
				for t in range(0, indices.size(), 3):
					var c: Vector3 = (vertices[indices[t]] + vertices[indices[t + 1]] + vertices[indices[t + 2]]) / 3.0
					worst_centre = maxf(worst_centre, _collision_plane_gap(key, c))
		chunk.free()
	print("  drawn ground off the collision surface: vertices %.3f m, triangle centres %.3f m" % [worst, worst_centre])
	if worst > 0.01 or worst_centre > 0.35:
		print("FAIL _test_drawn_ground_lies_on_its_collision: vertices %.3f m, triangle centres %.3f m off the collision surface" % [worst, worst_centre])
		result = 1
	return result

# Section (x, radius) of a chunk's vertices at chunk-local z, snapped.
func _border_points(key: Vector2i, chunk: Node, z: float) -> Dictionary:
	var points := {}
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				if absf(v.z - z) < 0.001:
					points[Vector2(_section_xz(key, v).x, Vector2(v.x, v.y).length()).snappedf(0.01)] = true
	return points

func _test_chunks_along_share_their_border_vertices() -> int:
	# A flat chunk next to one with relief: the same vertices on the border
	# they share, or a slit opens between their edges (chords of up to 87 m
	# on the flat side against ~50 m on the other left 0.44 m gaps).
	var flat_key := Vector2i(-1, -1)
	for along in range(19):
		for around in range(16):
			if not _plan.chunk_has_relief(around, along) and _plan.chunk_has_relief(around, along + 1):
				flat_key = Vector2i(around, along)
	if flat_key.x < 0:
		print("FAIL _test_chunks_along_share_their_border_vertices: no flat chunk next to a raised one in section 42")
		return 1
	var next := flat_key + Vector2i(0, 1)
	var a := _dress(flat_key)
	var b := _dress(next)
	var chunk_length: float = 4.0 * _plan.lot_length
	var mine := _border_points(flat_key, a, chunk_length)
	var theirs := _border_points(next, b, 0.0)
	var result := 0
	if mine.keys() != theirs.keys() and not _same_keys(mine, theirs):
		print("FAIL _test_chunks_along_share_their_border_vertices: chunks %s and %s have %d and %d distinct border vertices" % [flat_key, next, mine.size(), theirs.size()])
		result = 1
	a.free()
	b.free()
	return result

func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
	return true

var _worker_ground := []

func _build_ground_on_worker(key: Vector2i) -> void:
	_worker_ground = TerrainDressing.build_ground(_plan, key.x, key.y)

func _test_ground_built_on_a_worker_matches_one_built_in_place() -> int:
	# The heavy vertex work runs on worker threads (InteriorWorld); the node
	# work stays on the main thread. Same mesh and collision either way.
	var key := _raised_chunk()
	var task := WorkerThreadPool.add_task(_build_ground_on_worker.bind(key))
	WorkerThreadPool.wait_for_task_completion(task)
	var from_worker := StaticBody3D.new()
	_dressing.dress_chunk(from_worker, _plan, key.x, key.y, _groups.get(key, []), _worker_ground)
	var in_place := _dress(key)
	var result := 0
	var a: Array = _ground_meshes(from_worker)
	var b: Array = _ground_meshes(in_place)
	if a.size() != b.size() or a.is_empty():
		print("FAIL _test_ground_built_on_a_worker_matches_one_built_in_place: %d ground meshes from the worker, %d in place" % [a.size(), b.size()])
		result = 1
	else:
		for m in range(a.size()):
			for s in range((a[m] as Mesh).get_surface_count()):
				if (a[m] as Mesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX] != (b[m] as Mesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					print("FAIL _test_ground_built_on_a_worker_matches_one_built_in_place: surface %d of mesh %d differs" % [s, m])
					result = 1
	if from_worker.get_node_or_null("Collision") == null:
		print("FAIL _test_ground_built_on_a_worker_matches_one_built_in_place: no collision from the worker's ground")
		result = 1
	from_worker.free()
	in_place.free()
	return result

func _test_water_only_where_the_plan_has_lakes() -> int:
	var wet := _dress(_find_chunk(SectionPlan.Zone.WATER, true))
	var dry := _dress(_find_chunk(SectionPlan.Zone.WATER, false))
	var result := 0
	if wet.get_node_or_null("Water") == null or dry.get_node_or_null("Water") != null:
		print("FAIL _test_water_only_where_the_plan_has_lakes: water node present in the dry chunk or missing in the wet one")
		result = 1
	if dry.get_node_or_null("Surface") == null:
		print("FAIL _test_water_only_where_the_plan_has_lakes: dry chunk has no Surface")
		result = 1
	wet.free()
	dry.free()
	return result

# Vertex colours are stored with 8 bits per channel: compare within 1/255.
func _has_color(mesh: Mesh, color: Color) -> bool:
	for s in range(mesh.get_surface_count()):
		for c: Color in mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]:
			if absf(c.r - color.r) <= 1.0 / 255.0 and absf(c.g - color.g) <= 1.0 / 255.0 and absf(c.b - color.b) <= 1.0 / 255.0:
				return true
	return false

func _test_road_colours_where_the_plan_has_roads() -> int:
	# A town chunk has streets; every chunk border that is not by a lake has a
	# main road, so a dry chunk shows the main-road colour.
	var chunk := _dress(_find_chunk(SectionPlan.Zone.TOWN, true))
	var result := 0
	var surface: Mesh = (chunk.get_node("Surface") as MeshInstance3D).mesh
	if not _has_color(surface, TerrainDressing.STREET_COLOR) or not _has_color(surface, TerrainDressing.MAIN_ROAD_COLOR):
		print("FAIL _test_road_colours_where_the_plan_has_roads: town chunk lacks street or main-road colour")
		result = 1
	chunk.free()
	return result

func _busiest_chunk() -> Vector2i:
	var best := Vector2i.ZERO
	var most := 0
	for key in _groups:
		if _groups[key].size() > most:
			most = _groups[key].size()
			best = key
	return best

func _test_building_transform_stands_on_the_wall_facing_the_axis() -> int:
	var size := Vector3(20.0, 60.0, 30.0)
	var x := 700.0
	var xform: Transform3D = TerrainDressing.building_transform(RADIUS, x, 400.0, size)
	var angle := x / RADIUS
	var up := Vector3(-cos(angle), -sin(angle), 0.0)
	var base: Vector3 = xform * Vector3(0.0, -0.5, 0.0)
	var result := 0
	if not base.is_equal_approx(Vector3(cos(angle) * RADIUS, sin(angle) * RADIUS, 400.0)):
		print("FAIL _test_building_transform_stands_on_the_wall_facing_the_axis: base at %s" % base)
		result = 1
	if not xform.basis.y.normalized().is_equal_approx(up) or not xform.basis.z.normalized().is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		print("FAIL _test_building_transform_stands_on_the_wall_facing_the_axis: up %s along %s" % [xform.basis.y.normalized(), xform.basis.z.normalized()])
		result = 1
	if not Vector3(xform.basis.x.length(), xform.basis.y.length(), xform.basis.z.length()).is_equal_approx(size) or xform.basis.determinant() <= 0.0:
		print("FAIL _test_building_transform_stands_on_the_wall_facing_the_axis: scale %s (mirrored: %s)" % [Vector3(xform.basis.x.length(), xform.basis.y.length(), xform.basis.z.length()), xform.basis.determinant() <= 0.0])
		result = 1
	return result

# The chunk's buildings of `style`, in index order.
func _indices_of_style(indices: Array, style: int) -> Array:
	return indices.filter(func(b: int) -> bool: return _plan.building_style[b] == style)

func _test_chunk_buildings_match_the_plan() -> int:
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	var result := 0
	var group := chunk.get_node_or_null("Buildings")
	if group == null or chunk.get_shape_owners().size() != indices.size():
		print("FAIL _test_chunk_buildings_match_the_plan: chunk %s has no Buildings node or %d colliders for %d buildings" % [key, chunk.get_shape_owners().size(), indices.size()])
		chunk.free()
		return 1
	var total := 0
	for style in range(SectionPlan.Style.size()):
		var expected: int = _indices_of_style(indices, style).size()
		var node := group.get_node_or_null(BuildingShapes.NAMES[style]) as MultiMeshInstance3D
		if expected == 0:
			if node != null:
				print("FAIL _test_chunk_buildings_match_the_plan: %s drawn with no building of that shape" % BuildingShapes.NAMES[style])
				result = 1
			continue
		if node == null or node.multimesh.instance_count != expected or node.multimesh.mesh != BuildingShapes.mesh(style) or not node.multimesh.use_colors or not node.multimesh.use_custom_data:
			print("FAIL _test_chunk_buildings_match_the_plan: %s expected %d instances of its mesh with colours and custom data" % [BuildingShapes.NAMES[style], expected])
			result = 1
			continue
		if node.visibility_range_end != TerrainDressing.BUILDING_VISIBILITY_END or node.material_override != _dressing.building_material:
			print("FAIL _test_chunk_buildings_match_the_plan: %s visibility %f or wrong material" % [BuildingShapes.NAMES[style], node.visibility_range_end])
			result = 1
		total += node.multimesh.instance_count
	if total != indices.size():
		print("FAIL _test_chunk_buildings_match_the_plan: %d instances for %d buildings" % [total, indices.size()])
		result = 1
	chunk.free()
	return result

func _directions() -> Array:
	var dirs := []
	for x in [-1.0, 0.0, 1.0]:
		for y in [-1.0, 0.0, 1.0]:
			for z in [-1.0, 0.0, 1.0]:
				if x != 0.0 or y != 0.0 or z != 0.0:
					dirs.append(Vector3(x, y, z).normalized())
	return dirs

func _test_building_colliders_match_the_drawn_buildings() -> int:
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	# Headless runs cannot read MultiMesh instances back; compare with the
	# transforms the dressing draws them with.
	var drawn_list := TerrainDressing.chunk_building_transforms(_plan, key.x, key.y, indices)
	var owners: PackedInt32Array = chunk.get_shape_owners()
	var result := 0
	for k in range(indices.size()):
		var b: int = indices[k]
		var drawn: Transform3D = drawn_list[k]
		var collider: Transform3D = chunk.shape_owner_get_transform(owners[k])
		var shape := chunk.shape_owner_get_shape(owners[k], 0) as ConvexPolygonShape3D
		if not collider.is_equal_approx(drawn.orthonormalized()) or shape == null:
			print("FAIL _test_building_colliders_match_the_drawn_buildings: building %d collider %s (%s) vs drawn %s" % [b, collider, shape, drawn])
			result = 1
			break
		# Every drawn vertex, in the collider's frame, lies within the hull.
		var size: Vector3 = _plan.building_size[b]
		var vertices: PackedVector3Array = BuildingShapes.mesh(_plan.building_style[b]).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for d: Vector3 in _directions():
			var hull_reach := -INF
			for p in shape.points:
				hull_reach = maxf(hull_reach, p.dot(d))
			var mesh_reach := -INF
			for v in vertices:
				mesh_reach = maxf(mesh_reach, (v * size).dot(d))
			if hull_reach < mesh_reach - 1e-3:
				print("FAIL _test_building_colliders_match_the_drawn_buildings: building %d collider short by %f toward %s" % [b, mesh_reach - hull_reach, d])
				result = 1
				break
		if result:
			break
	chunk.free()
	return result

func _test_building_bounds_cover_the_tallest_building() -> int:
	# Headless renderers report no MultiMesh bounds; custom_aabb must hold them.
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	var xforms := TerrainDressing.chunk_building_transforms(_plan, key.x, key.y, indices)
	var result := 0
	for k in range(indices.size()):
		var node: MultiMeshInstance3D = chunk.get_node("Buildings/" + BuildingShapes.NAMES[_plan.building_style[indices[k]]])
		var top: Vector3 = xforms[k] * Vector3(0.0, 0.5, 0.0)
		if not node.custom_aabb.has_point(top):
			print("FAIL _test_building_bounds_cover_the_tallest_building: top %s outside %s" % [top, node.custom_aabb])
			result = 1
			break
	chunk.free()
	return result

func _test_building_custom_data_carries_the_look() -> int:
	var result := 0
	for b in range(0, _plan.building_count(), 97):
		var custom: Color = TerrainDressing.building_custom(_plan, b)
		if not is_equal_approx(custom.r, _plan.building_facade[b]) or not is_equal_approx(custom.g, _plan.building_accent[b]) or not is_equal_approx(custom.b, _plan.building_lit[b]) or custom.a < 0.0 or custom.a >= 1.0:
			print("FAIL _test_building_custom_data_carries_the_look: building %d custom %s" % [b, custom])
			result = 1
			break
	return result

func _test_building_shader_reads_each_building() -> int:
	# Headless has no real renderer: check the code; Task 4 renders it too.
	var material = _dressing.building_material
	if not (material is ShaderMaterial):
		print("FAIL _test_building_shader_reads_each_building: building material is %s" % material.get_class())
		return 1
	var code: String = (material as ShaderMaterial).shader.code
	var result := 0
	for needle in ["INSTANCE_CUSTOM", "abs(local_normal.y) >= 0.5", "atan(local_position.z, local_position.x)", "ACCENTS[", "EMISSION = accent * glow"]:
		if not code.contains(needle):
			print("FAIL _test_building_shader_reads_each_building: shader lacks '%s'" % needle)
			result = 1
	if (material as ShaderMaterial).get_shader_parameter("glow_energy") == null:
		print("FAIL _test_building_shader_reads_each_building: glow_energy not set")
		result = 1
	return result

func _test_released_chunks_drop_only_the_shapes_nobody_uses() -> int:
	# Convex shapes are cached by (style, size) and shared between chunks.
	# Releasing a chunk drops the shapes no other chunk uses; built chunks
	# keep theirs. (Clearing the whole cache made loading rebuild thousands
	# of shapes and pushed frames past 50 ms.)
	var dressing = TerrainDressing.new()
	var keys := _groups.keys()
	var first := StaticBody3D.new()
	var second := StaticBody3D.new()
	dressing.dress_chunk(first, _plan, keys[0].x, keys[0].y, _groups[keys[0]])
	dressing.dress_chunk(second, _plan, keys[1].x, keys[1].y, _groups[keys[1]])
	var second_keys := {}
	for key in second.get_meta("shape_keys"):
		second_keys[key] = true
	dressing.release_chunk(first)
	var result := 0
	if dressing._convex_shapes.size() != second_keys.size():
		print("FAIL _test_released_chunks_drop_only_the_shapes_nobody_uses: %d shapes cached after releasing the first chunk, the second uses %d" % [dressing._convex_shapes.size(), second_keys.size()])
		result = 1
	for owner_id in first.get_shape_owners():
		if first.shape_owner_get_shape(owner_id, 0) == null:
			print("FAIL _test_released_chunks_drop_only_the_shapes_nobody_uses: a built building lost its collider")
			result = 1
			break
	dressing.release_chunk(second)
	if dressing._convex_shapes.size() != 0:
		print("FAIL _test_released_chunks_drop_only_the_shapes_nobody_uses: %d shapes left after releasing both chunks" % dressing._convex_shapes.size())
		result = 1
	first.free()
	second.free()
	return result
