extends RefCounted

# Builds the plan of one section's inner surface from the section's index
# alone: same index, same plan, every time (piece C regenerates sections as
# the player travels). Packed arrays are built in locals and assigned whole.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const WATER_SHARE := 0.10
const TOWN_SHARE := 0.15
# The field lots with the highest mountain noise become RELIEF: this share of
# all lots (see _with_relief).
const RELIEF_SHARE := 0.05
const MOUNTAIN_FEATURE_SIZE := 1500.0
# Hills roll up to HILL_HEIGHT everywhere on open land; mountains add up to
# MOUNTAIN_HEIGHT in total where the mountain noise passes the RELIEF
# threshold. Both fade to 0 within RELIEF_BLEND of a town, the city, a lake
# or an end wall.
const HILL_FEATURE_SIZE := 800.0
const HILL_HEIGHT := 100.0
const MOUNTAIN_HEIGHT := 350.0
const RELIEF_BLEND := 250.0
const ZONE_FEATURE_SIZE := 2500.0
const CITY_RADIUS := 700.0
# Share of the length, from each end, the city centre keeps away from.
const CITY_END_MARGIN := 0.2
const TOWER_RADIUS := 250.0
# Buildings keep this far from every lot edge: clear of the widest road
# (6 m on each side of an edge) with room to spare.
const LOT_MARGIN := 10.0
# Gap between a building and the edge of its plot.
const PLOT_CLEARANCE := 2.0
const TOWN_PLOTS := 5
const CITY_PLOTS := 3
const TOWN_BUILD_CHANCE := 0.8
const TOWN_FOOTPRINT := Vector2(12.0, 25.0)
const TOWN_HEIGHT := Vector2(8.0, 40.0)
const CITY_FOOTPRINT := Vector2(30.0, 60.0)
const CITY_HEIGHT := Vector2(40.0, 120.0)
const TOWER_FOOTPRINT := Vector2(25.0, 45.0)
const TOWER_HEIGHT := Vector2(150.0, 300.0)
# Sci-fi facade colours: towns light (white, light grey, sand, blue-grey,
# pale teal), the city darker (graphite, grey, white, blue-grey, bronze).
const TOWN_COLORS := [Color(0.92, 0.93, 0.95), Color(0.78, 0.8, 0.83), Color(0.85, 0.8, 0.7), Color(0.62, 0.68, 0.75), Color(0.72, 0.82, 0.8)]
const CITY_COLORS := [Color(0.3, 0.32, 0.35), Color(0.55, 0.57, 0.6), Color(0.88, 0.9, 0.92), Color(0.5, 0.58, 0.68), Color(0.42, 0.38, 0.33)]
# Shapes by zone. Domes and vaults only for low, wide town buildings: a dome
# 40 m high on a 12 m base would read as a bullet. Towers are mostly spires.
const TOWN_LOW_STYLES := [SectionPlanScript.Style.DOME, SectionPlanScript.Style.VAULT, SectionPlanScript.Style.BLOCK, SectionPlanScript.Style.RING_HOUSE]
const TOWN_TALL_STYLES := [SectionPlanScript.Style.BLOCK, SectionPlanScript.Style.RING_HOUSE]
const CITY_STYLES := [SectionPlanScript.Style.STEPPED, SectionPlanScript.Style.TAPERED, SectionPlanScript.Style.RING_TOWER, SectionPlanScript.Style.FIN_SLAB]
const TOWER_STYLES := [SectionPlanScript.Style.SPIRE, SectionPlanScript.Style.SPIRE, SectionPlanScript.Style.STEPPED, SectionPlanScript.Style.RING_TOWER]
const LOW_AND_WIDE := 0.7
# Warm white, cool white, cyan, amber, magenta (rare).
const ACCENT_WEIGHTS := [0.3, 0.25, 0.2, 0.18, 0.07]
const LIT_SHARE := Vector2(0.2, 0.6)

