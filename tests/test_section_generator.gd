extends SceneTree

const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _plan = SectionGenerator.generate(42, RADIUS, LENGTH)

func _init():
	var failures := 0
	failures += _test_grid_matches_the_terrain_chunks()
	failures += _test_same_index_same_plan()
	failures += _test_different_index_different_plan()
	failures += _test_zone_shares()
	failures += _test_one_city_centre_in_the_middle()
	failures += _test_zones_join_up_where_the_way_round_closes()
	failures += _test_every_crop_appears()
	failures += _test_crops_come_in_patches()
	failures += _test_surface_distance_wraps_around()
	failures += _test_no_road_touches_water()
	failures += _test_road_kinds()
	failures += _test_relief_lots_are_the_highest_five_percent_of_fields()
	failures += _test_no_road_touches_relief()
	failures += _test_same_index_same_heights()
	failures += _test_flat_zones_and_ends_stay_at_zero()
	failures += _test_heights_in_range_and_mountains_only_above_the_threshold()
	failures += _test_heights_join_where_the_way_round_closes()
	failures += _test_buildings_stand_at_level_zero()
	failures += _test_some_chunks_flat_some_raised()
	failures += _test_buildings_only_in_towns_and_city()
	failures += _test_buildings_stay_inside_their_lot_clear_of_roads()
	failures += _test_building_sizes_match_their_zone()
	failures += _test_towers_only_near_the_city_centre()
	failures += _test_buildings_do_not_overlap()
	failures += _test_group_buildings_by_chunk_covers_every_building_once()
	failures += _test_every_building_has_a_look()
	failures += _test_styles_fit_the_zone_and_the_shape()
	failures += _test_looks_vary()
	failures += _test_same_index_same_looks()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _count_zone(plan, zone: int) -> int:
	var count := 0
	for value in plan.zones:
		if value == zone:
			count += 1
	return count

func _test_grid_matches_the_terrain_chunks() -> int:
	# 16 chunks around x 3 lots, 20 chunks along x 4 lots.
	var result := 0
	if not is_equal_approx(_plan.lot_width * 48.0, TAU * RADIUS) or not is_equal_approx(_plan.lot_length, 250.0) or _plan.zones.size() != 3840:
		print("FAIL _test_grid_matches_the_terrain_chunks: lot %f x %f, %d lots" % [_plan.lot_width, _plan.lot_length, _plan.zones.size()])
		result = 1
	return result

func _test_same_index_same_plan() -> int:
	var again = SectionGenerator.generate(42, RADIUS, LENGTH)
	if again.zones != _plan.zones or again.crops != _plan.crops or again.rows_along != _plan.rows_along or again.city_center != _plan.city_center:
		print("FAIL _test_same_index_same_plan: two plans for section 42 differ")
		return 1
	return 0

func _test_different_index_different_plan() -> int:
	var other = SectionGenerator.generate(43, RADIUS, LENGTH)
	if other.zones == _plan.zones:
		print("FAIL _test_different_index_different_plan: sections 42 and 43 have the same zones")
		return 1
	return 0

func _test_zone_shares() -> int:
	# 10% water and 15% town exactly, before the city overwrites some lots.
	var water := _count_zone(_plan, SectionPlan.Zone.WATER)
	var town := _count_zone(_plan, SectionPlan.Zone.TOWN)
	var city := _count_zone(_plan, SectionPlan.Zone.CITY)
	var result := 0
	if city < 15 or city > 35:
		print("FAIL _test_zone_shares: %d city lots, expected about 23 (700 m radius)" % city)
		result = 1
	if water > 384 or water < 384 - city or town > 576 or town < 576 - city:
		print("FAIL _test_zone_shares: water %d (expected 384 minus city), town %d (expected 576 minus city)" % [water, town])
		result = 1
	return result

