extends SceneTree

# Road traffic: lanes on the plan's roads, cars at fixed spacing moved by the
# shader only (RoadTraffic.car_at is its GDScript copy). Every car drawn by
# exactly one chunk, no jumps crossing chunks or when TIME rolls over.

const RoadTraffic = preload("res://scripts/road_traffic.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _failures := 0
var _plans := []

func _initialize():
	for index in [2, 5]:
		_plans.append(SectionGenerator.generate(index, RADIUS, LENGTH))
	_failures += _test_runs_cover_every_road_edge_once()
	_failures += _test_loops_spacing_and_whole_laps_per_hour()
	_failures += _test_city_denser_than_town_streets()
	_failures += _test_every_car_drawn_by_one_chunk()
	_failures += _test_cars_on_their_lanes_driving_right()
	_failures += _test_no_jumps_crossing_chunks()
	_failures += _test_same_after_time_rolls_over()
	_failures += _test_far_buffer_holds_every_car_in_section_frame()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _edge_road(plan, along: bool, line: int, edge: int) -> int:
	if along:
		return plan.road_west[plan.lot_index(line, edge)]
	return plan.road_south[plan.lot_index(edge, line)]

func _test_runs_cover_every_road_edge_once() -> int:
	for plan in _plans:
		var seen := {}
		for run: Dictionary in RoadTraffic.runs(plan):
			var edges: int = SectionPlan.LOTS_ALONG if run.along else SectionPlan.LOTS_AROUND
			for k in range(run.count):
				var edge: int = (run.start + k) % edges if not run.along else run.start + k
				var key := Vector3i(int(run.along), run.line, edge)
				var road := _edge_road(plan, run.along, run.line, edge)
				if seen.has(key) or road != run.road or road == SectionPlan.Road.NONE:
					print("FAIL _test_runs_cover_every_road_edge_once: edge %s road %d in run of %d (seen %s)" % [key, road, run.road, seen.has(key)])
					return 1
				seen[key] = true
			if run.closed != (not run.along and run.count == SectionPlan.LOTS_AROUND):
				print("FAIL _test_runs_cover_every_road_edge_once: run %s closed %s" % [run, run.closed])
				return 1
		var total := 0
		for i in range(plan.road_west.size()):
			total += int(plan.road_west[i] != SectionPlan.Road.NONE) + int(plan.road_south[i] != SectionPlan.Road.NONE)
		if total != seen.size():
			print("FAIL _test_runs_cover_every_road_edge_once: %d road edges, %d in runs" % [total, seen.size()])
			return 1
	return 0

func _test_loops_spacing_and_whole_laps_per_hour() -> int:
	for plan in _plans:
		for loop: Dictionary in RoadTraffic.loops(plan):
			var wanted: float = RoadTraffic.spacing(loop.road, loop.city)
			if loop.cars > 2048 or loop.cars < 1 or absf(loop.spacing - wanted) > wanted * 0.5 or not is_equal_approx(loop.spacing * loop.cars, loop.length):
				print("FAIL _test_loops_spacing_and_whole_laps_per_hour: %d cars, %.1f m apart (wanted %.0f) on %.0f m" % [loop.cars, loop.spacing, wanted, loop.length])
				return 1
			var laps: float = loop.speed * 3600.0 / loop.length
			if absf(laps - roundf(laps)) > 0.0001 or laps < 1.0 or absf(loop.speed - RoadTraffic.speed(loop.road)) > RoadTraffic.speed(loop.road) * 0.35:
				print("FAIL _test_loops_spacing_and_whole_laps_per_hour: %.4f laps an hour at %.1f m/s" % [laps, loop.speed])
				return 1
	return 0

func _test_city_denser_than_town_streets() -> int:
	var city := 0.0
	var street := 0.0
	for plan in _plans:
		for loop: Dictionary in RoadTraffic.loops(plan):
			if loop.road == SectionPlan.Road.STREET:
				if loop.city:
					city = loop.spacing
				else:
					street = loop.spacing
	if city <= 0.0 or street <= 0.0 or city > street * 0.6:
		print("FAIL _test_city_denser_than_town_streets: city %.0f m, town %.0f m" % [city, street])
		return 1
	return 0

# Every visible car of a plan at `time`, keyed by (loop seed, car), with its
# section-frame position, forward and up, and the chunk that drew it.
func _cars(plan, by_chunk: Dictionary, time: float) -> Dictionary:
	var cars := {}
	for key: Vector2i in by_chunk:
		var xform := RoadTraffic.chunk_transform(plan, key)
		var data: PackedFloat32Array = by_chunk[key]
		for i in range(data.size() / RoadTraffic.FLOATS):
			var car: Dictionary = RoadTraffic.car_at(data, i, time, plan.radius)
			if not car.visible:
				continue
			var id := Vector2i(car.seed, car.car)
			if cars.has(id):
				cars[id].count += 1
				continue
			cars[id] = {"position": xform * (car.position as Vector3), "forward": xform.basis * (car.forward as Vector3), "up": xform.basis * (car.up as Vector3), "chunk": key, "count": 1}
	return cars

func _test_every_car_drawn_by_one_chunk() -> int:
	var plan = _plans[0]
	var loops := RoadTraffic.loops(plan)
	var by_chunk := RoadTraffic.chunk_instances(plan, loops)
	var expected := 0
	for loop: Dictionary in loops:
		expected += loop.cars
	for time in [0.0, 1.37, 250.9]:
		var cars := _cars(plan, by_chunk, time)
		var doubled := cars.values().filter(func(c: Dictionary) -> bool: return c.count > 1)
		if cars.size() != expected or not doubled.is_empty():
			print("FAIL _test_every_car_drawn_by_one_chunk: at %.2f s %d cars drawn of %d, %d twice" % [time, cars.size(), expected, doubled.size()])
			return 1
	return 0

func _test_cars_on_their_lanes_driving_right() -> int:
	# On the ground (radius 2000, level 0), the road's centre line on the
	# car's left, a lane offset away, on a lot edge.
	var plan = _plans[0]
	var by_chunk := RoadTraffic.chunk_instances(plan, RoadTraffic.loops(plan))
	var cars := _cars(plan, by_chunk, 42.0)
	for car: Dictionary in cars.values():
		var p: Vector3 = car.position
		var radial := Vector2(p.x, p.y).length()
		var up_ok: bool = (car.up as Vector3).dot(-Vector3(p.x, p.y, 0.0).normalized()) > 0.999
		if absf(radial - RADIUS) > 0.01 or not up_ok:
			print("FAIL _test_cars_on_their_lanes_driving_right: car at radius %.3f, up %s" % [radial, car.up])
			return 1
		var right: Vector3 = (car.forward as Vector3).cross(car.up)
		var on_line := false
		for offset in [RoadTraffic.LANE_OFFSET_MAIN, RoadTraffic.LANE_OFFSET_STREET]:
			var centre: Vector3 = p - right * offset
			var x: float = fposmod(atan2(centre.y, centre.x), TAU) * RADIUS
			var z: float = centre.z + LENGTH * 0.5
			var along_line: bool = absf((car.forward as Vector3).z) > 0.99 and absf(x / plan.lot_width - roundf(x / plan.lot_width)) * plan.lot_width < 0.05
			var around_line: bool = absf((car.forward as Vector3).z) < 0.01 and absf(z / plan.lot_length - roundf(z / plan.lot_length)) * plan.lot_length < 0.05
			on_line = on_line or along_line or around_line
		if not on_line:
			print("FAIL _test_cars_on_their_lanes_driving_right: car at %s forward %s off any road's right lane" % [p, car.forward])
			return 1
	return 0

func _test_no_jumps_crossing_chunks() -> int:
	# Small steps: each car moves its speed's worth; only a U-turn at a
	# dead end shifts it across the road (two lane offsets).
	var plan = _plans[0]
	var by_chunk := RoadTraffic.chunk_instances(plan, RoadTraffic.loops(plan))
	var step := 0.05
	var before := _cars(plan, by_chunk, 100.0)
	var crossed := 0
	for k in range(1, 41):
		var after := _cars(plan, by_chunk, 100.0 + k * step)
		for id in after:
			var a: Dictionary = before[id]
			var b: Dictionary = after[id]
			var moved: float = (a.position as Vector3).distance_to(b.position)
			if moved > 40.0 * step + 2.0 * RoadTraffic.LANE_OFFSET_MAIN + 0.01:
				print("FAIL _test_no_jumps_crossing_chunks: car %s jumped %.2f m (chunk %s to %s)" % [id, moved, a.chunk, b.chunk])
				return 1
			if a.chunk != b.chunk:
				crossed += 1
		before = after
	if crossed < 10:
		print("FAIL _test_no_jumps_crossing_chunks: only %d chunk crossings seen" % crossed)
		return 1
	return 0

func _test_same_after_time_rolls_over() -> int:
	var plan = _plans[1]
	var by_chunk := RoadTraffic.chunk_instances(plan, RoadTraffic.loops(plan))
	var a := _cars(plan, by_chunk, 12.5)
	var b := _cars(plan, by_chunk, 3612.5)
	for id in a:
		if not b.has(id) or (a[id].position as Vector3).distance_to(b[id].position) > 0.05:
			print("FAIL _test_same_after_time_rolls_over: car %s differs an hour later" % id)
			return 1
	return 0

func _test_far_buffer_holds_every_car_in_section_frame() -> int:
	# The far buffer: every chunk's instances, moved into the section's frame.
	var plan = _plans[0]
	var by_chunk := RoadTraffic.chunk_instances(plan, RoadTraffic.loops(plan))
	var far := RoadTraffic.section_buffer(plan, by_chunk)
	var near := _cars(plan, by_chunk, 7.0)
	var count := 0
	for i in range(far.size() / RoadTraffic.FLOATS):
		var car: Dictionary = RoadTraffic.car_at(far, i, 7.0, plan.radius)
		if not car.visible:
			continue
		count += 1
		var id := Vector2i(car.seed, car.car)
		if not near.has(id) or (near[id].position as Vector3).distance_to(car.position) > 0.01:
			print("FAIL _test_far_buffer_holds_every_car_in_section_frame: car %s at %s" % [id, car.position])
			return 1
	if count != near.size():
		print("FAIL _test_far_buffer_holds_every_car_in_section_frame: %d far cars, %d near" % [count, near.size()])
		return 1
	return 0
