extends RefCounted

# Turns a section plan into geometry, one interior terrain chunk at a time,
# in the chunk's own frame (InteriorWorld turns each chunk about Z and shifts
# it along Z). The ground is a mosaic at level 0 with no overlapping layers:
# with the interior camera (near 0.2 m, far 60 km) the depth buffer cannot
# separate surfaces less than a metre apart at 2 km, so layers would flicker.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const CROP_COLORS := [
	Color(0.85, 0.72, 0.3),   # wheat
	Color(0.25, 0.45, 0.15),  # corn
	Color(0.95, 0.75, 0.1),   # sunflower
	Color(0.55, 0.45, 0.8),   # lavender
	Color(0.5, 0.75, 0.35),   # rice
	Color(0.45, 0.55, 0.3),   # pasture
]
const TOWN_GROUND_COLOR := Color(0.62, 0.6, 0.55)
const CITY_GROUND_COLOR := Color(0.5, 0.5, 0.52)
const MAIN_ROAD_COLOR := Color(0.2, 0.2, 0.22)
const STREET_COLOR := Color(0.32, 0.32, 0.34)
const WATER_COLOR := Color(0.12, 0.32, 0.5)
const WINDOW_SPACING := 4.0
const WINDOW_GLOW_COLOR := Color(1.0, 0.85, 0.55)
const BUILDING_VISIBILITY_END := 12000.0

# Vertex data for one mesh surface. Kept as a class so its packed arrays are
# mutated in place (packed arrays are values).
class MeshArrays:
	const ROW_SPACING := 5.0
	# Longest arc of one flat quad: it strays at most ~0.5 m from the curve.
	const ARC_STEP := 90.0

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return vertices.is_empty()

	# A rectangle of the inner wall, x0..x1 around (arc metres) and z0..z1
	# along, facing the axis. UVs count filari: along z or around.
	func add_patch(radius: float, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool) -> void:
		var steps: int = maxi(1, ceili((x1 - x0) / ARC_STEP))
		var base: int = vertices.size()
		for s in range(steps + 1):
			var x: float = lerpf(x0, x1, float(s) / steps)
			var angle: float = x / radius
			var inward := Vector3(-cos(angle), -sin(angle), 0.0)
			for z: float in [z0, z1]:
				vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, z))
				normals.append(inward)
				colors.append(color)
				uvs.append(Vector2(x, z) / ROW_SPACING if rows_along else Vector2(z, x) / ROW_SPACING)
		# Same winding as the interior terrain: the front faces the axis.
		for s in range(steps):
			var p00: int = base + s * 2
			indices.append_array(PackedInt32Array([p00, p00 + 2, p00 + 1, p00 + 2, p00 + 3, p00 + 1]))

	func to_arrays() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays

var field_material: StandardMaterial3D
var paved_material: StandardMaterial3D
var water_material: StandardMaterial3D
var building_material: StandardMaterial3D
var _box_mesh := BoxMesh.new()
var _box_shapes := {}

func _init() -> void:
	field_material = StandardMaterial3D.new()
	field_material.vertex_color_use_as_albedo = true
	field_material.albedo_texture = _stripe_texture()
	field_material.roughness = 0.95
	paved_material = StandardMaterial3D.new()
	paved_material.vertex_color_use_as_albedo = true
	paved_material.roughness = 0.9
	water_material = StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_material.roughness = 0.1
	water_material.metallic = 0.3
	# Windows projected in world space: the same window size on a house and a
	# tower (a unit box stretched per building would stretch its UVs). The
	# instance colour tints the walls; a mask lights the panes.
	building_material = StandardMaterial3D.new()
	building_material.vertex_color_use_as_albedo = true
	building_material.albedo_texture = _window_texture(false)
	building_material.uv1_triplanar = true
	building_material.uv1_world_triplanar = true
	building_material.uv1_scale = Vector3.ONE / WINDOW_SPACING
	building_material.emission_enabled = true
	building_material.emission = WINDOW_GLOW_COLOR
	building_material.emission_energy_multiplier = 0.8
	building_material.emission_texture = _window_texture(true)
	building_material.roughness = 0.8