func _test_one_city_centre_in_the_middle() -> int:
	var result := 0
	if _plan.city_center.y < 0.2 * LENGTH or _plan.city_center.y > 0.8 * LENGTH:
		print("FAIL _test_one_city_centre_in_the_middle: centre at z %f" % _plan.city_center.y)
		result = 1
	for along in range(80):
		for around in range(48):
			var near: bool = _plan.surface_distance(_plan.lot_center(around, along), _plan.city_center) <= 700.0
			var is_city: bool = _plan.zone_at(around, along) == SectionPlan.Zone.CITY
			if near != is_city:
				print("FAIL _test_one_city_centre_in_the_middle: lot (%d, %d) city=%s but within 700 m=%s" % [around, along, is_city, near])
				return 1
	return result

# RELIEF is carved out of fields by a second noise: it counts as field here,
# where the zone noise's own seam is under test.
func _land_use(around: int, along: int) -> int:
	var zone: int = _plan.zone_at(around, along)
	return SectionPlan.Zone.FIELD if zone == SectionPlan.Zone.RELIEF else zone

func _agreement(around_a: int, around_b: int) -> float:
	var same := 0
	for along in range(80):
		if _land_use(around_a, along) == _land_use(around_b, along):
			same += 1
	return same / 80.0

func _test_zones_join_up_where_the_way_round_closes() -> int:
	# Neighbouring lots mostly share a zone (zones are km-sized). If the noise
	# were sampled on the unrolled strip, lots 47 and 0 would be 12 km apart
	# and agree only by chance (~0.6).
	var seam := _agreement(47, 0)
	var inside := _agreement(23, 24)
	if seam < 0.75 or inside < 0.75:
		print("FAIL _test_zones_join_up_where_the_way_round_closes: agreement at the seam %.2f, inside %.2f" % [seam, inside])
		return 1
	return 0

func _test_every_crop_appears() -> int:
	var counts := {}
	for i in range(_plan.zones.size()):
		if _plan.zones[i] == SectionPlan.Zone.FIELD:
			counts[_plan.crops[i]] = counts.get(_plan.crops[i], 0) + 1
	for crop in SectionPlan.Crop.values():
		if counts.get(crop, 0) < 20:
			print("FAIL _test_every_crop_appears: crop %d on %d field lots" % [crop, counts.get(crop, 0)])
			return 1
	return 0

func _test_surface_distance_wraps_around() -> int:
	var c: float = _plan.circumference()
	var result := 0
	if not is_equal_approx(_plan.surface_distance(Vector2(10.0, 0.0), Vector2(c - 10.0, 0.0)), 20.0):
		print("FAIL _test_surface_distance_wraps_around: across the seam %f expected 20" % _plan.surface_distance(Vector2(10.0, 0.0), Vector2(c - 10.0, 0.0)))
		result = 1
	if not is_equal_approx(_plan.surface_distance(Vector2(100.0, 0.0), Vector2(100.0, 300.0)), 300.0):
		print("FAIL _test_surface_distance_wraps_around: along z expected 300")
		result = 1
	return result

func _is_built(zone: int) -> bool:
	return zone == SectionPlan.Zone.TOWN or zone == SectionPlan.Zone.CITY

func _test_no_road_touches_water() -> int:
	for along in range(80):
		for around in range(48):
			if _plan.zone_at(around, along) != SectionPlan.Zone.WATER:
				continue
			if _plan.road_on_west(around, along) + _plan.road_on_east(around, along) + _plan.road_on_south(around, along) + _plan.road_on_north(around, along) != 0:
				print("FAIL _test_no_road_touches_water: lake lot (%d, %d) has a road on an edge" % [around, along])
				return 1
	return 0

func _expected_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	for zone in [zone_a, zone_b]:
		if zone == SectionPlan.Zone.WATER or zone == SectionPlan.Zone.RELIEF:
			return SectionPlan.Road.NONE
	if on_chunk_border:
		return SectionPlan.Road.MAIN
	if _is_built(zone_a) or _is_built(zone_b):
		return SectionPlan.Road.STREET
	return SectionPlan.Road.NONE

