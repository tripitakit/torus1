extends RefCounted

# Turns a section plan into geometry, one interior terrain chunk at a time,
# in the chunk's own frame (InteriorWorld turns each chunk about Z and shifts
# it along Z). The ground is a mosaic with no overlapping layers, at level 0
# or following the plan's heights: with the interior camera (near 0.2 m, far
# 60 km) the depth buffer cannot separate surfaces less than a metre apart at
# 2 km, so layers would flicker.

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const BuildingShapesScript = preload("res://scripts/building_shapes.gd")
const TreeShapesScript = preload("res://scripts/tree_shapes.gd")

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
# Hill and mountain ground: forest floor up to the treeline, rock above it
# and on steep slopes.
const FOREST_COLOR := Color(0.2, 0.34, 0.15)
const ROCK_COLOR := Color(0.46, 0.44, 0.41)
# Two breaks closer than this are one (float rounding at lot edges).
const BREAK_TOLERANCE := 0.01
# A quad corner this close to a cell's fold (in grid cells) counts as on it.
const FOLD_TOLERANCE := 0.000001
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
# Forests on hills and mountains: one tree per TREE_SPACING cell of a global
# grid, jittered, TREE_EDGE_MARGIN clear of flat land, none above the
# treeline (TREELINE give or take TREELINE_BAND) or on slopes past
# TREE_MAX_SLOPE. Conifers are LOW_CONIFER_SHARE of the trees low down, all
# of them from CONIFERS_ONLY up. Base TREE_SINK into the ground.
const TREE_SPACING := 17.0
const TREE_EDGE_MARGIN := 5.0
const TREELINE := 600.0
const TREELINE_BAND := 50.0
const TREE_MAX_SLOPE := 1.2
const TREE_HEIGHTS := Vector2(10.0, 25.0)
const TREE_WIDTHS := Vector2(0.35, 0.5)
const TREE_SINK := 0.5
const LOW_CONIFER_SHARE := 0.4
const CONIFERS_FROM := 300.0
const CONIFERS_ONLY := 450.0
const CONIFER_GREEN := Color(0.12, 0.3, 0.16)
const BROADLEAF_GREEN := Color(0.24, 0.42, 0.14)
# Past this the forest floor's colour stands in for the trees.
const TREE_VISIBILITY_END := 3000.0
# Floats per tree in a MultiMesh buffer: 12 of transform, 4 of colour (the
# crown's green). Instance colour, not custom data: the compatibility
# renderer showed custom data as red, blue and magenta crowns.
const TREE_FLOATS := 16
const TRUNK_COLOR := Color(0.36, 0.25, 0.16)
const TREE_SHADER := """
shader_type spatial;

uniform vec3 trunk_color : source_color = vec3(0.36, 0.25, 0.16);

// COLOR is the vertex colour times the instance's: the crown (white, alpha
// 1) takes the tree's green; the trunk (alpha 0) stays trunk_color.
void fragment() {
	ALBEDO = mix(trunk_color, COLOR.rgb, COLOR.a);
	ROUGHNESS = 0.9;
}
"""

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

	# Sampling context of the patch being added (add_relief_patch sets it,
	# _relief_vertex reads it). Plain copies of the plan's numbers: reading
	# the shared plan object per vertex serialises the worker threads.
	var _radius := 0.0
	var _lot_width := 0.0
	var _lot_length := 0.0
	var _heights := PackedFloat32Array()
	var _slopes_x := PackedFloat32Array()
	var _slopes_z := PackedFloat32Array()
	var _chunk_start := Vector2.ZERO
	var _color := Color()
	var _rows_along := false
	var _relief_lot := false

	# The same rectangle following the plan's heights. chunk_start is the
	# chunk's (x, z) origin in section metres, lot_start the lot's (x, z) in
	# chunk metres. Split on every height-grid line and road-band edge
	# (relief_breaks below) so neighbours share every edge vertex, and each
	# piece crossing a grid cell's fold cut along it (_add_quad_on_folds), so
	# every triangle lies on the collision's plane. Hill and mountain lots take their
	# colour from height and slope.
	func add_relief_patch(plan, chunk_start: Vector2, lot_start: Vector2, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool, relief_lot: bool) -> void:
		var step: Vector2 = plan.height_step()
		var xs := relief_breaks(x0, x1, chunk_start.x, step.x, lot_start.x, plan.lot_width)
		var zs := relief_breaks(z0, z1, chunk_start.y, step.y, lot_start.y, plan.lot_length)
		_radius = plan.radius
		_lot_width = plan.lot_width
		_lot_length = plan.lot_length
		_heights = plan.heights
		_slopes_x = plan._slopes_x
		_slopes_z = plan._slopes_z
		_chunk_start = chunk_start
		_color = color
		_rows_along = rows_along
		_relief_lot = relief_lot
		var base: int = vertices.size()
		for x: float in xs:
			for z: float in zs:
				_relief_vertex(x, z)
		# Breaks in grid cells (section frame), for the folds.
		var gxs := PackedFloat64Array()
		for x: float in xs:
			gxs.append((chunk_start.x + x) / step.x)
		var gzs := PackedFloat64Array()
		for z: float in zs:
			gzs.append((chunk_start.y + z) / step.y)
		# (x_i, z_j) is base + i * zs.size() + j. Each quad lies in one grid
		# cell, whose height is two planes meeting on its fold fx + fz = 1:
		# a quad on one side is two triangles, one across it is cut there.
		var nz: int = zs.size()
		for i in range(xs.size() - 1):
			var column := floori((gxs[i] + gxs[i + 1]) * 0.5)
			var fx0: float = gxs[i] - column
			var fx1: float = gxs[i + 1] - column
			for j in range(nz - 1):
				var row := floori((gzs[j] + gzs[j + 1]) * 0.5)
				var fz0: float = gzs[j] - row - 1.0
				var fz1: float = gzs[j + 1] - row - 1.0
				var p00: int = base + i * nz + j
				var lowest: float = fx0 + fz0
				var highest: float = fx1 + fz1
				# The two usual triangles already meet on the (x1,z0)-(x0,z1)
				# diagonal: when the fold runs along it (a whole cell), no cut.
				var on_diagonal: bool = absf(fx1 + fz0) <= FOLD_TOLERANCE and absf(fx0 + fz1) <= FOLD_TOLERANCE
				if lowest < -FOLD_TOLERANCE and highest > FOLD_TOLERANCE and not on_diagonal and not _cell_is_flat(column, row):
					_cut_quad_on_fold(p00, nz, xs[i], xs[i + 1], zs[j], zs[j + 1], fx0, fx1, fz0, fz1)
				else:
					indices.append_array(PackedInt32Array([p00, p00 + nz, p00 + 1, p00 + nz, p00 + nz + 1, p00 + 1]))

	# Appends the vertex at chunk (x, z) of the current patch; returns its
	# index. SectionPlan.sample_at inlined (a call per vertex into the plan
	# costs more than the sum): the grid cell, the height on the cell's two
	# triangles, the bilinear slope.
	func _relief_vertex(x: float, z: float) -> int:
		var radius: float = _radius
		var columns := SectionPlanScript.RELIEF_COLUMNS
		var per_lot := float(SectionPlanScript.RELIEF_POINTS_PER_LOT)
		var gx: float = fposmod((_chunk_start.x + x) / _lot_width, SectionPlanScript.LOTS_AROUND) * per_lot
		var column := floori(gx)
		var fx: float = gx - column
		var gz: float = clampf((_chunk_start.y + z) / _lot_length * per_lot, 0.0, SectionPlanScript.RELIEF_ROWS - 1)
		var row := mini(floori(gz), SectionPlanScript.RELIEF_ROWS - 2)
		var fz: float = gz - row
		var i00: int = row * columns + column
		var i10: int = row * columns + (column + 1) % columns
		var i01: int = i00 + columns
		var i11: int = i10 + columns
		var h: float
		if fx + fz <= 1.0:
			h = _heights[i00] + fx * (_heights[i10] - _heights[i00]) + fz * (_heights[i01] - _heights[i00])
		else:
			h = _heights[i11] + (1.0 - fx) * (_heights[i01] - _heights[i11]) + (1.0 - fz) * (_heights[i10] - _heights[i11])
		var w00: float = (1.0 - fx) * (1.0 - fz)
		var w10: float = fx * (1.0 - fz)
		var w01: float = (1.0 - fx) * fz
		var w11: float = fx * fz
		var sx: float = _slopes_x[i00] * w00 + _slopes_x[i10] * w10 + _slopes_x[i01] * w01 + _slopes_x[i11] * w11
		var sz: float = _slopes_z[i00] * w00 + _slopes_z[i10] * w10 + _slopes_z[i01] * w01 + _slopes_z[i11] * w11
		var angle: float = x / radius
		var outward := Vector3(cos(angle), sin(angle), 0.0)
		var around := Vector3(-sin(angle), cos(angle), 0.0)
		var k: float = (radius - h) / radius
		vertices.append(outward * (radius - h) + Vector3(0.0, 0.0, z))
		normals.append((-outward * k - around * sx - Vector3(0.0, 0.0, k * sz)).normalized())
		colors.append(relief_color(h, sqrt(sx * sx + sz * sz)) if _relief_lot else _color)
		uvs.append(Vector2(x, z) / ROW_SPACING if _rows_along else Vector2(z, x) / ROW_SPACING)
		return vertices.size() - 1

	# A quad across its cell's fold: corner (x_i, z_j) is vertex
	# p00 + i * nz + j, and fx + fz - 1 its fold value (fx0..fx1 across,
	# fz0..fz1 already minus 1). Cut into two fans along the fold, corners in
	# ring order (x0,z0), (x1,z0), (x1,z1), (x0,z1) (which keeps the winding
	# facing the axis). Each crossing is computed from its edge's lower end,
	# so the quad on the other side of that edge gets the very same point.
	# Plain numbers and packed arrays only: this runs for every quad near a
	# road cut, and Variant arrays made it the dressing's main cost.
	func _cut_quad_on_fold(p00: int, nz: int, x0: float, x1: float, z0: float, z1: float, fx0: float, fx1: float, fz0: float, fz1: float) -> void:
		var ring := PackedInt32Array([p00, p00 + nz, p00 + nz + 1, p00 + 1])
		var ring_x := PackedFloat64Array([x0, x1, x1, x0])
		var ring_z := PackedFloat64Array([z0, z0, z1, z1])
		var folds := PackedFloat64Array([fx0 + fz0, fx1 + fz0, fx1 + fz1, fx0 + fz1])
		var low := PackedInt32Array()
		var high := PackedInt32Array()
		for k in range(4):
			var next: int = (k + 1) % 4
			var f0: float = folds[k]
			var f1: float = folds[next]
			if f0 <= FOLD_TOLERANCE:
				low.append(ring[k])
			if f0 >= -FOLD_TOLERANCE:
				high.append(ring[k])
			if (f0 < -FOLD_TOLERANCE and f1 > FOLD_TOLERANCE) or (f0 > FOLD_TOLERANCE and f1 < -FOLD_TOLERANCE):
				# Every ring edge runs along x or along z: its lower end is
				# the one with the smaller x or z.
				var first: int = k if ring_x[k] + ring_z[k] < ring_x[next] + ring_z[next] else next
				var second: int = next if first == k else k
				var t: float = folds[first] / (folds[first] - folds[second])
				var v := _relief_vertex(lerpf(ring_x[first], ring_x[second], t), lerpf(ring_z[first], ring_z[second], t))
				low.append(v)
				high.append(v)
		for polygon: PackedInt32Array in [low, high]:
			for k in range(1, polygon.size() - 1):
				indices.append(polygon[0])
				indices.append(polygon[k])
				indices.append(polygon[k + 1])

	# A cell whose four heights lie on one plane has no fold to cut along.
	func _cell_is_flat(column: int, row: int) -> bool:
		var columns := SectionPlanScript.RELIEF_COLUMNS
		var c: int = posmod(column, columns)
		var r: int = clampi(row, 0, SectionPlanScript.RELIEF_ROWS - 2)
		var i00: int = r * columns + c
		var i10: int = r * columns + (c + 1) % columns
		return absf(_heights[i00] + _heights[i10 + columns] - _heights[i10] - _heights[i00 + columns]) < 0.0001

	static func relief_color(height: float, slope: float) -> Color:
		var rock := maxf(smoothstep(0.9, 1.3, slope), smoothstep(550.0, 650.0, height))
		return FOREST_COLOR.lerp(ROCK_COLOR, rock)

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
var conifer_mesh: ArrayMesh
var broadleaf_mesh: ArrayMesh
var tree_material: ShaderMaterial
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
	conifer_mesh = TreeShapesScript.conifer()
	broadleaf_mesh = TreeShapesScript.broadleaf()
	var tree_shader := Shader.new()
	tree_shader.code = TREE_SHADER
	tree_material = ShaderMaterial.new()
	tree_material.shader = tree_shader
	tree_material.set_shader_parameter("trunk_color", TRUNK_COLOR)

