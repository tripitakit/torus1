extends SceneTree

const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")
const TerrainDressing = preload("res://scripts/terrain_dressing.gd")

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