static func generate(section_index: int, radius: float, length: float):
	var plan = SectionPlanScript.new()
	plan.section_index = section_index
	plan.radius = radius
	plan.length = length
	plan.lot_width = TAU * radius / SectionPlanScript.LOTS_AROUND
	plan.lot_length = length / SectionPlanScript.LOTS_ALONG
	plan.zones = _zones_from_noise(plan)
	plan.city_center = _city_center(plan)
	plan.zones = _with_city(plan, plan.zones)
	plan.zones = _with_relief(plan, plan.zones)
	plan.crops = _crops(plan)
	plan.rows_along = _rows(plan)
	var roads: Array = _roads(plan)
	plan.road_west = roads[0]
	plan.road_south = roads[1]
	_place_buildings(plan)
	plan.heights = _heights(plan)
	return plan

# Noise sampled at the lot centre's 3D position on the cylinder, so zones join
# up seamlessly where the way round closes.
static func _lot_point(plan, around: int, along: int) -> Vector3:
	var angle: float = TAU * (around + 0.5) / SectionPlanScript.LOTS_AROUND
	return Vector3(cos(angle) * plan.radius, sin(angle) * plan.radius, (along + 0.5) * plan.lot_length)

static func _sample_lots(plan, noise: FastNoiseLite) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			values.append(noise.get_noise_3dv(_lot_point(plan, around, along)))
	return values

static func _zones_from_noise(plan) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = plan.section_index
	noise.frequency = 1.0 / ZONE_FEATURE_SIZE
	var values := _sample_lots(plan, noise)
	# Thresholds from the values themselves: exactly the lowest share is
	# water and the highest share is town, whatever the noise's spread.
	var sorted := values.duplicate()
	sorted.sort()
	var count := values.size()
	var water_below: float = sorted[int(count * WATER_SHARE)]
	var town_above: float = sorted[count - 1 - int(count * TOWN_SHARE)]
	var zones := PackedByteArray()
	for value in values:
		if value < water_below:
			zones.append(SectionPlanScript.Zone.WATER)
		elif value > town_above:
			zones.append(SectionPlanScript.Zone.TOWN)
		else:
			zones.append(SectionPlanScript.Zone.FIELD)
	return zones

static func _city_center(plan) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, "city"])
	var around := rng.randi_range(0, SectionPlanScript.LOTS_AROUND - 1)
	var along := rng.randi_range(int(SectionPlanScript.LOTS_ALONG * CITY_END_MARGIN), int(SectionPlanScript.LOTS_ALONG * (1.0 - CITY_END_MARGIN)) - 1)
	return plan.lot_center(around, along)

static func _with_city(plan, zones: PackedByteArray) -> PackedByteArray:
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			if plan.surface_distance(plan.lot_center(around, along), plan.city_center) <= CITY_RADIUS:
				zones[plan.lot_index(around, along)] = SectionPlanScript.Zone.CITY
	return zones

