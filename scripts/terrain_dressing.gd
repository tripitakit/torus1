extends RefCounted

# Turns a section plan into geometry, one interior terrain chunk at a time,
# in the chunk's own frame (InteriorWorld turns each chunk about Z and shifts
# it along Z). The ground is a mosaic with no overlapping layers, at level 0
# or following the plan's heights: with the interior camera (near 0.2 m, far
# 60 km) the depth buffer cannot separate surfaces less than a metre apart at
# 2 km, so layers would flicker.

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const BuildingShapesScript = preload("res://scripts/building_shapes.gd")

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
# RELIEF lots: grass low and gentle, rock on steep slopes and high up.
const GRASS_COLOR := Color(0.36, 0.5, 0.26)
const ROCK_COLOR := Color(0.46, 0.44, 0.41)
# Two breaks closer than this are one (float rounding at lot edges).
const BREAK_TOLERANCE := 0.01
# One shader for every building (see BUILDING_SHADER): facades only on walls,
# driven by each instance's colour and custom data (building_custom).
const BUILDING_GLOW_ENERGY := 1.2
const BUILDING_SHADER := """
shader_type spatial;

uniform float glow_energy = 1.2;

// Filled in vertex(): position in metres in the building's own frame (base
// centre at the origin), the surface normal after the stretch, and the
// per-building data (TerrainDressing.building_custom).
varying vec3 local_position;
varying vec3 local_normal;
varying vec4 look;
varying float half_width;
varying float height;

// Warm white, cool white, cyan, amber, magenta.
const vec3 ACCENTS[5] = vec3[5](
	vec3(1.0, 0.82, 0.55),
	vec3(0.8, 0.9, 1.0),
	vec3(0.3, 0.9, 1.0),
	vec3(1.0, 0.6, 0.2),
	vec3(1.0, 0.3, 0.8));

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_position = VERTEX * scale + vec3(0.0, 0.5 * scale.y, 0.0);
	local_normal = normalize(NORMAL / scale);
	half_width = 0.25 * (scale.x + scale.z);
	height = scale.y;
	look = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 wall = COLOR.rgb;
	int facade = int(look.x + 0.5);
	vec3 accent = ACCENTS[clamp(int(look.y + 0.5), 0, 4)];
	float lit_share = look.z;
	float seed = look.w;
	// Metres round the building and up from its base: the same window size
	// on any shape, and no seams on the round ones.
	float around = atan(local_position.z, local_position.x) * half_width;
	float up = local_position.y;
	vec3 albedo = wall;
	float glow = 0.0;
	float metal = 0.1;
	float rough = 0.8;
	if (abs(local_normal.y) >= 0.5) {
		// Roofs, ledges and the tops of domes: plain, never windows.
		albedo = wall * 0.7;
	} else if (facade == 0) {
		// Bands of glass every 1 to 3 floors, each 8 m stretch lit or not.
		float period = 4.0 * (1.0 + floor(hash(vec2(seed, 1.0)) * 3.0));
		float band = step(mod(up, period), 1.2) * step(2.0, up);
		float lit = step(hash(vec2(floor(around / 8.0), floor(up / period)) + seed), 0.3 + lit_share);
		albedo = mix(wall, vec3(0.08, 0.1, 0.12), band);
		glow = band * lit;
	} else if (facade == 1) {
		// Sparse square windows, 1.5 m every 6 m across and 4 m up.
		vec2 cell = vec2(floor(around / 6.0), floor(up / 4.0));
		float pane = step(mod(around, 6.0), 1.5) * step(1.5, mod(up, 4.0)) * step(mod(up, 4.0), 3.0) * step(2.0, up);
		float lit = step(hash(cell + seed), lit_share);
		albedo = mix(wall, vec3(0.08, 0.1, 0.12), pane);
		glow = pane * lit;
	} else if (facade == 2) {
		// Dark glass all over, a light here and there.
		vec2 cell = vec2(floor(around / 3.0), floor(up / 4.0));
		float spot = step(0.3, fract(around / 3.0)) * step(fract(around / 3.0), 0.7) * step(0.3, fract(up / 4.0)) * step(fract(up / 4.0), 0.7);
		albedo = vec3(0.05, 0.07, 0.09) + wall * 0.05;
		metal = 0.8;
		rough = 0.15;
		glow = spot * step(hash(cell + seed), 0.05);
	} else {
		// Blind panels with seams, and a thin glowing band under the roof.
		float seam = max(step(mod(around, 4.0), 0.15), step(mod(up, 4.0), 0.15));
		albedo = wall * (1.0 - 0.4 * seam);
		metal = 0.5;
		rough = 0.5;
		glow = step(height - 2.0, up) * step(up, height - 1.4);
	}
	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = accent * glow * glow_energy;
}
"""
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

	# The same rectangle following the plan's heights. chunk_start is the
	# chunk's (x, z) origin in section metres, lot_start the lot's (x, z) in
	# chunk metres. Split on every height-grid line and road-band edge
	# (relief_breaks below) so neighbours share every edge vertex. RELIEF
	# lots take their colour from height and slope.
	func add_relief_patch(plan, chunk_start: Vector2, lot_start: Vector2, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool, relief_lot: bool) -> void:
		var step: Vector2 = plan.height_step()
		var xs := relief_breaks(x0, x1, chunk_start.x, step.x, lot_start.x, plan.lot_width)
		var zs := relief_breaks(z0, z1, chunk_start.y, step.y, lot_start.y, plan.lot_length)
		var radius: float = plan.radius
		var base: int = vertices.size()
		for x: float in xs:
			var angle: float = x / radius
			var outward := Vector3(cos(angle), sin(angle), 0.0)
			var around := Vector3(-sin(angle), cos(angle), 0.0)
			for z: float in zs:
				var h: float = plan.height_at(chunk_start.x + x, chunk_start.y + z)
				var slope: Vector2 = plan.slope_at(chunk_start.x + x, chunk_start.y + z)
				var k: float = (radius - h) / radius
				vertices.append(outward * (radius - h) + Vector3(0.0, 0.0, z))
				normals.append((-outward * k - around * slope.x - Vector3(0.0, 0.0, k * slope.y)).normalized())
				colors.append(relief_color(h, slope.length()) if relief_lot else color)
				uvs.append(Vector2(x, z) / ROW_SPACING if rows_along else Vector2(z, x) / ROW_SPACING)
		# Same winding as add_patch: (x_i, z_j) is base + i * zs.size() + j.
		var nz: int = zs.size()
		for i in range(xs.size() - 1):
			for j in range(nz - 1):
				var p00: int = base + i * nz + j
				indices.append_array(PackedInt32Array([p00, p00 + nz, p00 + 1, p00 + nz, p00 + nz + 1, p00 + 1]))

	# Triangle corners in draw order, for a collision shape.
	func faces() -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in indices:
			out.append(vertices[i])
		return out

	static func relief_color(height: float, slope: float) -> Color:
		var rock := maxf(smoothstep(0.5, 0.9, slope), smoothstep(180.0, 300.0, height))
		return GRASS_COLOR.lerp(ROCK_COLOR, rock)

	# Where a relief patch from a to b (chunk metres, one axis) is split: its
	# two ends, every height-grid line inside it (grid lines sit at whole
	# steps of section metres, chunk_start being the chunk's origin), and
	# every edge a road band of its lot could have (half a street or main
	# road in from either lot edge). Two patches sharing an edge thus share
	# every vertex on it.
	static func relief_breaks(a: float, b: float, chunk_start: float, step: float, lot_start: float, lot_size: float) -> PackedFloat64Array:
		var street: float = SectionPlanScript.road_width(SectionPlanScript.Road.STREET) * 0.5
		var main: float = SectionPlanScript.road_width(SectionPlanScript.Road.MAIN) * 0.5
		var lot_end: float = lot_start + lot_size
		var cuts: Array[float] = [lot_start + street, lot_start + main, lot_end - main, lot_end - street]
		var k := ceili((chunk_start + a) / step)
		while k * step - chunk_start < b:
			cuts.append(k * step - chunk_start)
			k += 1
		cuts.sort()
		var out := PackedFloat64Array([a])
		for cut in cuts:
			if cut > out[out.size() - 1] + BREAK_TOLERANCE and cut < b - BREAK_TOLERANCE:
				out.append(cut)
		out.append(b)
		return out

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
var building_material: ShaderMaterial
# Convex colliders by (style, whole-metre size): equal buildings share one.
# Each key counts the chunks using it; release_chunk drops shapes no chunk
# uses any more, so the cache holds only what is loaded.
var _convex_shapes := {}
var _shape_users := {}

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
	var shader := Shader.new()
	shader.code = BUILDING_SHADER
	building_material = ShaderMaterial.new()
	building_material.shader = shader
	building_material.set_shader_parameter("glow_energy", BUILDING_GLOW_ENERGY)

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
	var relief: bool = plan.chunk_has_relief(chunk_around, chunk_along)
	var chunk_start := Vector2(chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width, chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length)
	for lot_x in range(SectionPlanScript.CHUNK_LOTS_AROUND):
		for lot_z in range(SectionPlanScript.CHUNK_LOTS_ALONG):
			var around: int = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND + lot_x
			var along: int = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG + lot_z
			var x0: float = lot_x * plan.lot_width
			var x1: float = x0 + plan.lot_width
			var z0: float = lot_z * plan.lot_length
			var z1: float = z0 + plan.lot_length
			var lot_start := Vector2(x0, z0)
			var zone: int = plan.zone_at(around, along)
			if zone == SectionPlanScript.Zone.WATER or zone == SectionPlanScript.Zone.RELIEF:
				# Whole lot, no roads (none border a lake or a RELIEF lot).
				var wet: bool = zone == SectionPlanScript.Zone.WATER
				_add(water if wet else paved, relief, plan, chunk_start, lot_start, x0, x1, z0, z1, WATER_COLOR if wet else GRASS_COLOR, true, not wet)
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
						_add(paved, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, MAIN_ROAD_COLOR, true, false)
					elif road == SectionPlanScript.Road.STREET:
						_add(paved, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, STREET_COLOR, true, false)
					elif zone == SectionPlanScript.Zone.FIELD:
						_add(fields, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, CROP_COLORS[plan.crops[lot]], plan.rows_along[lot] == 1, false)
					else:
						_add(paved, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, TOWN_GROUND_COLOR if zone == SectionPlanScript.Zone.TOWN else CITY_GROUND_COLOR, true, false)
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
	if relief:
		_set_ground_collision(chunk, [fields, paved, water])

