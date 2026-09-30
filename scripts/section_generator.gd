extends RefCounted

# Builds the plan of one section's inner surface from the section's index
# alone: same index, same plan, every time (piece C regenerates sections as
# the player travels). Packed arrays are built in locals and assigned whole.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const WATER_SHARE := 0.10
const TOWN_SHARE := 0.15
# Hills: HILL_SHARE of all lots, taken from fields where a patch noise is
# highest; patches of fewer than HILL_MIN_LOTS lots go back to field.
const HILL_SHARE := 0.12
const HILL_MIN_LOTS := 4
const HILL_PATCH_SIZE := 2000.0
const HILL_FEATURE_SIZE := 700.0
const HILL_HEIGHTS := Vector2(50.0, 150.0)
# Heights fade to 0 within this of flat land (field, town, city, lake) or an
# end wall, inside the raised lots: flat land stays exactly flat.
const RELIEF_BLEND := 250.0
# The mountain chain, in about CHAIN_CHANCE of the sections: a ridge along
# the section, CHAIN_LENGTHS long, CHAIN_END_MARGIN clear of both end walls,
# its line wandering CHAIN_MEANDER either way. Along it one noise
# (CHAIN_FEATURE_SIZE) sets both the crest and the half width: wide high
# massifs, narrow low saddles. The ends taper over CHAIN_TAPER. Flanks get
# spurs and valleys from a ridged noise (CHAIN_DETAIL_SIZE). No spires: they
# read as needles. Nothing above MOUNTAIN_HEIGHT. A lot whose centre the chain
# raises past MOUNTAIN_LOT_MIN is MOUNTAIN.
const CHAIN_CHANCE := 1.0 / 3.0
const CHAIN_LENGTHS := Vector2(6000.0, 12000.0)
const CHAIN_END_MARGIN := 2000.0
const CHAIN_MEANDER := 400.0
const CHAIN_CREST := Vector2(600.0, 1350.0)
const CHAIN_HALF_WIDTH := Vector2(1000.0, 2000.0)
const CHAIN_TAPER := 1500.0
const CHAIN_FEATURE_SIZE := 3000.0
const CHAIN_DETAIL_SIZE := 600.0
const MOUNTAIN_HEIGHT := 1500.0
const MOUNTAIN_LOT_MIN := 20.0
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
	var chain := chain_of(plan)
	plan.has_chain = chain != null
	plan.zones = _with_mountain(plan, plan.zones, chain)
	plan.zones = _with_hills(plan, plan.zones)
	plan.crops = _crops(plan)
	plan.rows_along = _rows(plan)
	var roads: Array = _roads(plan)
	plan.road_west = roads[0]
	plan.road_south = roads[1]
	_place_buildings(plan)
	plan.heights = _heights(plan, chain)
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

# A point of the unrolled surface on the cylinder in 3D, where the noises are
# sampled: the way round closes with no seam.
static func surface_point(plan, x: float, z: float) -> Vector3:
	var angle: float = x / plan.radius
	return Vector3(cos(angle) * plan.radius, sin(angle) * plan.radius, z)

# A section's mountain chain: a ridge along the section. height() is read
# for every lot centre and grid point, on the generator's worker thread.
class Chain:
	extends RefCounted
	var circumference := 0.0
	var radius := 0.0
	var x0 := 0.0
	var z0 := 0.0
	var z1 := 0.0
	var meander: FastNoiseLite
	var massif: FastNoiseLite
	var detail: FastNoiseLite

	func ridge_x(z: float) -> float:
		return x0 + CHAIN_MEANDER * meander.get_noise_1d(z)

	# Distance between two x the short way round.
	func _gap(a: float, b: float) -> float:
		return absf(fposmod(a - b + circumference * 0.5, circumference) - circumference * 0.5)

	func height(x: float, z: float) -> float:
		if z <= z0 or z >= z1:
			return 0.0
		var dx: float = _gap(x, ridge_x(z))
		if dx >= CHAIN_HALF_WIDTH.y:
			return 0.0
		# The noise mostly stays within +-0.6: stretched, massifs and saddles
		# use the whole crest range.
		var bulk: float = clampf(0.5 + 0.8 * massif.get_noise_1d(z), 0.0, 1.0)
		var taper: float = smoothstep(0.0, CHAIN_TAPER, z - z0) * smoothstep(0.0, CHAIN_TAPER, z1 - z)
		var p: float = clampf(1.0 - dx / lerpf(CHAIN_HALF_WIDTH.x, CHAIN_HALF_WIDTH.y, bulk), 0.0, 1.0)
		var h := 0.0
		if p > 0.0:
			# Ridged noise on the flanks: spurs, and the valleys between them.
			var angle: float = x / radius
			var ridged: float = 1.0 - absf(detail.get_noise_3d(cos(angle) * radius, sin(angle) * radius, z))
			h = taper * lerpf(CHAIN_CREST.x, CHAIN_CREST.y, bulk) * pow(p, 1.4) * (0.7 + 0.45 * ridged)
		return minf(h, MOUNTAIN_HEIGHT)