static func mountain_noise(section_index: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = hash([section_index, "relief"])
	noise.frequency = 1.0 / MOUNTAIN_FEATURE_SIZE
	noise.fractal_octaves = 4
	return noise

# A point of the unrolled surface on the cylinder in 3D, where the noises are
# sampled: the way round closes with no seam.
static func surface_point(plan, x: float, z: float) -> Vector3:
	var angle: float = x / plan.radius
	return Vector3(cos(angle) * plan.radius, sin(angle) * plan.radius, z)

# The field lots with the highest mountain noise at their centre, RELIEF_SHARE
# of all lots, become RELIEF. Keeps the threshold and the highest centre value
# for the heights.
static func _with_relief(plan, zones: PackedByteArray) -> PackedByteArray:
	var noise := mountain_noise(plan.section_index)
	var values := PackedFloat64Array()
	var field_values := PackedFloat64Array()
	var peak := -INF
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var center: Vector2 = plan.lot_center(around, along)
			var value: float = noise.get_noise_3dv(surface_point(plan, center.x, center.y))
			values.append(value)
			peak = maxf(peak, value)
			if zones[plan.lot_index(around, along)] == SectionPlanScript.Zone.FIELD:
				field_values.append(value)
	field_values.sort()
	var count: int = mini(int(values.size() * RELIEF_SHARE), field_values.size())
	var threshold: float = field_values[field_values.size() - count]
	for i in range(values.size()):
		if zones[i] == SectionPlanScript.Zone.FIELD and values[i] >= threshold:
			zones[i] = SectionPlanScript.Zone.RELIEF
	plan.relief_threshold = threshold
	plan.relief_peak = peak
	return zones

static func _is_flat(zone: int) -> bool:
	return zone == SectionPlanScript.Zone.TOWN or zone == SectionPlanScript.Zone.CITY or zone == SectionPlanScript.Zone.WATER

# For each lot, the rectangles (x0, z0, x1, z1) of the flat lots among it and
# its 8 neighbours. RELIEF_BLEND is under one lot, so no farther lot can be
# nearer than it. Lots next to the seam get the neighbour across it at its
# unrolled position (x below 0 or past the circumference).
static func _flat_rects_by_lot(plan) -> Array:
	var by_lot := []
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var rects := []
			for dz in range(-1, 2):
				var lot_z: int = along + dz
				if lot_z < 0 or lot_z >= SectionPlanScript.LOTS_ALONG:
					continue
				for dx in range(-1, 2):
					var lot_x: int = around + dx
					if _is_flat(plan.zone_at(lot_x, lot_z)):
						rects.append(Rect2(lot_x * plan.lot_width, lot_z * plan.lot_length, plan.lot_width, plan.lot_length))
			by_lot.append(rects)
	return by_lot

# Distance from (x, z) to the nearest of `rects` or to an end wall. A point
# inside or on the edge of a flat lot is at 0.
static func _flat_distance(plan, x: float, z: float, rects: Array) -> float:
	var nearest: float = minf(z, plan.length - z)
	for rect: Rect2 in rects:
		var gap_x: float = maxf(0.0, maxf(rect.position.x - x, x - rect.end.x))
		var gap_z: float = maxf(0.0, maxf(rect.position.y - z, z - rect.end.y))
		nearest = minf(nearest, Vector2(gap_x, gap_z).length())
	return nearest

@warning_ignore("integer_division")
static func _heights(plan) -> PackedFloat32Array:
	var mountains := mountain_noise(plan.section_index)
	var hills := FastNoiseLite.new()
	hills.seed = hash([plan.section_index, "hills"])
	hills.frequency = 1.0 / HILL_FEATURE_SIZE
	hills.fractal_octaves = 2
	var flat_rects := _flat_rects_by_lot(plan)
	var step: Vector2 = plan.height_step()
	var heights := PackedFloat32Array()
	heights.resize(SectionPlanScript.RELIEF_COLUMNS * SectionPlanScript.RELIEF_ROWS)
	for row in range(SectionPlanScript.RELIEF_ROWS):
		var z: float = row * step.y
		var along: int = mini(row / SectionPlanScript.RELIEF_POINTS_PER_LOT, SectionPlanScript.LOTS_ALONG - 1)
		for column in range(SectionPlanScript.RELIEF_COLUMNS):
			var x: float = column * step.x
			var around: int = column / SectionPlanScript.RELIEF_POINTS_PER_LOT
			var distance := _flat_distance(plan, x, z, flat_rects[along * SectionPlanScript.LOTS_AROUND + around])
			if distance <= 0.0:
				continue  # resize() filled it with 0
			var p := surface_point(plan, x, z)
			var hill: float = HILL_HEIGHT * clampf((hills.get_noise_3dv(p) + 1.0) * 0.5, 0.0, 1.0)
			var mountain: float = (MOUNTAIN_HEIGHT - HILL_HEIGHT) * smoothstep(plan.relief_threshold, plan.relief_peak, mountains.get_noise_3dv(p))
			heights[row * SectionPlanScript.RELIEF_COLUMNS + column] = minf(hill + mountain, MOUNTAIN_HEIGHT) * smoothstep(0.0, RELIEF_BLEND, distance)
	return heights

# Crops come in patches: one seed per block of CHUNK lots, jittered inside
# it with a random crop; every lot takes the crop of its nearest seed. The
# patches are irregular, about a dozen lots each, and join up where the way
# round closes (distances wrap). Smooth noise cut into six equal crop bands
# changed crop almost every lot (checked: 17-50% of neighbours alike).
@warning_ignore("integer_division")
static func _crops(plan) -> PackedByteArray:
	var block_lots := Vector2i(SectionPlanScript.CHUNK_LOTS_AROUND, SectionPlanScript.CHUNK_LOTS_ALONG)
	var blocks_around: int = SectionPlanScript.LOTS_AROUND / block_lots.x
	var blocks_along: int = SectionPlanScript.LOTS_ALONG / block_lots.y
	var block_size := Vector2(block_lots.x * plan.lot_width, block_lots.y * plan.lot_length)
	var crop_count: int = SectionPlanScript.Crop.size()
	var seeds := PackedVector2Array()
	var seed_crops := PackedByteArray()
	for block_z in range(blocks_along):
		for block_x in range(blocks_around):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.section_index, block_x, block_z, "crop"])
			seeds.append(Vector2((block_x + rng.randf()) * block_size.x, (block_z + rng.randf()) * block_size.y))
			seed_crops.append(rng.randi_range(0, crop_count - 1))
	var crops := PackedByteArray()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var center: Vector2 = plan.lot_center(around, along)
			var home := Vector2i(around / block_lots.x, along / block_lots.y)
			var best := INF
			var crop := 0
			# The nearest seed is in the lot's own block or one next to it.
			for dz in range(-1, 2):
				var block_z: int = home.y + dz
				if block_z < 0 or block_z >= blocks_along:
					continue
				for dx in range(-1, 2):
					var s: int = block_z * blocks_around + posmod(home.x + dx, blocks_around)
					var distance: float = plan.surface_distance(center, seeds[s])
					if distance < best:
						best = distance
						crop = seed_crops[s]
			crops.append(crop)
	return crops