func _test_road_kinds() -> int:
	# West edges include lot 0's, shared with lot 47 across the seam.
	for along in range(80):
		for around in range(48):
			var zone: int = _plan.zone_at(around, along)
			var west := _expected_road(zone, _plan.zone_at(around - 1, along), around % 3 == 0)
			var south := SectionPlan.Road.NONE if along == 0 else _expected_road(zone, _plan.zone_at(around, along - 1), along % 4 == 0)
			if _plan.road_on_west(around, along) != west or _plan.road_on_south(around, along) != south:
				print("FAIL _test_road_kinds: lot (%d, %d) west %d (expected %d) south %d (expected %d)" % [around, along, _plan.road_on_west(around, along), west, _plan.road_on_south(around, along), south])
				return 1
	return 0

func _test_relief_lots_are_the_highest_five_percent_of_fields() -> int:
	# 5% of all 3840 lots, taken from fields only: every RELIEF lot's centre
	# is at or above the threshold, every field's below it.
	var noise: FastNoiseLite = SectionGenerator.mountain_noise(_plan.section_index)
	var relief := 0
	var result := 0
	for along in range(80):
		for around in range(48):
			var zone: int = _plan.zone_at(around, along)
			var center: Vector2 = _plan.lot_center(around, along)
			var value: float = noise.get_noise_3dv(SectionGenerator.surface_point(_plan, center.x, center.y))
			if zone == SectionPlan.Zone.RELIEF:
				relief += 1
				if value < _plan.relief_threshold or _plan.surface_distance(center, _plan.city_center) <= SectionGenerator.CITY_RADIUS:
					print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: RELIEF lot (%d, %d) below the threshold or in the city" % [around, along])
					result = 1
			elif zone == SectionPlan.Zone.FIELD and value >= _plan.relief_threshold:
				print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: field lot (%d, %d) above the threshold" % [around, along])
				result = 1
	if relief != 192:
		print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: %d RELIEF lots, expected 192" % relief)
		result = 1
	if _plan.relief_peak < _plan.relief_threshold:
		print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: peak %f below threshold %f" % [_plan.relief_peak, _plan.relief_threshold])
		result = 1
	return result

func _test_no_road_touches_relief() -> int:
	for along in range(80):
		for around in range(48):
			if _plan.zone_at(around, along) != SectionPlan.Zone.RELIEF:
				continue
			if _plan.road_on_west(around, along) + _plan.road_on_east(around, along) + _plan.road_on_south(around, along) + _plan.road_on_north(around, along) != 0:
				print("FAIL _test_no_road_touches_relief: RELIEF lot (%d, %d) has a road on an edge" % [around, along])
				return 1
	return 0

const FLAT_ZONES := [SectionPlan.Zone.TOWN, SectionPlan.Zone.CITY, SectionPlan.Zone.WATER]

func _test_same_index_same_heights() -> int:
	var again = SectionGenerator.generate(42, RADIUS, LENGTH)
	var other = SectionGenerator.generate(43, RADIUS, LENGTH)
	if _plan.heights.size() != 240 * 401 or again.heights != _plan.heights or other.heights == _plan.heights:
		print("FAIL _test_same_index_same_heights: %d heights, same index equal %s, other index differs %s" % [_plan.heights.size(), again.heights == _plan.heights, other.heights != _plan.heights])
		return 1
	return 0

func _test_flat_zones_and_ends_stay_at_zero() -> int:
	# Every grid point inside or on the edge of a town, city or lake lot, and
	# both end rows.
	for along in range(80):
		for around in range(48):
			if not (_plan.zone_at(around, along) in FLAT_ZONES):
				continue
			for row in range(along * 5, along * 5 + 6):
				for column in range(around * 5, around * 5 + 6):
					if absf(_plan.grid_height(column, row)) > 0.001:
						print("FAIL _test_flat_zones_and_ends_stay_at_zero: lot (%d, %d) point (%d, %d) at %f m" % [around, along, column, row, _plan.grid_height(column, row)])
						return 1
	for column in range(240):
		if absf(_plan.grid_height(column, 0)) > 0.001 or absf(_plan.grid_height(column, 400)) > 0.001:
			print("FAIL _test_flat_zones_and_ends_stay_at_zero: end row not flat at column %d" % column)
			return 1
	return 0