# `ground` is build_ground's result for this chunk, when a worker thread made
# it already; empty, it is built here.
func dress_chunk(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, building_indices: Array, ground: Array = []) -> void:
	_add_ground(chunk, ground if not ground.is_empty() else build_ground(plan, chunk_around, chunk_along), plan)
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

# The chunk's ground as vertex data: [fields, paved, water, collision,
# trees], three MeshArrays, for a chunk with relief its collision triangles
# (empty when flat), and its trees (tree_buffers). Touches no node or resource: safe on a worker thread
# (the plan is only read).
static func build_ground(plan, chunk_around: int, chunk_along: int) -> Array:
	var fields := MeshArrays.new()
	var paved := MeshArrays.new()
	var water := MeshArrays.new()
	# Every chunk of a plan with heights takes the fine split, flat ones too:
	# a flat chunk's long chords next to a raised chunk's short ones opened
	# slits up to 0.44 m along their shared border.
	var relief: bool = not plan.heights.is_empty()
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
			if zone == SectionPlanScript.Zone.WATER or SectionPlanScript.is_raised(zone):
				# Whole lot, no roads (none border a lake, a hill or a mountain).
				var wet: bool = zone == SectionPlanScript.Zone.WATER
				_add(water if wet else paved, relief, plan, chunk_start, lot_start, x0, x1, z0, z1, WATER_COLOR if wet else FOREST_COLOR, true, not wet)
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
	var raised: bool = plan.chunk_has_relief(chunk_around, chunk_along)
	var collision: PackedVector3Array = relief_collision_faces(plan, chunk_around, chunk_along) if raised else PackedVector3Array()
	var trees: Array = tree_buffers(plan, chunk_around, chunk_along) if relief else [PackedFloat32Array(), PackedFloat32Array(), 0.0]
	return [fields, paved, water, collision, trees]