static func _rows(plan) -> PackedByteArray:
	var rows := PackedByteArray()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.section_index, around, along, "rows"])
			rows.append(rng.randi_range(0, 1))
	return rows

static func _is_built(zone: int) -> bool:
	return zone == SectionPlanScript.Zone.TOWN or zone == SectionPlanScript.Zone.CITY

# No road next to a lake or a RELIEF lot; a main road on every chunk border; a
# street next to a town or the city; nothing between two fields.
static func _edge_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	for zone in [zone_a, zone_b]:
		if zone == SectionPlanScript.Zone.WATER or zone == SectionPlanScript.Zone.RELIEF:
			return SectionPlanScript.Road.NONE
	if on_chunk_border:
		return SectionPlanScript.Road.MAIN
	if _is_built(zone_a) or _is_built(zone_b):
		return SectionPlanScript.Road.STREET
	return SectionPlanScript.Road.NONE

static func _roads(plan) -> Array:
	var west := PackedByteArray()
	var south := PackedByteArray()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var zone: int = plan.zone_at(around, along)
			west.append(_edge_road(zone, plan.zone_at(around - 1, along), around % SectionPlanScript.CHUNK_LOTS_AROUND == 0))
			if along == 0:
				# The section's end wall: no road.
				south.append(SectionPlanScript.Road.NONE)
			else:
				south.append(_edge_road(zone, plan.zone_at(around, along - 1), along % SectionPlanScript.CHUNK_LOTS_ALONG == 0))
	return [west, south]

