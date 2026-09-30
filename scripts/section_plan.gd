extends RefCounted

# What stands on one section's inner surface: a grid of lots (zone, crop,
# roads) and a list of buildings. Pure data, made by section_generator.gd and
# turned into geometry by terrain_dressing.gd.
#
# Unrolled surface coordinates: x = arc length around the section
# (0 .. 2 pi radius), z = distance along it from its low-z end (0 .. length).
# Lot (around, along) covers x in [around, around + 1] * lot_width and
# z in [along, along + 1] * lot_length.

enum Zone { FIELD, TOWN, CITY, WATER, RELIEF }
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
# row * RELIEF_COLUMNS + column. Empty: all flat.
var heights := PackedFloat32Array()
# Mountain-noise level above which lot centres became RELIEF, and the
# highest lot-centre value (see section_generator.gd).
var relief_threshold := 0.0
var relief_peak := 0.0

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

# Bilinear between the four grid points around (x, z); x wraps around.
func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var step := height_step()
	var gx: float = fposmod(x, circumference()) / step.x
	var gz: float = clampf(z / step.y, 0.0, RELIEF_ROWS - 1)
	var column := floori(gx)
	var row := mini(floori(gz), RELIEF_ROWS - 2)
	var fx: float = gx - column
	var fz: float = gz - row
	var low: float = lerpf(grid_height(column, row), grid_height(column + 1, row), fx)
	var high: float = lerpf(grid_height(column, row + 1), grid_height(column + 1, row + 1), fx)
	return lerpf(low, high, fz)

# (dh/dx, dh/dz) by central differences one grid step each way.
func slope_at(x: float, z: float) -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var step := height_step()
	return Vector2(
		(height_at(x + step.x, z) - height_at(x - step.x, z)) / (2.0 * step.x),
		(height_at(x, z + step.y) - height_at(x, z - step.y)) / (2.0 * step.y))

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