# A chunk with relief collides with its own drawn ground, not the shared
# level-0 shape: same triangles as the mesh.
func _set_ground_collision(chunk: StaticBody3D, parts: Array) -> void:
	var faces := PackedVector3Array()
	for arrays: MeshArrays in parts:
		faces.append_array(arrays.faces())
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Collision"
		chunk.add_child(collision)
	collision.shape = shape

# One patch: split and lifted to the plan's heights in a chunk with relief,
# the old level-0 patch otherwise.
static func _add(arrays: MeshArrays, relief: bool, plan, chunk_start: Vector2, lot_start: Vector2, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool, relief_lot: bool) -> void:
	if relief:
		arrays.add_relief_patch(plan, chunk_start, lot_start, x0, x1, z0, z1, color, rows_along, relief_lot)
	else:
		arrays.add_patch(plan.radius, x0, x1, z0, z1, color, rows_along)

# One filare per repeat: a lighter band and a darker furrow.
static func _stripe_texture() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in range(16):
		var shade := 1.0 if x < 11 else 0.55
		for y in range(16):
			image.set_pixel(x, y, Color(shade, shade, shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func relief_color(height: float, slope: float) -> Color:
	return MeshArrays.relief_color(height, slope)

static func relief_breaks(a: float, b: float, chunk_start: float, step: float, lot_start: float, lot_size: float) -> PackedFloat64Array:
	return MeshArrays.relief_breaks(a, b, chunk_start, step, lot_start, lot_size)

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

# Per-instance data for the building shader: facade, light colour, share of
# windows lit, and a seed in 0..1 that varies the pattern between buildings.
static func building_custom(plan, b: int) -> Color:
	return Color(float(plan.building_facade[b]), float(plan.building_accent[b]), plan.building_lit[b], fposmod(b * 0.618034, 1.0))

func _build_buildings(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, indices: Array) -> void:
	var xforms := chunk_building_transforms(plan, chunk_around, chunk_along, indices)
	# Colliders straight on the chunk body, in index order: thousands of
	# nodes would slow docking down.
	var by_style := {}
	var used := {}
	for k in range(indices.size()):
		var b: int = indices[k]
		var style: int = plan.building_style[b]
		if not by_style.has(style):
			by_style[style] = []
		by_style[style].append(k)
		var owner_id := chunk.create_shape_owner(chunk)
		chunk.shape_owner_add_shape(owner_id, _convex_shape(style, plan.building_size[b]))
		used[_shape_key(style, plan.building_size[b])] = true
		chunk.shape_owner_set_transform(owner_id, xforms[k].orthonormalized())
	for key in used:
		_shape_users[key] = _shape_users.get(key, 0) + 1
	chunk.set_meta("shape_keys", used.keys())
	var group := Node3D.new()
	group.name = "Buildings"
	chunk.add_child(group)
	# One MultiMesh per shape present in the chunk.
	for style: int in by_style:
		var ks: Array = by_style[style]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = BuildingShapesScript.mesh(style)
		multimesh.instance_count = ks.size()
		var tallest := 0.0
		for i in range(ks.size()):
			var k: int = ks[i]
			var b: int = indices[k]
			multimesh.set_instance_transform(i, xforms[k])
			multimesh.set_instance_color(i, plan.building_color[b])
			multimesh.set_instance_custom_data(i, building_custom(plan, b))
			tallest = maxf(tallest, plan.building_size[b].y)
		var instance := MultiMeshInstance3D.new()
		instance.name = BuildingShapesScript.NAMES[style]
		instance.multimesh = multimesh
		instance.material_override = building_material
		instance.visibility_range_end = BUILDING_VISIBILITY_END
		instance.custom_aabb = _chunk_bounds(plan, tallest)
		group.add_child(instance)

# Called before a dressed chunk is freed: its collider shapes are dropped
# from the cache unless another chunk still uses them. Built chunks keep
# their own shapes either way.
func release_chunk(chunk: Node) -> void:
	for key in chunk.get_meta("shape_keys", []):
		var users: int = _shape_users.get(key, 0) - 1
		if users > 0:
			_shape_users[key] = users
		else:
			_shape_users.erase(key)
			_convex_shapes.erase(key)

static func _shape_key(style: int, size: Vector3) -> Vector4i:
	return Vector4i(style, roundi(size.x), roundi(size.y), roundi(size.z))

func _convex_shape(style: int, size: Vector3) -> ConvexPolygonShape3D:
	var key := _shape_key(style, size)
	if not _convex_shapes.has(key):
		var points := PackedVector3Array()
		for p in BuildingShapesScript.hull_points(style):
			points.append(p * size)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		_convex_shapes[key] = shape
	return _convex_shapes[key]

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