static func _place_buildings(plan) -> void:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var sizes := PackedVector3Array()
	var colors := PackedColorArray()
	var lots := PackedInt32Array()
	var styles := PackedByteArray()
	var facades := PackedByteArray()
	var accents := PackedByteArray()
	var lits := PackedFloat64Array()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var zone: int = plan.zone_at(around, along)
			var plots: int
			var chance: float
			var footprint: Vector2
			var heights: Vector2
			var palette: Array
			var tower := false
			if zone == SectionPlanScript.Zone.TOWN:
				plots = TOWN_PLOTS
				chance = TOWN_BUILD_CHANCE
				footprint = TOWN_FOOTPRINT
				heights = TOWN_HEIGHT
				palette = TOWN_COLORS
			elif zone == SectionPlanScript.Zone.CITY:
				tower = plan.surface_distance(plan.lot_center(around, along), plan.city_center) <= TOWER_RADIUS
				plots = CITY_PLOTS
				chance = 1.0
				footprint = TOWER_FOOTPRINT if tower else CITY_FOOTPRINT
				heights = TOWER_HEIGHT if tower else CITY_HEIGHT
				palette = CITY_COLORS
			else:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.section_index, around, along])
			var plot_width: float = (plan.lot_width - 2.0 * LOT_MARGIN) / plots
			var plot_depth: float = (plan.lot_length - 2.0 * LOT_MARGIN) / plots
			for plot_x in range(plots):
				for plot_z in range(plots):
					if rng.randf() >= chance:
						continue
					var width: float = minf(roundf(rng.randf_range(footprint.x, footprint.y)), floorf(plot_width - 2.0 * PLOT_CLEARANCE))
					var depth: float = minf(roundf(rng.randf_range(footprint.x, footprint.y)), floorf(plot_depth - 2.0 * PLOT_CLEARANCE))
					# Squaring the random number: many low buildings, a few tall.
					var height: float = roundf(lerpf(heights.x, heights.y, pow(rng.randf(), 2.0)))
					var plot_x0: float = around * plan.lot_width + LOT_MARGIN + plot_x * plot_width
					var plot_z0: float = along * plan.lot_length + LOT_MARGIN + plot_z * plot_depth
					xs.append(plot_x0 + rng.randf_range(PLOT_CLEARANCE + width * 0.5, plot_width - PLOT_CLEARANCE - width * 0.5))
					zs.append(plot_z0 + rng.randf_range(PLOT_CLEARANCE + depth * 0.5, plot_depth - PLOT_CLEARANCE - depth * 0.5))
					sizes.append(Vector3(width, height, depth))
					colors.append(palette[rng.randi_range(0, palette.size() - 1)])
					lots.append(plan.lot_index(around, along))
					var look := _building_look(plan.section_index, around, along, plot_x, plot_z, zone == SectionPlanScript.Zone.TOWN, tower, Vector3(width, height, depth))
					styles.append(look[0])
					facades.append(look[1])
					accents.append(look[2])
					lits.append(look[3])
	plan.building_x = xs
	plan.building_z = zs
	plan.building_size = sizes
	plan.building_color = colors
	plan.building_lot = lots
	plan.building_style = styles
	plan.building_facade = facades
	plan.building_accent = accents
	plan.building_lit = lits

# Shape, facade, light colour and lit share of one building, from its own
# RNG: the placement RNG's sequence (positions, sizes) stays as it was.
static func _building_look(section_index: int, around: int, along: int, plot_x: int, plot_z: int, town: bool, tower: bool, size: Vector3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([section_index, around, along, plot_x, plot_z, "look"])
	var styles: Array
	if town:
		styles = TOWN_LOW_STYLES if size.y <= LOW_AND_WIDE * minf(size.x, size.z) else TOWN_TALL_STYLES
	elif tower:
		styles = TOWER_STYLES
	else:
		styles = CITY_STYLES
	var style: int = styles[rng.randi_range(0, styles.size() - 1)]
	var facade: int = rng.randi_range(0, SectionPlanScript.Facade.size() - 1)
	var accent: int = _pick_weighted(rng.randf(), ACCENT_WEIGHTS)
	var lit: float = rng.randf_range(LIT_SHARE.x, LIT_SHARE.y)
	return [style, facade, accent, lit]

static func _pick_weighted(u: float, weights: Array) -> int:
	var total := 0.0
	for w: float in weights:
		total += w
	var running := 0.0
	for k in range(weights.size()):
		running += weights[k] / total
		if u < running:
			return k
	return weights.size() - 1
