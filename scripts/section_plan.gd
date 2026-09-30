extends RefCounted

# What stands on one section's inner surface: a grid of lots (zone, crop,
# roads) and a list of buildings. Pure data, made by section_generator.gd and
# turned into geometry by terrain_dressing.gd.
#
# Unrolled surface coordinates: x = arc length around the section
# (0 .. 2 pi radius), z = distance along it from its low-z end (0 .. length).
# Lot (around, along) covers x in [around, around + 1] * lot_width and
# z in [along, along + 1] * lot_length.

enum Zone { FIELD, TOWN, CITY, WATER, HILL, MOUNTAIN }
enum Crop { WHEAT, CORN, SUNFLOWER, LAVENDER, RICE, PASTURE }
enum Road { NONE, STREET, MAIN }
# How a building looks (see building_shapes.gd and the building shader).
enum Style { DOME, VAULT, BLOCK, RING_HOUSE, STEPPED, TAPERED, RING_TOWER, FIN_SLAB, SPIRE }
enum Facade { BANDS, SPARSE, GLASS, PANELS }
# Window light colours: warm white, cool white, cyan, amber, magenta.
const ACCENT_COUNT := 5

const LOTS_AROUND := 48
const LOTS_ALONG := 80
# Lots per interior terrain chunk (16 x 20 chunks per section).
const CHUNK_LOTS_AROUND := 3
const CHUNK_LOTS_ALONG := 4
const MAIN_ROAD_WIDTH := 12.0
const STREET_WIDTH := 8.0
# Height grid: RELIEF_POINTS_PER_LOT points per lot each way, so grid lines
# fall on every lot and chunk edge. Columns wrap (column RELIEF_COLUMNS is
# column 0); rows run from z = 0 to z = length inclusive.
const RELIEF_POINTS_PER_LOT := 5
const RELIEF_COLUMNS := LOTS_AROUND * RELIEF_POINTS_PER_LOT
const RELIEF_ROWS := LOTS_ALONG * RELIEF_POINTS_PER_LOT + 1

var section_index := 0
var radius := 0.0
var length := 0.0
var lot_width := 0.0
var lot_length := 0.0
# Per lot, index along * LOTS_AROUND + around.
var zones := PackedByteArray()
var crops := PackedByteArray()
var rows_along := PackedByteArray()
# Road on each lot's low-x (west) and low-z (south) edge.
var road_west := PackedByteArray()
var road_south := PackedByteArray()
var city_center := Vector2.ZERO
# Buildings: one entry per index across the parallel arrays.
var building_x := PackedFloat64Array()
var building_z := PackedFloat64Array()
# (width around, height, depth along), whole metres.
var building_size := PackedVector3Array()
var building_color := PackedColorArray()
var building_lot := PackedInt32Array()
var building_style := PackedByteArray()
var building_facade := PackedByteArray()
var building_accent := PackedByteArray()
# Share of the building's windows that are lit, 0..1.
var building_lit := PackedFloat64Array()
# Ground height toward the axis in metres, per grid point, index
# row * RELIEF_COLUMNS + column. Empty: all flat. Setting it also fills the
# slope grids (_slopes_x, _slopes_z: central differences per grid point).
var heights := PackedFloat32Array():
	set(value):
		heights = value
		_update_slopes()
var _slopes_x := PackedFloat32Array()
var _slopes_z := PackedFloat32Array()
# Whether the section has a mountain chain (section_generator.gd).
var has_chain := false

# Hills and mountains: the zones with relief (and trees).
static func is_raised(zone: int) -> bool:
	return zone == Zone.HILL or zone == Zone.MOUNTAIN

static func road_width(road: int) -> float:
	if road == Road.MAIN:
		return MAIN_ROAD_WIDTH
	if road == Road.STREET:
		return STREET_WIDTH
	return 0.0

func lot_index(around: int, along: int) -> int:
	return along * LOTS_AROUND + posmod(around, LOTS_AROUND)

func zone_at(around: int, along: int) -> int:
	return zones[lot_index(around, along)]

func lot_center(around: int, along: int) -> Vector2:
	return Vector2((around + 0.5) * lot_width, (along + 0.5) * lot_length)

func circumference() -> float:
	return LOTS_AROUND * lot_width

# Distance on the surface; around the section, the shorter way round.
func surface_distance(a: Vector2, b: Vector2) -> float:
	var dx: float = absf(a.x - b.x)
	dx = minf(dx, circumference() - dx)
	return Vector2(dx, a.y - b.y).length()

func height_step() -> Vector2:
	return Vector2(lot_width, lot_length) / RELIEF_POINTS_PER_LOT

func grid_height(column: int, row: int) -> float:
	if heights.is_empty():
		return 0.0
	return heights[clampi(row, 0, RELIEF_ROWS - 1) * RELIEF_COLUMNS + posmod(column, RELIEF_COLUMNS)]

func height_at(x: float, z: float) -> float:
	return sample_at(x, z).x