# A chunk with relief collides with the height grid's points (every one of
# them is also a vertex of the drawn ground), two triangles per grid cell,
# wound like the mesh: about a third of the drawn triangles, so the physics
# server builds it quickly on the main thread.
static func relief_collision_faces(plan, chunk_around: int, chunk_along: int) -> PackedVector3Array:
	var columns: int = SectionPlanScript.CHUNK_LOTS_AROUND * SectionPlanScript.RELIEF_POINTS_PER_LOT
	var rows: int = SectionPlanScript.CHUNK_LOTS_ALONG * SectionPlanScript.RELIEF_POINTS_PER_LOT
	var step: Vector2 = plan.height_step()
	var points := PackedVector3Array()
	for c in range(columns + 1):
		var angle: float = c * step.x / plan.radius
		var outward := Vector3(cos(angle), sin(angle), 0.0)
		for r in range(rows + 1):
			var h: float = plan.grid_height(chunk_around * columns + c, chunk_along * rows + r)
			points.append(outward * (plan.radius - h) + Vector3(0.0, 0.0, r * step.y))
	var faces := PackedVector3Array()
	var n: int = rows + 1
	for c in range(columns):
		for r in range(rows):
			var p00: int = c * n + r
			for i in [p00, p00 + n, p00 + 1, p00 + n, p00 + n + 1, p00 + 1]:
				faces.append(points[i])
	return faces