func _test_heights_in_range_and_mountains_only_above_the_threshold() -> int:
	var noise: FastNoiseLite = SectionGenerator.mountain_noise(_plan.section_index)
	var step: Vector2 = _plan.height_step()
	var highest := 0.0
	for row in range(401):
		for column in range(240):
			var h: float = _plan.grid_height(column, row)
			highest = maxf(highest, h)
			if h < 0.0 or h > SectionGenerator.MOUNTAIN_HEIGHT + 0.001:
				print("FAIL _test_heights_in_range_and_mountains_only_above_the_threshold: %f m at (%d, %d)" % [h, column, row])
				return 1
			if h > SectionGenerator.HILL_HEIGHT + 0.001:
				var value: float = noise.get_noise_3dv(SectionGenerator.surface_point(_plan, column * step.x, row * step.y))
				if value <= _plan.relief_threshold:
					print("FAIL _test_heights_in_range_and_mountains_only_above_the_threshold: %f m at (%d, %d) with mountain noise below the threshold" % [h, column, row])
					return 1
	if highest < 200.0:
		print("FAIL _test_heights_in_range_and_mountains_only_above_the_threshold: highest point %f m, expected a mountain over 200 m" % highest)
		return 1
	print("  highest point: %.0f m" % highest)
	return 0

func _test_heights_join_where_the_way_round_closes() -> int:
	for k in range(40):
		var z: float = 250.0 + k * 490.0
		if not is_equal_approx(_plan.height_at(0.0, z), _plan.height_at(_plan.circumference(), z)) or absf(_plan.height_at(-1.0, z) - _plan.height_at(_plan.circumference() - 1.0, z)) > 1e-6:
			print("FAIL _test_heights_join_where_the_way_round_closes: at z %f" % z)
			return 1
	return 0

func _test_buildings_stand_at_level_zero() -> int:
	for b in range(_plan.building_count()):
		var size: Vector3 = _plan.building_size[b]
		for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var x: float = _plan.building_x[b] + corner.x * size.x
			var z: float = _plan.building_z[b] + corner.y * size.z
			if absf(_plan.height_at(x, z)) > 0.001:
				print("FAIL _test_buildings_stand_at_level_zero: building %d corner at %f m" % [b, _plan.height_at(x, z)])
				return 1
	return 0

func _test_some_chunks_flat_some_raised() -> int:
	var raised := 0
	for along in range(20):
		for around in range(16):
			if _plan.chunk_has_relief(around, along):
				raised += 1
	print("  chunks with relief: %d of 320" % raised)
	if raised == 0:
		print("FAIL _test_some_chunks_flat_some_raised: no chunk has relief")
		return 1
	return 0

func _test_buildings_only_in_towns_and_city() -> int:
	if _plan.building_count() < 5000:
		print("FAIL _test_buildings_only_in_towns_and_city: only %d buildings" % _plan.building_count())
		return 1
	for b in range(_plan.building_count()):
		if not _is_built(_plan.zones[_plan.building_lot[b]]):
			print("FAIL _test_buildings_only_in_towns_and_city: building %d stands on a field or lake lot" % b)
			return 1
	return 0

func _test_buildings_stay_inside_their_lot_clear_of_roads() -> int:
	# Clear of the widest road: half of 12 m on each side of a lot edge.
	var clearance := 6.0
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		var x0: float = (lot % 48) * _plan.lot_width
		var z0: float = floori(lot / 48.0) * _plan.lot_length
		var size: Vector3 = _plan.building_size[b]
		var left: float = _plan.building_x[b] - size.x * 0.5
		var right: float = _plan.building_x[b] + size.x * 0.5
		var near: float = _plan.building_z[b] - size.z * 0.5
		var far: float = _plan.building_z[b] + size.z * 0.5
		if left < x0 + clearance or right > x0 + _plan.lot_width - clearance or near < z0 + clearance or far > z0 + _plan.lot_length - clearance:
			print("FAIL _test_buildings_stay_inside_their_lot_clear_of_roads: building %d spans x %f..%f z %f..%f in lot x %f.. z %f.." % [b, left, right, near, far, x0, z0])
			return 1
	return 0