static func _chain_rng(section_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([section_index, "chain"])
	return rng

static func chain_wanted(section_index: int) -> bool:
	return _chain_rng(section_index).randf() < CHAIN_CHANCE

# The section's chain, or null: opposite the city round the section (give or
# take an eighth of a turn), CHAIN_END_MARGIN clear of both end walls.
static func chain_of(plan) -> Chain:
	var rng := _chain_rng(plan.section_index)
	if rng.randf() >= CHAIN_CHANCE:
		return null
	var chain := Chain.new()
	chain.circumference = plan.circumference()
	chain.radius = plan.radius
	var chain_length: float = minf(rng.randf_range(CHAIN_LENGTHS.x, CHAIN_LENGTHS.y), plan.length - 2.0 * CHAIN_END_MARGIN)
	chain.z0 = rng.randf_range(CHAIN_END_MARGIN, plan.length - CHAIN_END_MARGIN - chain_length)
	chain.z1 = chain.z0 + chain_length
	chain.x0 = fposmod(plan.city_center.x + chain.circumference * rng.randf_range(0.375, 0.625), chain.circumference)
	chain.meander = _noise(hash([plan.section_index, "meander"]), CHAIN_FEATURE_SIZE, 2)
	chain.massif = _noise(hash([plan.section_index, "massif"]), CHAIN_FEATURE_SIZE, 3)
	chain.detail = _noise(hash([plan.section_index, "detail"]), CHAIN_DETAIL_SIZE, 3)
	return chain

# Every lot but the city's whose centre the chain raises past
# MOUNTAIN_LOT_MIN becomes MOUNTAIN, lakes and towns included.
static func _with_mountain(plan, zones: PackedByteArray, chain: Chain) -> PackedByteArray:
	if chain == null:
		return zones
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var i: int = plan.lot_index(around, along)
			var center: Vector2 = plan.lot_center(around, along)
			if zones[i] != SectionPlanScript.Zone.CITY and chain.height(center.x, center.y) > MOUNTAIN_LOT_MIN:
				zones[i] = SectionPlanScript.Zone.MOUNTAIN
	return zones

static func _noise(seed_value: int, feature_size: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0 / feature_size
	noise.fractal_octaves = octaves
	return noise

# The field lots where a patch noise is highest, HILL_SHARE of all lots,
# become HILL; patches too small to read as hills go back to field.
static func _with_hills(plan, zones: PackedByteArray) -> PackedByteArray:
	var values := _sample_lots(plan, _noise(hash([plan.section_index, "hill patches"]), HILL_PATCH_SIZE, 2))
	var field_values := PackedFloat64Array()
	for i in range(values.size()):
		if zones[i] == SectionPlanScript.Zone.FIELD:
			field_values.append(values[i])
	var count: int = mini(int(values.size() * HILL_SHARE), field_values.size())
	if count == 0:
		return zones
	field_values.sort()
	var threshold: float = field_values[field_values.size() - count]
	for i in range(values.size()):
		if zones[i] == SectionPlanScript.Zone.FIELD and values[i] >= threshold:
			zones[i] = SectionPlanScript.Zone.HILL
	return _without_small_hills(plan, zones)

# Hill patches (lots sharing an edge; the way round closes) of fewer than
# HILL_MIN_LOTS lots go back to field.
@warning_ignore("integer_division")
static func _without_small_hills(plan, zones: PackedByteArray) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(zones.size())
	for start in range(zones.size()):
		if zones[start] != SectionPlanScript.Zone.HILL or seen[start] == 1:
			continue
		seen[start] = 1
		var patch := [start]
		var k := 0
		while k < patch.size():
			var i: int = patch[k]
			k += 1
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var along: int = i / SectionPlanScript.LOTS_AROUND + step.y
				if along < 0 or along >= SectionPlanScript.LOTS_ALONG:
					continue
				var j: int = plan.lot_index(i % SectionPlanScript.LOTS_AROUND + step.x, along)
				if zones[j] == SectionPlanScript.Zone.HILL and seen[j] == 0:
					seen[j] = 1
					patch.append(j)
		if patch.size() < HILL_MIN_LOTS:
			for i: int in patch:
				zones[i] = SectionPlanScript.Zone.FIELD
	return zones

# For each lot, the rectangles (x0, z0, x1, z1) of the lots among it and its
# 8 neighbours whose zone `wanted` accepts. RELIEF_BLEND is under one lot, so
# no farther lot can be nearer than it. Lots next to the seam get the
# neighbour across it at its unrolled position (x below 0 or past the
# circumference).
static func _rects_by_lot(plan, wanted: Callable) -> Array:
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
					if wanted.call(plan.zone_at(lot_x, lot_z)):
						rects.append(Rect2(lot_x * plan.lot_width, lot_z * plan.lot_length, plan.lot_width, plan.lot_length))
			by_lot.append(rects)
	return by_lot

# Distance from (x, z) to the nearest of `rects` or to an end wall. A point
# inside or on the edge of one of them is at 0.
static func _rect_distance(plan, x: float, z: float, rects: Array) -> float:
	var nearest: float = minf(z, plan.length - z)
	for rect: Rect2 in rects:
		var gap_x: float = maxf(0.0, maxf(rect.position.x - x, x - rect.end.x))
		var gap_z: float = maxf(0.0, maxf(rect.position.y - z, z - rect.end.y))
		nearest = minf(nearest, Vector2(gap_x, gap_z).length())
	return nearest

# Heights only inside raised lots, fading to 0 within RELIEF_BLEND of flat
# land or an end wall: the chain's and, in hill lots, the hills', whichever
# is higher.
@warning_ignore("integer_division")
static func _heights(plan, chain) -> PackedFloat32Array:
	var hills := _noise(hash([plan.section_index, "hills"]), HILL_FEATURE_SIZE, 2)
	var flat_rects := _rects_by_lot(plan, func(zone: int) -> bool: return not SectionPlanScript.is_raised(zone))
	var open_rects := _rects_by_lot(plan, func(zone: int) -> bool: return zone != SectionPlanScript.Zone.HILL)
	var step: Vector2 = plan.height_step()
	var heights := PackedFloat32Array()
	heights.resize(SectionPlanScript.RELIEF_COLUMNS * SectionPlanScript.RELIEF_ROWS)
	for row in range(SectionPlanScript.RELIEF_ROWS):
		var z: float = row * step.y
		var along: int = mini(row / SectionPlanScript.RELIEF_POINTS_PER_LOT, SectionPlanScript.LOTS_ALONG - 1)
		for column in range(SectionPlanScript.RELIEF_COLUMNS):
			var x: float = column * step.x
			var lot: int = along * SectionPlanScript.LOTS_AROUND + column / SectionPlanScript.RELIEF_POINTS_PER_LOT
			var flat := _rect_distance(plan, x, z, flat_rects[lot])
			if flat <= 0.0:
				continue  # resize() filled it with 0
			var h := 0.0
			if chain != null:
				h = chain.height(x, z) * smoothstep(0.0, RELIEF_BLEND, flat)
			var open := _rect_distance(plan, x, z, open_rects[lot])
			if open > 0.0:
				var bump: float = clampf((hills.get_noise_3dv(surface_point(plan, x, z)) + 1.0) * 0.5, 0.0, 1.0)
				h = maxf(h, lerpf(HILL_HEIGHTS.x, HILL_HEIGHTS.y, bump) * smoothstep(0.0, RELIEF_BLEND, open))
			heights[row * SectionPlanScript.RELIEF_COLUMNS + column] = h
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

# No road next to a lake, a hill or a mountain; a main road on every chunk
# border; a street next to a town or the city; nothing between two fields.
static func _edge_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	for zone in [zone_a, zone_b]:
		if zone == SectionPlanScript.Zone.WATER or SectionPlanScript.is_raised(zone):
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
