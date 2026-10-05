extends SceneTree

# People walking in the towns and the city: on loops in the open spaces
# between buildings, never through a building, never on a road; plenty of
# them in every built lot.

const TownWalkers = preload("res://scripts/town_walkers.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _failures := 0
var _plan

func _initialize():
	_plan = SectionGenerator.generate(5, RADIUS, LENGTH)
	_failures += _test_walkers_in_open_town_ground()
	_failures += _test_plenty_in_every_built_lot()
	_failures += _test_near_groups_cover_their_walkers()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _built(zone: int) -> bool:
	return zone == SectionPlan.Zone.TOWN or zone == SectionPlan.Zone.CITY

func _test_walkers_in_open_town_ground() -> int:
	var plan = _plan
	var circumference: float = TAU * RADIUS
	var start := Time.get_ticks_msec()
	var by_chunk := TownWalkers.loops_by_chunk(plan)
	print("  walkers made in %d ms" % (Time.get_ticks_msec() - start))
	var by_lot := {}
	for b in range(plan.building_count()):
		if not by_lot.has(plan.building_lot[b]):
			by_lot[plan.building_lot[b]] = []
		by_lot[plan.building_lot[b]].append(b)
	for key: Vector2i in by_chunk:
		for loop: Dictionary in by_chunk[key]:
			var s := 0.0
			while s < LoopTraffic.loop_length(loop):
				var p := LoopTraffic.pose(loop, s).origin
				var x: float = fposmod(atan2(p.y, p.x), TAU) * RADIUS
				var z: float = p.z + LENGTH * 0.5
				var around := floori(x / plan.lot_width)
				var along := floori(z / plan.lot_length)
				if not _built(plan.zone_at(around, along)):
					print("FAIL _test_walkers_in_open_town_ground: walker outside town at %.1f, %.1f" % [x, z])
					return 1
				# Not on the lot's edge roads.
				var lx: float = x - around * plan.lot_width
				var lz: float = z - along * plan.lot_length
				var west: float = SectionPlan.road_width(plan.road_on_west(around, along)) * 0.5
				var east: float = SectionPlan.road_width(plan.road_on_east(around, along)) * 0.5
				var south: float = SectionPlan.road_width(plan.road_on_south(around, along)) * 0.5
				var north: float = SectionPlan.road_width(plan.road_on_north(around, along)) * 0.5
				if lx < west + 1.0 or lx > plan.lot_width - east - 1.0 or lz < south + 1.0 or lz > plan.lot_length - north - 1.0:
					print("FAIL _test_walkers_in_open_town_ground: walker on a road at %.1f, %.1f" % [x, z])
					return 1
				# Clear of every building of the lot.
				for b: int in by_lot.get(plan.lot_index(around, along), []):
					var size: Vector3 = plan.building_size[b]
					var dx: float = absf(fposmod(x - plan.building_x[b] + circumference * 0.5, circumference) - circumference * 0.5)
					var dz: float = absf(z - plan.building_z[b])
					if dx < size.x * 0.5 + 1.0 and dz < size.z * 0.5 + 1.0:
						print("FAIL _test_walkers_in_open_town_ground: walker inside building %d at %.1f, %.1f" % [b, x, z])
						return 1
				s += 3.0
	return 0

func _test_plenty_in_every_built_lot() -> int:
	var plan = _plan
	var per_lot := {}
	for loops: Array in TownWalkers.loops_by_chunk(plan).values():
		for loop: Dictionary in loops:
			per_lot[loop.lot] = per_lot.get(loop.lot, 0) + 1
	var built := 0
	for i in range(plan.zones.size()):
		built += int(_built(plan.zones[i]))
	var total := 0
	for lot in per_lot:
		total += per_lot[lot]
		if per_lot[lot] > TownWalkers.PER_LOT.y:
			print("FAIL _test_plenty_in_every_built_lot: %d walkers in lot %d" % [per_lot[lot], lot])
			return 1
	if per_lot.size() < built * 0.9 or total < built * TownWalkers.PER_LOT.x * 0.8:
		print("FAIL _test_plenty_in_every_built_lot: %d walkers in %d of %d built lots" % [total, per_lot.size(), built])
		return 1
	return 0

# The animated walkers go in small groups (one per lot), each drawn while
# the camera is within LoopTraffic.DETAIL_TO of any of its walkers: its
# bounds hold every walker (feet and head) all round their loops, and its
# visibility range (measured to the bounds' centre) reaches DETAIL_TO past
# the bounds' farthest corner.
func _test_near_groups_cover_their_walkers() -> int:
	for loops: Array in TownWalkers.loops_by_chunk(_plan).values():
		var groups := TownWalkers.near_groups(loops)
		var count := 0
		for group in groups:
			count += (group.loops as Array).size()
			var bounds: AABB = group.bounds
			var reach: float = TownWalkers.near_range(bounds)
			if reach < LoopTraffic.DETAIL_TO + bounds.size.length() * 0.5:
				print("FAIL _test_near_groups_cover_their_walkers: range %.1f for bounds %s" % [reach, bounds.size])
				return 1
			if reach > LoopTraffic.DETAIL_TO + 400.0:
				print("FAIL _test_near_groups_cover_their_walkers: range %.1f, the group is too big" % reach)
				return 1
			for loop: Dictionary in group.loops:
				for k in range(12):
					var pose := LoopTraffic.pose(loop, LoopTraffic.loop_length(loop) * k / 12.0)
					for point in [pose.origin, pose.origin + pose.basis.y * 1.8]:
						if not bounds.grow(0.01).has_point(point):
							print("FAIL _test_near_groups_cover_their_walkers: %s outside %s" % [point, bounds])
							return 1
		if count != loops.size():
			print("FAIL _test_near_groups_cover_their_walkers: %d of %d walkers grouped" % [count, loops.size()])
			return 1
	return 0
