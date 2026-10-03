extends SceneTree

# Air traffic inside: stadium circuits along the section and rings round it,
# clear of the spine's pylons and well above the ground, cruisers flying
# them smoothly, banking in the circuits' turns.

const AirTraffic = preload("res://scripts/air_traffic.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _failures := 0
var _plans := []

func _initialize():
	# Section 2 has a mountain chain (see test_road_traffic's plans).
	for index in [2, 5, 11]:
		_plans.append(SectionGenerator.generate(index, RADIUS, LENGTH))
	_failures += _test_lanes_per_section()
	_failures += _test_clear_of_the_pylons()
	_failures += _test_high_above_the_ground()
	_failures += _test_paths_are_continuous_and_closed()
	_failures += _test_cruisers_spread_and_moving()
	_failures += _test_bank_in_turns_only()
	_failures += _test_instance_data_gives_the_same_pose()
	_failures += _test_short_wings()
	_failures += _test_cruiser_counts_vary()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _count(lanes: Array, kind: int) -> int:
	return lanes.filter(func(l: Dictionary) -> bool: return l.kind == kind).size()

func _test_lanes_per_section() -> int:
	for plan in _plans:
		var lanes := AirTraffic.lanes(plan)
		# Fewer circuits where a mountain chain takes their place.
		var circuits := _count(lanes, AirTraffic.CIRCUIT)
		if circuits < 3 or circuits > AirTraffic.CIRCUITS or _count(lanes, AirTraffic.RING) != AirTraffic.RINGS:
			print("FAIL _test_lanes_per_section: %d circuits, %d rings" % [circuits, _count(lanes, AirTraffic.RING)])
			return 1
		# A random number of cruisers a section, at least two a lane.
		var count := AirTraffic.cruiser_count(lanes)
		if count < AirTraffic.CRAFT.x or count > AirTraffic.CRAFT.y or lanes.any(func(l: Dictionary) -> bool: return l.craft < 2):
			print("FAIL _test_lanes_per_section: %d cruisers" % count)
			return 1
		# The same plan gives the same lanes.
		if str(AirTraffic.lanes(plan)) != str(lanes):
			print("FAIL _test_lanes_per_section: lanes not deterministic")
			return 1
	return 0

func _test_clear_of_the_pylons() -> int:
	# Circuits at least 30 degrees round from the spine; rings at least 300 m
	# along from the stations.
	var spine := SpineTrain.spine_angle()
	for plan in _plans:
		var zs := SpineTrain.station_z(plan)
		for lane: Dictionary in AirTraffic.lanes(plan):
			if lane.kind == AirTraffic.CIRCUIT:
				var gap := absf(angle_difference(lane.angle, spine))
				if gap < deg_to_rad(29.9):
					print("FAIL _test_clear_of_the_pylons: circuit %.1f deg from the spine" % rad_to_deg(gap))
					return 1
			else:
				for z: float in zs:
					if absf(lane.z - z) < 300.0:
						print("FAIL _test_clear_of_the_pylons: ring at %.0f, station at %.0f" % [lane.z, z])
						return 1
	return 0

func _test_high_above_the_ground() -> int:
	# Every 25 m along every lane, the cruiser is at least CLEARANCE above
	# the ground right under it.
	for plan in _plans:
		for lane: Dictionary in AirTraffic.lanes(plan):
			var s := 0.0
			while s < AirTraffic.lane_length(lane):
				var p: Vector3 = AirTraffic.pose(lane, s, plan).origin
				var angle := fposmod(atan2(p.y, p.x), TAU)
				var ground: float = RADIUS - plan.height_at(angle * RADIUS, p.z + LENGTH * 0.5)
				var above := ground - Vector2(p.x, p.y).length()
				if above < AirTraffic.CLEARANCE - 1.0:
					print("FAIL _test_high_above_the_ground: %.0f m above ground at %s (lane %d)" % [above, p, lane.kind])
					return 1
				s += 25.0
	return 0

func _test_paths_are_continuous_and_closed() -> int:
	var plan = _plans[0]
	for lane: Dictionary in AirTraffic.lanes(plan):
		var length := AirTraffic.lane_length(lane)
		var step := 1.0
		var last := AirTraffic.pose(lane, 0.0, plan)
		var s := step
		while s <= length + 0.001:
			var now := AirTraffic.pose(lane, s, plan)
			var moved := last.origin.distance_to(now.origin)
			if moved > step * 1.05 or moved < step * 0.9:
				print("FAIL _test_paths_are_continuous_and_closed: lane %d jumps %.3f m at s %.1f" % [lane.kind, moved, s])
				return 1
			# Facing the way it goes.
			if now.basis.z.dot((now.origin - last.origin).normalized()) < 0.99:
				print("FAIL _test_paths_are_continuous_and_closed: lane %d not facing its way at s %.1f" % [lane.kind, s])
				return 1
			last = now
			s += step
		if AirTraffic.pose(lane, 0.0, plan).origin.distance_to(AirTraffic.pose(lane, length, plan).origin) > 0.01:
			print("FAIL _test_paths_are_continuous_and_closed: lane %d does not close" % lane.kind)
			return 1
	return 0

func _test_cruisers_spread_and_moving() -> int:
	var plan = _plans[1]
	var lanes := AirTraffic.lanes(plan)
	var a := AirTraffic.buffer(lanes, plan, 50.0)
	var b := AirTraffic.buffer(lanes, plan, 51.0)
	var count := AirTraffic.cruiser_count(lanes)
	if a.size() != count * AirTraffic.FLOATS:
		print("FAIL _test_cruisers_spread_and_moving: buffer of %d floats" % a.size())
		return 1
	for i in range(count):
		var pa := Vector3(a[i * AirTraffic.FLOATS + 3], a[i * AirTraffic.FLOATS + 7], a[i * AirTraffic.FLOATS + 11])
		var pb := Vector3(b[i * AirTraffic.FLOATS + 3], b[i * AirTraffic.FLOATS + 7], b[i * AirTraffic.FLOATS + 11])
		var moved := pa.distance_to(pb)
		if moved < 55.0 or moved > 95.0:
			print("FAIL _test_cruisers_spread_and_moving: cruiser %d moved %.1f m in 1 s" % [i, moved])
			return 1
		for j in range(i):
			var pj := Vector3(a[j * AirTraffic.FLOATS + 3], a[j * AirTraffic.FLOATS + 7], a[j * AirTraffic.FLOATS + 11])
			if pa.distance_to(pj) < 50.0:
				print("FAIL _test_cruisers_spread_and_moving: cruisers %d and %d %.1f m apart" % [i, j, pa.distance_to(pj)])
				return 1
	return 0

func _test_bank_in_turns_only() -> int:
	# Up is straight toward the axis on the straights and on the rings;
	# tilted BANK in a circuit's turn, toward the turn's centre.
	var plan = _plans[0]
	for lane: Dictionary in AirTraffic.lanes(plan):
		if lane.kind != AirTraffic.CIRCUIT:
			var ring := AirTraffic.pose(lane, 100.0, plan)
			if ring.basis.y.dot(-Vector3(ring.origin.x, ring.origin.y, 0.0).normalized()) < 0.999:
				print("FAIL _test_bank_in_turns_only: ring not level")
				return 1
			continue
		var straight := AirTraffic.pose(lane, 100.0, plan)
		var toward_axis := -Vector3(straight.origin.x, straight.origin.y, 0.0).normalized()
		if straight.basis.y.dot(toward_axis) < 0.999:
			print("FAIL _test_bank_in_turns_only: tilted on a straight")
			return 1
		var turn_s: float = AirTraffic.leg_length(lane) + PI * AirTraffic.TURN_RADIUS * 0.5
		var turn := AirTraffic.pose(lane, turn_s, plan)
		var level := -Vector3(turn.origin.x, turn.origin.y, 0.0).normalized()
		var tilt := rad_to_deg(acos(clampf(turn.basis.y.dot(level), -1.0, 1.0)))
		if absf(tilt - rad_to_deg(AirTraffic.BANK)) > 1.0:
			print("FAIL _test_bank_in_turns_only: %.1f deg bank in the turn" % tilt)
			return 1
		return 0
	return 0

func _test_instance_data_gives_the_same_pose() -> int:
	# The shader reads each cruiser's lane from its instance basis
	# (AirTraffic.instance_buffer); pose_from_data is its GDScript copy.
	var plan = _plans[1]
	var lanes := AirTraffic.lanes(plan)
	var data := AirTraffic.instance_buffer(lanes, plan)
	var cpu := AirTraffic.buffer(lanes, plan, 77.7)
	for i in range(AirTraffic.cruiser_count(lanes)):
		var pose := AirTraffic.pose_from_data(data, i, 77.7)
		var expected := Vector3(cpu[i * AirTraffic.FLOATS + 3], cpu[i * AirTraffic.FLOATS + 7], cpu[i * AirTraffic.FLOATS + 11])
		if pose.origin.distance_to(expected) > 0.05:
			print("FAIL _test_instance_data_gives_the_same_pose: cruiser %d at %s, expected %s" % [i, pose.origin, expected])
			return 1
	# An hour later, the same place (TIME starts again every 3600 s).
	for i in range(AirTraffic.cruiser_count(lanes)):
		if AirTraffic.pose_from_data(data, i, 12.0).origin.distance_to(AirTraffic.pose_from_data(data, i, 3612.0).origin) > 0.05:
			print("FAIL _test_instance_data_gives_the_same_pose: cruiser %d moved after an hour" % i)
			return 1
	return 0

func _test_short_wings() -> int:
	# A compact sci-fi craft: about 9 m long, wings spanning at most
	# MAX_SPAN (stubs, not an airliner's).
	var box := AirTraffic.cruiser_mesh().get_aabb()
	if box.size.x > AirTraffic.MAX_SPAN or box.size.z < 8.0 or box.size.z > 10.5:
		print("FAIL _test_short_wings: %.1f m span, %.1f m long" % [box.size.x, box.size.z])
		return 1
	return 0

func _test_cruiser_counts_vary() -> int:
	var counts := {}
	for plan in _plans:
		counts[AirTraffic.cruiser_count(AirTraffic.lanes(plan))] = true
	if counts.size() < 2:
		print("FAIL _test_cruiser_counts_vary: every section has %s cruisers" % counts.keys())
		return 1
	return 0
