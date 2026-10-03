extends SceneTree

# The train on the axis spine: stations chosen from the plan (city first),
# a timetable the same length in every period, one train each way per
# period, handed on with no jump at the bridges.

const SpineTrain = preload("res://scripts/spine_train.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

const LENGTH := 20000.0
const BRIDGE := 1834.0
const PERIOD := LENGTH + BRIDGE

var _failures := 0

func _initialize():
	_failures += _test_city_first_then_thirds()
	_failures += _test_station_z_at_lot_centres()
	_failures += _test_period_time()
	_failures += _test_progress_cruise_stops_and_end()
	_failures += _test_stops_where_the_stations_are()
	_failures += _test_train_handed_on_at_the_bridge()
	_failures += _test_opposite_way_half_a_period_apart()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _plan(special: Dictionary):
	var plan = SectionPlan.new()
	plan.radius = 2000.0
	plan.length = LENGTH
	plan.lot_width = TAU * 2000.0 / SectionPlan.LOTS_AROUND
	plan.lot_length = LENGTH / SectionPlan.LOTS_ALONG
	var zones := PackedByteArray()
	zones.resize(SectionPlan.LOTS_AROUND * SectionPlan.LOTS_ALONG)
	zones.fill(SectionPlan.Zone.FIELD)
	for along: int in special:
		zones[along * SectionPlan.LOTS_AROUND + SpineTrain.STATION_COLUMN] = special[along]
	plan.zones = zones
	return plan

func _test_city_first_then_thirds() -> int:
	# First half: a town at 12, the city at 30: the city. Second half
	# nothing: two thirds of the way (lot 53).
	var lots := SpineTrain.station_lots(_plan({12: SectionPlan.Zone.TOWN, 30: SectionPlan.Zone.CITY}))
	if lots != PackedInt32Array([30, 53]):
		print("FAIL _test_city_first_then_thirds: %s" % lots)
		return 1
	# Two towns in the second half: the one nearer two thirds; a city past
	# the first half's lots does not count.
	lots = SpineTrain.station_lots(_plan({40: SectionPlan.Zone.CITY, 46: SectionPlan.Zone.TOWN, 58: SectionPlan.Zone.TOWN}))
	if lots != PackedInt32Array([26, 58]):
		print("FAIL _test_city_first_then_thirds: %s" % lots)
		return 1
	return 0

func _test_station_z_at_lot_centres() -> int:
	var plan = _plan({})
	var zs := SpineTrain.station_z(plan)
	if not is_equal_approx(zs[0], 26.5 * 250.0) or not is_equal_approx(zs[1], 53.5 * 250.0):
		print("FAIL _test_station_z_at_lot_centres: %s" % zs)
		return 1
	return 0

func _test_period_time() -> int:
	var expected := PERIOD / SpineTrain.SPEED + 2.0 * SpineTrain.SPEED / SpineTrain.ACCEL + 2.0 * SpineTrain.DWELL
	if not is_equal_approx(SpineTrain.period_time(PERIOD), expected):
		print("FAIL _test_period_time: %.2f, expected %.2f" % [SpineTrain.period_time(PERIOD), expected])
		return 1
	return 0

func _test_progress_cruise_stops_and_end() -> int:
	var stops := [5000.0, 15000.0]
	var total := SpineTrain.period_time(PERIOD)
	var start_speed := SpineTrain.progress(0.1, stops, PERIOD) / 0.1
	var end_speed := (PERIOD - SpineTrain.progress(total - 0.1, stops, PERIOD)) / 0.1
	if absf(SpineTrain.progress(0.0, stops, PERIOD)) > 0.001 or absf(start_speed - SpineTrain.SPEED) > 0.01 or absf(end_speed - SpineTrain.SPEED) > 0.01:
		print("FAIL _test_progress_cruise_stops_and_end: start at %.3f, speeds %.2f / %.2f" % [SpineTrain.progress(0.0, stops, PERIOD), start_speed, end_speed])
		return 1
	# Never backwards; still for DWELL seconds at each stop.
	var last := -1.0
	var still := [0.0, 0.0]
	var step := 0.05
	var t := 0.0
	while t < total:
		var u := SpineTrain.progress(t, stops, PERIOD)
		if u < last - 0.0001:
			print("FAIL _test_progress_cruise_stops_and_end: backwards at %.2f s" % t)
			return 1
		for k in range(2):
			if absf(u - stops[k]) < 0.0001:
				still[k] += step
		last = u
		t += step
	if absf(still[0] - SpineTrain.DWELL) > 0.2 or absf(still[1] - SpineTrain.DWELL) > 0.2:
		print("FAIL _test_progress_cruise_stops_and_end: still %.2f s and %.2f s at the stops" % still)
		return 1
	return 0

func _test_stops_where_the_stations_are() -> int:
	# While stopped, each way's train is at a station's z in the section's
	# frame (plan z - length / 2).
	var station_zs := [6000.0, 14500.0]
	for way in [SpineTrain.AHEAD, SpineTrain.BACK]:
		var stops := SpineTrain.stops(way, station_zs, LENGTH, BRIDGE)
		for u in stops:
			var z := SpineTrain.train_node_z(way, u, LENGTH, BRIDGE)
			if absf(z - (6000.0 - LENGTH * 0.5)) > 0.001 and absf(z - (14500.0 - LENGTH * 0.5)) > 0.001:
				print("FAIL _test_stops_where_the_stations_are: way %d stops at node z %.1f" % [way, z])
				return 1
	return 0

# The chain z of the train going `way` in section slot `slot` at time t.
func _chain_z(way: int, slot: int, t: float, station_zs: Array) -> float:
	var total := SpineTrain.period_time(PERIOD)
	var u := SpineTrain.progress(SpineTrain.train_tau(t, way, total), SpineTrain.stops(way, station_zs, LENGTH, BRIDGE), PERIOD)
	return -(slot + 0.5) * PERIOD + SpineTrain.train_node_z(way, u, LENGTH, BRIDGE)

func _test_train_handed_on_at_the_bridge() -> int:
	# Ahead (toward -z): leaving section 3 for section 4 at the end of its
	# period; back (toward +z): leaving section 4 for section 3.
	var total := SpineTrain.period_time(PERIOD)
	var a := [3000.0, 9000.0]
	var b := [11000.0, 17500.0]
	for way in [SpineTrain.AHEAD, SpineTrain.BACK]:
		var offset := 0.0 if way == SpineTrain.AHEAD else total * 0.5
		var t_end := total * 7.0 - offset
		var from_slot := 3 if way == SpineTrain.AHEAD else 4
		var to_slot := 4 if way == SpineTrain.AHEAD else 3
		var leaving := _chain_z(way, from_slot, t_end - 0.001, a if from_slot == 3 else b)
		var arriving := _chain_z(way, to_slot, t_end + 0.001, a if to_slot == 3 else b)
		var bridge_z := -4.0 * PERIOD
		if absf(leaving - bridge_z) > 0.2 or absf(arriving - bridge_z) > 0.2:
			print("FAIL _test_train_handed_on_at_the_bridge: way %d leaves at %.2f, next arrives at %.2f, bridge at %.2f" % [way, leaving, arriving, bridge_z])
			return 1
	return 0

func _test_opposite_way_half_a_period_apart() -> int:
	var total := SpineTrain.period_time(PERIOD)
	if not is_equal_approx(fposmod(SpineTrain.train_tau(100.0, SpineTrain.BACK, total) - SpineTrain.train_tau(100.0, SpineTrain.AHEAD, total), total), total * 0.5):
		print("FAIL _test_opposite_way_half_a_period_apart")
		return 1
	return 0