# Meshes and, with relief, the collision of a chunk's ground (build_ground).
func _add_ground(chunk: StaticBody3D, ground: Array, plan) -> void:
	var fields: MeshArrays = ground[0]
	var paved: MeshArrays = ground[1]
	var water: MeshArrays = ground[2]
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
	if not (ground[3] as PackedVector3Array).is_empty():
		_set_ground_collision(chunk, ground[3])
	_add_trees(chunk, ground[4], plan)

# Two MultiMeshes of the chunk's trees (build_ground made the buffers).
@warning_ignore("integer_division")
func _add_trees(chunk: StaticBody3D, trees: Array, plan) -> void:
	var group := Node3D.new()
	group.name = "Trees"
	for part in [["Conifers", trees[0], conifer_mesh], ["Broadleaves", trees[1], broadleaf_mesh]]:
		var buffer: PackedFloat32Array = part[1]
		if buffer.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = part[2]
		multimesh.instance_count = buffer.size() / TREE_FLOATS
		multimesh.buffer = buffer
		var node := MultiMeshInstance3D.new()
		node.name = part[0]
		node.multimesh = multimesh
		node.material_override = tree_material
		node.visibility_range_end = TREE_VISIBILITY_END
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = _chunk_bounds(plan, trees[2])
		group.add_child(node)
	if group.get_child_count() > 0:
		chunk.add_child(group)
	else:
		group.free()

# A 64-bit hash of a tree cell: eight 7-bit random numbers per tree.
static func _tree_hash(section_index: int, cx: int, cz: int) -> int:
	var h: int = section_index * 0x1E3779B97F4A7C15 + cx * 0x3F58476D1CE4E5B9 + cz * 0x14D049BB133111EB
	h = (h ^ (h >> 30)) * 0x3F58476D1CE4E5B9
	h = (h ^ (h >> 27)) * 0x14D049BB133111EB
	return h ^ (h >> 31)