func _is_whole(value: float) -> bool:
	return is_equal_approx(value, roundf(value))

func _in_range(value: float, low: float, high: float) -> bool:
	return value >= low - 0.001 and value <= high + 0.001

func _test_building_sizes_match_their_zone() -> int:
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		var size: Vector3 = _plan.building_size[b]
		var ok := _is_whole(size.x) and _is_whole(size.y) and _is_whole(size.z)
		if _plan.zones[lot] == SectionPlan.Zone.TOWN:
			ok = ok and _in_range(size.y, 8.0, 40.0) and _in_range(size.x, 12.0, 25.0) and _in_range(size.z, 12.0, 25.0)
		elif size.y >= 150.0:
			ok = ok and _in_range(size.y, 150.0, 300.0) and _in_range(size.x, 25.0, 45.0) and _in_range(size.z, 25.0, 45.0)
		else:
			ok = ok and _in_range(size.y, 40.0, 120.0) and _in_range(size.x, 30.0, 60.0) and _in_range(size.z, 30.0, 60.0)
		if not ok:
			print("FAIL _test_building_sizes_match_their_zone: building %d size %s in a zone-%d lot" % [b, size, _plan.zones[lot]])
			return 1
	return 0

func _test_towers_only_near_the_city_centre() -> int:
	var towers := 0
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		if _plan.zones[lot] != SectionPlan.Zone.CITY:
			continue
		var center: Vector2 = _plan.lot_center(lot % 48, floori(lot / 48.0))
		var near: bool = _plan.surface_distance(center, _plan.city_center) <= 250.0
		var tower: bool = _plan.building_size[b].y >= 150.0
		if tower:
			towers += 1
		if near != tower:
			print("FAIL _test_towers_only_near_the_city_centre: building %d tower=%s, lot within 250 m=%s" % [b, tower, near])
			return 1
	if towers == 0:
		print("FAIL _test_towers_only_near_the_city_centre: no towers at all")
		return 1
	return 0

func _test_buildings_do_not_overlap() -> int:
	var by_lot := {}
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		if not by_lot.has(lot):
			by_lot[lot] = []
		by_lot[lot].append(b)
	for lot in by_lot:
		var list: Array = by_lot[lot]
		for i in range(list.size()):
			for j in range(i + 1, list.size()):
				var a: int = list[i]
				var c: int = list[j]
				var dx: float = absf(_plan.building_x[a] - _plan.building_x[c])
				var dz: float = absf(_plan.building_z[a] - _plan.building_z[c])
				if dx < (_plan.building_size[a].x + _plan.building_size[c].x) * 0.5 and dz < (_plan.building_size[a].z + _plan.building_size[c].z) * 0.5:
					print("FAIL _test_buildings_do_not_overlap: buildings %d and %d overlap in lot %d" % [a, c, lot])
					return 1
	return 0

func _test_group_buildings_by_chunk_covers_every_building_once() -> int:
	var groups: Dictionary = _plan.group_buildings_by_chunk()
	var seen := {}
	for key in groups:
		for b in groups[key]:
			var lot: int = _plan.building_lot[b]
			var expected := Vector2i(floori((lot % 48) / 3.0), floori(floori(lot / 48.0) / 4.0))
			if key != expected or seen.has(b):
				print("FAIL _test_group_buildings_by_chunk_covers_every_building_once: building %d under %s (expected %s, seen before %s)" % [b, key, expected, seen.has(b)])
				return 1
			seen[b] = true
	if seen.size() != _plan.building_count():
		print("FAIL _test_group_buildings_by_chunk_covers_every_building_once: %d of %d buildings grouped" % [seen.size(), _plan.building_count()])
		return 1
	return 0

