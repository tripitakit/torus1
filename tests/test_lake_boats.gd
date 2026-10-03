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