func dress_chunk(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, building_indices: Array) -> void:
	_build_ground(chunk, plan, chunk_around, chunk_along)
	if not building_indices.is_empty():
		_build_buildings(chunk, plan, chunk_around, chunk_along, building_indices)

# Which road a lot cell carries. The lot is split 3 x 3 by its edge roads:
# column 0 is the west band, 2 the east band; row 0 south, 2 north. The
# centre is never road; a corner is a crossing of its two edges' roads.
static func cell_road(column: int, row: int, west: int, east: int, south: int, north: int) -> int:
	var column_road: int = west if column == 0 else (east if column == 2 else SectionPlanScript.Road.NONE)
	var row_road: int = south if row == 0 else (north if row == 2 else SectionPlanScript.Road.NONE)
	if column == 1:
		return row_road
	if row == 1:
		return column_road
	return maxi(column_road, row_road)

func _build_ground(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int) -> void:
	var fields := MeshArrays.new()
	var paved := MeshArrays.new()
	var water := MeshArrays.new()
	for lot_x in range(SectionPlanScript.CHUNK_LOTS_AROUND):
		for lot_z in range(SectionPlanScript.CHUNK_LOTS_ALONG):
			var around: int = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND + lot_x
			var along: int = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG + lot_z
			var x0: float = lot_x * plan.lot_width
			var x1: float = x0 + plan.lot_width
			var z0: float = lot_z * plan.lot_length
			var z1: float = z0 + plan.lot_length
			var zone: int = plan.zone_at(around, along)
			if zone == SectionPlanScript.Zone.WATER:
				water.add_patch(plan.radius, x0, x1, z0, z1, WATER_COLOR, true)
				continue
			var west: int = plan.road_on_west(around, along)
			var east: int = plan.road_on_east(around, along)
			var south: int = plan.road_on_south(around, along)
			var north: int = plan.road_on_north(around, along)
			# Each road is split down its middle: half its width in each lot.
			var xs := [x0, x0 + SectionPlanScript.road_width(west) * 0.5, x1 - SectionPlanScript.road_width(east) * 0.5, x1]
			var zs := [z0, z0 + SectionPlanScript.road_width(south) * 0.5, z1 - SectionPlanScript.road_width(north) * 0.5, z1]
			var lot: int = plan.lot_index(around, along)
			for column in range(3):
				for row in range(3):
					var cx0: float = xs[column]
					var cx1: float = xs[column + 1]
					var cz0: float = zs[row]
					var cz1: float = zs[row + 1]
					if cx1 - cx0 < 0.001 or cz1 - cz0 < 0.001:
						continue
					var road := cell_road(column, row, west, east, south, north)
					if road == SectionPlanScript.Road.MAIN:
						paved.add_patch(plan.radius, cx0, cx1, cz0, cz1, MAIN_ROAD_COLOR, true)
					elif road == SectionPlanScript.Road.STREET:
						paved.add_patch(plan.radius, cx0, cx1, cz0, cz1, STREET_COLOR, true)
					elif zone == SectionPlanScript.Zone.FIELD:
						fields.add_patch(plan.radius, cx0, cx1, cz0, cz1, CROP_COLORS[plan.crops[lot]], plan.rows_along[lot] == 1)
					else:
						paved.add_patch(plan.radius, cx0, cx1, cz0, cz1, TOWN_GROUND_COLOR if zone == SectionPlanScript.Zone.TOWN else CITY_GROUND_COLOR, true)
	var surface_mesh := ArrayMesh.new()
	for part in [[fields, field_material], [paved, paved_material]]:
		var arrays: MeshArrays = part[0]
		if not arrays.is_empty():
			surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays.to_arrays())
			surface_mesh.surface_set_material(surface_mesh.get_surface_count() - 1, part[1])
	if surface_mesh.get_surface_count() > 0:
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.mesh = surface_mesh
		chunk.add_child(surface)
	if not water.is_empty():
		var water_mesh := ArrayMesh.new()
		water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water.to_arrays())
		var water_node := MeshInstance3D.new()
		water_node.name = "Water"
		water_node.mesh = water_mesh
		water_node.material_override = water_material
		chunk.add_child(water_node)