func _test_crops_come_in_patches() -> int:
	# Patches: most neighbouring field lots grow the same crop. Picking a crop
	# at random per lot would make ~5 in 6 neighbours differ.
	var pairs := 0
	var same := 0
	for along in range(80):
		for around in range(48):
			if _plan.zone_at(around, along) != SectionPlan.Zone.FIELD:
				continue
			for neighbour in [Vector2i(around + 1, along), Vector2i(around, along + 1)]:
				if neighbour.y >= 80 or _plan.zone_at(neighbour.x, neighbour.y) != SectionPlan.Zone.FIELD:
					continue
				pairs += 1
				if _plan.crops[_plan.lot_index(around, along)] == _plan.crops[_plan.lot_index(neighbour.x, neighbour.y)]:
					same += 1
	var share := float(same) / pairs
	if share < 0.5:
		print("FAIL _test_crops_come_in_patches: only %.0f%% of neighbouring field lots share a crop" % (share * 100.0))
		return 1
	return 0

func _test_every_building_has_a_look() -> int:
	var n: int = _plan.building_count()
	if _plan.building_style.size() != n or _plan.building_facade.size() != n or _plan.building_accent.size() != n or _plan.building_lit.size() != n:
		print("FAIL _test_every_building_has_a_look: %d buildings, looks %d/%d/%d/%d" % [n, _plan.building_style.size(), _plan.building_facade.size(), _plan.building_accent.size(), _plan.building_lit.size()])
		return 1
	for b in range(n):
		if _plan.building_style[b] >= SectionPlan.Style.size() or _plan.building_facade[b] >= SectionPlan.Facade.size() or _plan.building_accent[b] >= SectionPlan.ACCENT_COUNT or not _in_range(_plan.building_lit[b], 0.2, 0.6):
			print("FAIL _test_every_building_has_a_look: building %d look out of range" % b)
			return 1
	return 0

func _test_styles_fit_the_zone_and_the_shape() -> int:
	for b in range(_plan.building_count()):
		var size: Vector3 = _plan.building_size[b]
		var style: int = _plan.building_style[b]
		var allowed: Array
		if _plan.zones[_plan.building_lot[b]] == SectionPlan.Zone.TOWN:
			var low_and_wide: bool = size.y <= 0.7 * minf(size.x, size.z)
			allowed = SectionGenerator.TOWN_LOW_STYLES if low_and_wide else SectionGenerator.TOWN_TALL_STYLES
		elif size.y >= 150.0:
			allowed = SectionGenerator.TOWER_STYLES
		else:
			allowed = SectionGenerator.CITY_STYLES
		if not allowed.has(style):
			print("FAIL _test_styles_fit_the_zone_and_the_shape: building %d size %s has style %d, allowed %s" % [b, size, style, allowed])
			return 1
	return 0

func _test_looks_vary() -> int:
	var styles := {}
	var facades := {}
	var accents := {}
	var magenta := 0
	for b in range(_plan.building_count()):
		styles[_plan.building_style[b]] = true
		facades[_plan.building_facade[b]] = true
		accents[_plan.building_accent[b]] = true
		if _plan.building_accent[b] == 4:
			magenta += 1
	var share: float = float(magenta) / _plan.building_count()
	if styles.size() < 8 or facades.size() != 4 or accents.size() != 5 or share >= 0.1 or share <= 0.0:
		print("FAIL _test_looks_vary: %d styles, %d facades, %d accents, magenta share %.3f" % [styles.size(), facades.size(), accents.size(), share])
		return 1
	return 0

func _test_same_index_same_looks() -> int:
	var again = SectionGenerator.generate(42, RADIUS, LENGTH)
	if again.building_x != _plan.building_x or again.building_style != _plan.building_style or again.building_facade != _plan.building_facade or again.building_accent != _plan.building_accent or again.building_lit != _plan.building_lit:
		print("FAIL _test_same_index_same_looks: two plans for section 42 differ")
		return 1
	return 0