func slope_at(x: float, z: float) -> Vector2:
	var sample := sample_at(x, z)
	return Vector2(sample.y, sample.z)

# (height, dh/dx, dh/dz) at (x, z); x wraps around. The height follows the
# grid cell's two triangles, split along its (x1, z0)-(x0, z1) diagonal like
# the relief collision (TerrainDressing.relief_collision_faces), so what is
# drawn lies on what collides. The slope is bilinear between the grid
# points' central differences: smooth shading across the triangles. One
# cell lookup for all three: the terrain dressing inlines it per vertex.
func sample_at(x: float, z: float) -> Vector3:
	if heights.is_empty():
		return Vector3.ZERO
	var gx: float = fposmod(x / lot_width, LOTS_AROUND) * RELIEF_POINTS_PER_LOT
	var gz: float = clampf(z / lot_length * RELIEF_POINTS_PER_LOT, 0.0, RELIEF_ROWS - 1)
	var column := floori(gx)
	var row := mini(floori(gz), RELIEF_ROWS - 2)
	var fx: float = gx - column
	var fz: float = gz - row
	var i00: int = row * RELIEF_COLUMNS + column
	var i10: int = row * RELIEF_COLUMNS + (column + 1) % RELIEF_COLUMNS
	var i01: int = i00 + RELIEF_COLUMNS
	var i11: int = i10 + RELIEF_COLUMNS
	var w00: float = (1.0 - fx) * (1.0 - fz)
	var w10: float = fx * (1.0 - fz)
	var w01: float = (1.0 - fx) * fz
	var w11: float = fx * fz
	var h: float
	if fx + fz <= 1.0:
		h = heights[i00] + fx * (heights[i10] - heights[i00]) + fz * (heights[i01] - heights[i00])
	else:
		h = heights[i11] + (1.0 - fx) * (heights[i01] - heights[i11]) + (1.0 - fz) * (heights[i10] - heights[i11])
	return Vector3(
		h,
		_slopes_x[i00] * w00 + _slopes_x[i10] * w10 + _slopes_x[i01] * w01 + _slopes_x[i11] * w11,
		_slopes_z[i00] * w00 + _slopes_z[i10] * w10 + _slopes_z[i01] * w01 + _slopes_z[i11] * w11)

func _update_slopes() -> void:
	var slopes_x := PackedFloat32Array()
	var slopes_z := PackedFloat32Array()
	if not heights.is_empty():
		var step := height_step()
		slopes_x.resize(heights.size())
		slopes_z.resize(heights.size())
		for row in range(RELIEF_ROWS):
			var here: int = row * RELIEF_COLUMNS
			var below: int = maxi(row - 1, 0) * RELIEF_COLUMNS
			var above: int = mini(row + 1, RELIEF_ROWS - 1) * RELIEF_COLUMNS
			for column in range(RELIEF_COLUMNS):
				var west: int = (column + RELIEF_COLUMNS - 1) % RELIEF_COLUMNS
				var east: int = (column + 1) % RELIEF_COLUMNS
				slopes_x[here + column] = (heights[here + east] - heights[here + west]) / (2.0 * step.x)
				slopes_z[here + column] = (heights[above + column] - heights[below + column]) / (2.0 * step.y)
	_slopes_x = slopes_x
	_slopes_z = slopes_z

# True when any grid point of the chunk, borders included, is above 0.
func chunk_has_relief(chunk_around: int, chunk_along: int) -> bool:
	if heights.is_empty():
		return false
	var columns := CHUNK_LOTS_AROUND * RELIEF_POINTS_PER_LOT
	var rows := CHUNK_LOTS_ALONG * RELIEF_POINTS_PER_LOT
	for row in range(chunk_along * rows, chunk_along * rows + rows + 1):
		for column in range(chunk_around * columns, chunk_around * columns + columns + 1):
			if grid_height(column, row) > 0.0:
				return true
	return false

# A lot's east edge is its east neighbour's west edge; its north edge is its
# north neighbour's south edge (none past the section's far end).
func road_on_west(around: int, along: int) -> int:
	return road_west[lot_index(around, along)]

func road_on_east(around: int, along: int) -> int:
	return road_west[lot_index(around + 1, along)]

func road_on_south(around: int, along: int) -> int:
	return road_south[lot_index(around, along)]

func road_on_north(around: int, along: int) -> int:
	if along + 1 >= LOTS_ALONG:
		return Road.NONE
	return road_south[lot_index(around, along + 1)]

func building_count() -> int:
	return building_x.size()

# Building indices per interior chunk: Vector2i(chunk_around, chunk_along) -> Array.
@warning_ignore("integer_division")
func group_buildings_by_chunk() -> Dictionary:
	var groups := {}
	for b in range(building_count()):
		var lot: int = building_lot[b]
		var key := Vector2i((lot % LOTS_AROUND) / CHUNK_LOTS_AROUND, (lot / LOTS_AROUND) / CHUNK_LOTS_ALONG)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	return groups
