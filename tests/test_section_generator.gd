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
	failures += _test_surface_distance_wraps_around()

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

func _agreement(around_a: int, around_b: int) -> float:
	var same := 0
	for along in range(80):
		if _plan.zone_at(around_a, along) == _plan.zone_at(around_b, along):
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
