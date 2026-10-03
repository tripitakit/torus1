extends SceneTree

# Boats on the lakes: one route per lake (its largest rectangle of water
# lots, inset), always on the water, a few boats each, not too many.

const LakeBoats = preload("res://scripts/lake_boats.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _failures := 0
var _plans := []

func _initialize():
	for index in [2, 5, 11]:
		_plans.append(SectionGenerator.generate(index, RADIUS, LENGTH))
	_failures += _test_lakes_are_water_and_connected()
	_failures += _test_boats_stay_on_the_water()
	_failures += _test_counts()
	_failures += _test_piers_from_the_shore_to_the_route()
	_failures += _test_boats_stop_at_their_pier()
	_failures += _test_life_on_the_piers()
	_failures += _test_no_wake()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_lakes_are_water_and_connected() -> int:
	for plan in _plans:
		var seen := {}
		var total := 0
		for lake: Array in LakeBoats.lakes(plan):
			for lot: Vector2i in lake:
				if plan.zone_at(lot.x, lot.y) != SectionPlan.Zone.WATER or seen.has(lot):
					print("FAIL _test_lakes_are_water_and_connected: lot %s" % lot)
					return 1
				seen[lot] = true
			total += lake.size()
			var rect := LakeBoats.largest_rectangle(plan, lake)
			for i in range(rect.size.x):
				for j in range(rect.size.y):
					if plan.zone_at(rect.position.x + i, rect.position.y + j) != SectionPlan.Zone.WATER:
						print("FAIL _test_lakes_are_water_and_connected: rectangle %s not all water" % rect)
						return 1
		var water := 0
		for zone in plan.zones:
			water += int(zone == SectionPlan.Zone.WATER)
		if total != water:
			print("FAIL _test_lakes_are_water_and_connected: %d lots in lakes of %d water lots" % [total, water])
			return 1
	return 0

func _test_boats_stay_on_the_water() -> int:
	# Every 10 m round every route, the boat and 30 m to either side are on
	# water lots.
	for plan in _plans:
		for loop: Dictionary in LakeBoats.routes(plan):
			var s := 0.0
			while s < LoopTraffic.loop_length(loop):
				var f := LoopTraffic.pose(loop, s)
				for side in [-30.0, 0.0, 30.0]:
					var p: Vector3 = f.origin + f.basis.x * side
					var x: float = fposmod(atan2(p.y, p.x), TAU) * RADIUS
					var z: float = p.z + LENGTH * 0.5
					if plan.zone_at(floori(x / plan.lot_width), floori(z / plan.lot_length)) != SectionPlan.Zone.WATER:
						print("FAIL _test_boats_stay_on_the_water: off the water at %s" % p)
						return 1
				if absf(Vector2(f.origin.x, f.origin.y).length() - RADIUS) > 0.01:
					print("FAIL _test_boats_stay_on_the_water: not on the surface")
					return 1
				s += 10.0
	return 0

func _test_counts() -> int:
	for plan in _plans:
		var boats := LakeBoats.routes(plan)
		var lakes := LakeBoats.lakes(plan)
		if boats.size() > LakeBoats.MAX_BOATS or (not lakes.is_empty() and boats.is_empty()):
			print("FAIL _test_counts: %d boats on %d lakes" % [boats.size(), lakes.size()])
			return 1
	return 0

# Plan x is unrolled and may run past the circumference: compare round it.
func _round_distance(a: Vector2, b: Vector2) -> float:
	var circumference := TAU * RADIUS
	var dx := fposmod(a.x - b.x + circumference * 0.5, circumference) - circumference * 0.5
	return Vector2(dx, a.y - b.y).length()

func _zone(plan, p: Vector2) -> int:
	return plan.zone_at(floori(p.x / plan.lot_width), floori(p.y / plan.lot_length))

func _test_piers_from_the_shore_to_the_route() -> int:
	var any := false
	for plan in _plans:
		for pier: Dictionary in LakeBoats.piers(plan):
			any = true
			var deck: Rect2 = pier.deck
			var platform: Rect2 = pier.platform
			# The deck's far end is over water, the platform on flat land.
			if _zone(plan, pier.end) != SectionPlan.Zone.WATER or _zone(plan, platform.get_center()) == SectionPlan.Zone.WATER or SectionPlan.is_raised(_zone(plan, platform.get_center())):
				print("FAIL _test_piers_from_the_shore_to_the_route: pier %s on the wrong ground" % pier)
				return 1
			if not deck.intersects(platform) or deck.size.x < 10.0 or deck.size.y < 10.0:
				print("FAIL _test_piers_from_the_shore_to_the_route: deck %s, platform %s" % [deck, platform])
				return 1
	if not any:
		print("FAIL _test_piers_from_the_shore_to_the_route: no piers at all")
		return 1
	return 0

func _test_boats_stop_at_their_pier() -> int:
	for plan in _plans:
		var piers := LakeBoats.piers(plan)
		for loop: Dictionary in LakeBoats.routes(plan):
			if loop.stop < 0.0:
				continue
			var p := LoopTraffic.pose(loop, loop.stop).origin
			var x: float = fposmod(atan2(p.y, p.x), TAU) * RADIUS
			var at := Vector2(x, p.z + LENGTH * 0.5)
			var nearest := INF
			for pier: Dictionary in piers:
				nearest = minf(nearest, _round_distance(at, pier.end))
			if nearest > 6.0:
				print("FAIL _test_boats_stop_at_their_pier: stop %.1f m from the nearest pier's end" % nearest)
				return 1
	return 0

func _test_life_on_the_piers() -> int:
	# People on the platform, carts on the deck and platform, drones above
	# them: every point within the pier's footprint (plan x, z), at its height.
	for plan in _plans:
		for pier: Dictionary in LakeBoats.piers(plan):
			var footprint: Rect2 = (pier.deck as Rect2).merge(pier.platform).grow(1.0)
			for part in [["people", LakeBoats.pier_people(plan, pier)], ["carts", LakeBoats.pier_carts(plan, pier)], ["drones", LakeBoats.pier_drones(plan, pier)]]:
				if (part[1] as Array).is_empty():
					print("FAIL _test_life_on_the_piers: no %s" % part[0])
					return 1
				for loop: Dictionary in part[1]:
					var s := 0.0
					while s < LoopTraffic.loop_length(loop):
						var p := LoopTraffic.pose(loop, s).origin
						var radius := Vector2(p.x, p.y).length()
						var at := Vector2(fposmod(atan2(p.y, p.x), TAU) * RADIUS, p.z + LENGTH * 0.5)
						var height := RADIUS - radius
						var wanted_height: float = LakeBoats.DECK_HEIGHT if part[0] != "drones" else LakeBoats.DRONE_HEIGHT
						var inside := footprint.has_point(at) or footprint.has_point(at + Vector2(TAU * RADIUS, 0.0)) or footprint.has_point(at - Vector2(TAU * RADIUS, 0.0))
						if not inside or absf(height - wanted_height) > 0.05:
							print("FAIL _test_life_on_the_piers: %s at %s, %.2f m up, outside %s" % [part[0], at, height, footprint])
							return 1
						s += 1.0
	return 0

func _test_no_wake() -> int:
	# Nothing flat on the water behind the stern (it flickered).
	var box := LakeBoats.boat_mesh().get_aabb()
	if box.position.z < -5.5:
		print("FAIL _test_no_wake: the boat reaches %.1f m behind" % -box.position.z)
		return 1
	return 0