# The trees of a chunk, for two MultiMeshes ([conifers, broadleaves, height
# of the tallest top above the wall]): one per TREE_SPACING cell of a global
# grid (section metres), jittered inside it, kept where its point lies in a
# hill or mountain lot, TREE_EDGE_MARGIN clear of flat land and the end
# walls, under the treeline and not on a cliff. Pure: safe on a worker
# thread.
static func tree_buffers(plan, chunk_around: int, chunk_along: int) -> Array:
	var conifers := PackedFloat32Array()
	var broadleaves := PackedFloat32Array()
	var tallest := 0.0
	var chunk_start := Vector2(chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width, chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length)
	var radius: float = plan.radius
	for lot_x in range(SectionPlanScript.CHUNK_LOTS_AROUND):
		for lot_z in range(SectionPlanScript.CHUNK_LOTS_ALONG):
			var around: int = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND + lot_x
			var along: int = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG + lot_z
			if not SectionPlanScript.is_raised(plan.zone_at(around, along)):
				continue
			var x0: float = around * plan.lot_width
			var x1: float = x0 + plan.lot_width
			var z0: float = along * plan.lot_length
			var z1: float = z0 + plan.lot_length
			var west: float = 0.0 if SectionPlanScript.is_raised(plan.zone_at(around - 1, along)) else TREE_EDGE_MARGIN
			var east: float = 0.0 if SectionPlanScript.is_raised(plan.zone_at(around + 1, along)) else TREE_EDGE_MARGIN
			var south: float = TREE_EDGE_MARGIN if along == 0 or not SectionPlanScript.is_raised(plan.zone_at(around, along - 1)) else 0.0
			var north: float = TREE_EDGE_MARGIN if along + 1 >= SectionPlanScript.LOTS_ALONG or not SectionPlanScript.is_raised(plan.zone_at(around, along + 1)) else 0.0
			for cx in range(floori(x0 / TREE_SPACING), ceili(x1 / TREE_SPACING)):
				for cz in range(floori(z0 / TREE_SPACING), ceili(z1 / TREE_SPACING)):
					var bits := _tree_hash(plan.section_index, cx, cz)
					var x: float = (cx + 0.15 + 0.7 * float(bits & 127) / 128.0) * TREE_SPACING
					var z: float = (cz + 0.15 + 0.7 * float((bits >> 7) & 127) / 128.0) * TREE_SPACING
					if x < x0 + west or x >= x1 - east or z < z0 + south or z >= z1 - north:
						continue
					var sample: Vector3 = plan.sample_at(x, z)
					var h: float = sample.x
					if h > TREELINE + TREELINE_BAND * (float((bits >> 14) & 127) / 64.0 - 1.0) or Vector2(sample.y, sample.z).length() > TREE_MAX_SLOPE:
						continue
					var conifer: bool = float((bits >> 21) & 127) / 128.0 < lerpf(LOW_CONIFER_SHARE, 1.0, smoothstep(CONIFERS_FROM, CONIFERS_ONLY, h))
					var tree_height: float = lerpf(TREE_HEIGHTS.x, TREE_HEIGHTS.y, float((bits >> 28) & 127) / 128.0)
					var width: float = tree_height * lerpf(TREE_WIDTHS.x, TREE_WIDTHS.y, float((bits >> 35) & 127) / 128.0)
					var yaw: float = TAU * float((bits >> 42) & 127) / 128.0
					var shade: float = lerpf(0.8, 1.15, float((bits >> 49) & 127) / 128.0)
					var angle: float = (x - chunk_start.x) / radius
					var up := Vector3(-cos(angle), -sin(angle), 0.0)
					var side: Vector3 = Vector3(-sin(angle), cos(angle), 0.0) * cos(yaw) + Vector3(0.0, 0.0, sin(yaw))
					var front: Vector3 = side.cross(up)
					var bx: Vector3 = side * width
					var by: Vector3 = up * tree_height
					var bz: Vector3 = front * width
					var origin: Vector3 = -up * (radius - h + TREE_SINK) + Vector3(0.0, 0.0, z - chunk_start.y)
					var green: Color = (CONIFER_GREEN if conifer else BROADLEAF_GREEN) * shade
					var data := PackedFloat32Array([bx.x, by.x, bz.x, origin.x, bx.y, by.y, bz.y, origin.y, bx.z, by.z, bz.z, origin.z, green.r, green.g, green.b, 1.0])
					if conifer:
						conifers.append_array(data)
					else:
						broadleaves.append_array(data)
					tallest = maxf(tallest, h + tree_height)
	return [conifers, broadleaves, tallest]

# A chunk with relief collides with its own ground, not the shared level-0
# shape.
func _set_ground_collision(chunk: StaticBody3D, faces: PackedVector3Array) -> void:
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

