extends RefCounted

# Builds the plan of one section's inner surface from the section's index
# alone: same index, same plan, every time (piece C regenerates sections as
# the player travels). Packed arrays are built in locals and assigned whole.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const WATER_SHARE := 0.10
const TOWN_SHARE := 0.15
const ZONE_FEATURE_SIZE := 2500.0
const CROP_FEATURE_SIZE := 800.0
# Crop bands per unit of noise: neighbouring patches get different crops.
const CROP_BANDS := 9.0
const CITY_RADIUS := 700.0
# Share of the length, from each end, the city centre keeps away from.
const CITY_END_MARGIN := 0.2

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
	plan.crops = _crops(plan)
	plan.rows_along = _rows(plan)
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

static func _crops(plan) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = plan.section_index + 7919
	noise.frequency = 1.0 / CROP_FEATURE_SIZE
	var crop_count: int = SectionPlanScript.Crop.size()
	var crops := PackedByteArray()
	for value in _sample_lots(plan, noise):
		crops.append(posmod(floori((value + 1.0) * CROP_BANDS), crop_count))
	return crops

static func _rows(plan) -> PackedByteArray:
	var rows := PackedByteArray()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.section_index, around, along, "rows"])
			rows.append(rng.randi_range(0, 1))
	return rows
