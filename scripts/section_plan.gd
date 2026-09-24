extends RefCounted

# What stands on one section's inner surface: a grid of lots (zone, crop,
# roads) and a list of buildings. Pure data, made by section_generator.gd and
# turned into geometry by terrain_dressing.gd.
#
# Unrolled surface coordinates: x = arc length around the section
# (0 .. 2 pi radius), z = distance along it from its low-z end (0 .. length).
# Lot (around, along) covers x in [around, around + 1] * lot_width and
# z in [along, along + 1] * lot_length.

enum Zone { FIELD, TOWN, CITY, WATER }
enum Crop { WHEAT, CORN, SUNFLOWER, LAVENDER, RICE, PASTURE }
enum Road { NONE, STREET, MAIN }

const LOTS_AROUND := 48
const LOTS_ALONG := 80
# Lots per interior terrain chunk (16 x 20 chunks per section).
const CHUNK_LOTS_AROUND := 3
const CHUNK_LOTS_ALONG := 4
const MAIN_ROAD_WIDTH := 12.0
const STREET_WIDTH := 8.0

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