# One filare per repeat: a lighter band and a darker furrow.
static func _stripe_texture() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in range(16):
		var shade := 1.0 if x < 11 else 0.55
		for y in range(16):
			image.set_pixel(x, y, Color(shade, shade, shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

# A unit box scaled to size (width around, height, depth along), its base
# centred on the wall at (x, z) and its "up" toward the axis.
static func building_transform(radius: float, x: float, z: float, size: Vector3) -> Transform3D:
	var angle: float = x / radius
	var up := Vector3(-cos(angle), -sin(angle), 0.0)
	var around := Vector3(-sin(angle), cos(angle), 0.0)
	var base := Vector3(cos(angle) * radius, sin(angle) * radius, z)
	return Transform3D(Basis(around * size.x, up * size.y, Vector3(0.0, 0.0, size.z)), base + up * size.y * 0.5)

# The drawn transform of each listed building, in its chunk's frame. One
# source for both the MultiMesh and the colliders (headless test runs cannot
# read MultiMesh instances back: the dummy renderer stores none).
static func chunk_building_transforms(plan, chunk_around: int, chunk_along: int, indices: Array) -> Array[Transform3D]:
	var chunk_x0: float = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width
	var chunk_z0: float = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length
	var xforms: Array[Transform3D] = []
	for b: int in indices:
		xforms.append(building_transform(plan.radius, plan.building_x[b] - chunk_x0, plan.building_z[b] - chunk_z0, plan.building_size[b]))
	return xforms

func _build_buildings(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, indices: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _box_mesh
	multimesh.instance_count = indices.size()
	var xforms := chunk_building_transforms(plan, chunk_around, chunk_along, indices)
	var tallest := 0.0
	for k in range(indices.size()):
		var b: int = indices[k]
		var size: Vector3 = plan.building_size[b]
		var xform: Transform3D = xforms[k]
		multimesh.set_instance_transform(k, xform)
		multimesh.set_instance_color(k, plan.building_color[b])
		# Colliders straight on the chunk body: thousands of nodes would slow
		# docking down.
		var owner_id := chunk.create_shape_owner(chunk)
		chunk.shape_owner_add_shape(owner_id, _box_shape(size))
		chunk.shape_owner_set_transform(owner_id, xform.orthonormalized())
		tallest = maxf(tallest, size.y)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Buildings"
	instance.multimesh = multimesh
	instance.material_override = building_material
	instance.visibility_range_end = BUILDING_VISIBILITY_END
	instance.custom_aabb = _chunk_bounds(plan, tallest)
	chunk.add_child(instance)

# Boxes with the same (whole-metre) size share one shape.
func _box_shape(size: Vector3) -> BoxShape3D:
	var key := Vector3i(size)
	if not _box_shapes.has(key):
		var shape := BoxShape3D.new()
		shape.size = size
		_box_shapes[key] = shape
	return _box_shapes[key]

# The chunk's slice of wall up to its tallest building, in the chunk's frame.
func _chunk_bounds(plan, tallest: float) -> AABB:
	var span: float = SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width / plan.radius
	var chunk_length: float = SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length
	var bounds := AABB(Vector3(plan.radius, 0.0, 0.0), Vector3.ZERO)
	for step in range(9):
		var angle: float = span * step / 8.0
		for r: float in [plan.radius, plan.radius - tallest]:
			for z: float in [0.0, chunk_length]:
				bounds = bounds.expand(Vector3(cos(angle) * r, sin(angle) * r, z))
	return bounds.grow(1.0)

# One window per repeat. Albedo: white walls (tinted per building) with a
# darker pane. Glow mask: only the pane.
static func _window_texture(glow: bool) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in range(16):
		for y in range(16):
			var pane := x >= 4 and x < 12 and y >= 3 and y < 11
			var shade: float
			if glow:
				shade = 1.0 if pane else 0.0
			else:
				shade = 0.35 if pane else 1.0
			image.set_pixel(x, y, Color(shade, shade, shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
