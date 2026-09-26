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
	failures += _test_ground_vertices_at_level_zero_facing_the_axis()
	failures += _test_ground_area_is_the_chunk_area()
	failures += _test_water_only_where_the_plan_has_lakes()
	failures += _test_road_colours_where_the_plan_has_roads()
	failures += _test_building_transform_stands_on_the_wall_facing_the_axis()
	failures += _test_chunk_buildings_match_the_plan()
	failures += _test_building_colliders_match_the_drawn_buildings()
	failures += _test_building_bounds_cover_the_tallest_building()
	failures += _test_building_custom_data_carries_the_look()
	failures += _test_building_shader_reads_each_building()
	failures += _test_clearing_the_shape_cache_keeps_built_chunks_whole()

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

func _test_ground_vertices_at_level_zero_facing_the_axis() -> int:
	var chunk := _dress(_find_chunk(SectionPlan.Zone.WATER, true))
	var result := 0
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(vertices.size()):
				var v: Vector3 = vertices[i]
				if absf(Vector2(v.x, v.y).length() - RADIUS) > 0.001 or normals[i].dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
					print("FAIL _test_ground_vertices_at_level_zero_facing_the_axis: vertex %s normal %s" % [v, normals[i]])
					chunk.free()
					return 1
	chunk.free()
	return result

func _triangle_area(mesh: Mesh) -> float:
	var area := 0.0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[t]]
			area += (vertices[indices[t + 1]] - a).cross(vertices[indices[t + 2]] - a).length() * 0.5
	return area

func _test_ground_area_is_the_chunk_area() -> int:
	# A mosaic with no gaps and no overlaps covers exactly the chunk (chords
	# are ~0.01% shorter than arcs). An overlap adds area; a gap removes it.
	var result := 0
	for key in [_find_chunk(SectionPlan.Zone.WATER, true), _find_chunk(SectionPlan.Zone.TOWN, true), _find_chunk(SectionPlan.Zone.CITY, true)]:
		var chunk := _dress(key)
		var area := 0.0
		for mesh: Mesh in _ground_meshes(chunk):
			area += _triangle_area(mesh)
		var expected: float = 3.0 * _plan.lot_width * 4.0 * _plan.lot_length
		if absf(area - expected) > expected * 0.001:
			print("FAIL _test_ground_area_is_the_chunk_area: chunk %s covers %.1f m2, expected %.1f" % [key, area, expected])
			result = 1
		chunk.free()
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

func _test_clearing_the_shape_cache_keeps_built_chunks_whole() -> int:
	# Convex shapes are cached by (style, size): thousands per section, so
	# the interior clears the cache as sections go. Chunks already built keep
	# their own shapes.
	var dressing = TerrainDressing.new()
	var chunk := StaticBody3D.new()
	var key := _busiest_chunk()
	dressing.dress_chunk(chunk, _plan, key.x, key.y, _groups[key])
	var cached: int = dressing._convex_shapes.size()
	dressing.clear_shape_cache()
	var result := 0
	if cached == 0 or dressing._convex_shapes.size() != 0:
		print("FAIL _test_clearing_the_shape_cache_keeps_built_chunks_whole: %d cached, %d left after clearing" % [cached, dressing._convex_shapes.size()])
		result = 1
	for owner_id in chunk.get_shape_owners():
		if chunk.shape_owner_get_shape(owner_id, 0) == null:
			print("FAIL _test_clearing_the_shape_cache_keeps_built_chunks_whole: a built building lost its collider")
			result = 1
			break
	chunk.free()
	return result
