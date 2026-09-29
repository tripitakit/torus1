extends SceneTree

const InteriorLayout = preload("res://scripts/interior_layout.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

const SECTION_RADIUS := 2000.0
const SECTION_LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const SUN_RANGE := 2600.0

var _bridge_length: float = TorusGeometry.compute_bridge_length(1737400.0, 5212200.0, 2000, SECTION_LENGTH)

func _init():
	var failures := 0
	failures += _test_sections_sit_either_side_of_the_bridge()
	failures += _test_twenty_suns_one_per_kilometre()
	failures += _test_cylinder_point_on_the_wall()
	failures += _test_every_terrain_chunk_gets_one_to_seven_axis_lights()
	failures += _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights()
	failures += _test_chain_slot_positions()
	failures += _test_ring_indices_wrap()
	failures += _test_nearest_bridge_slot()
	failures += _test_nearest_section_slot()
	failures += _test_sections_within_reach()
	failures += _test_bridges_of_sections()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _all_axis_lights() -> PackedVector2Array:
	var lights := PackedVector2Array()
	for side in [-1.0, 1.0]:
		var center: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, side)
		for sun in InteriorLayout.sun_positions(center, SECTION_LENGTH, 1000.0):
			lights.append(Vector2(sun.z, SUN_RANGE))
	# Bridges have no lights of their own: the sections' suns light them.
	return lights

func _test_sections_sit_either_side_of_the_bridge() -> int:
	var ahead: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, -1.0)
	var behind: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, 1.0)
	var result := 0
	# Each section's near end touches the bridge's end.
	if not is_equal_approx(ahead + SECTION_LENGTH * 0.5, -_bridge_length * 0.5) or not is_equal_approx(behind - SECTION_LENGTH * 0.5, _bridge_length * 0.5):
		print("FAIL _test_sections_sit_either_side_of_the_bridge: centres %f / %f with bridge length %f" % [ahead, behind, _bridge_length])
		result = 1
	return result

func _test_twenty_suns_one_per_kilometre() -> int:
	var center: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, -1.0)
	var suns: PackedVector3Array = InteriorLayout.sun_positions(center, SECTION_LENGTH, 1000.0)
	var result := 0
	var start: float = center - SECTION_LENGTH * 0.5
	if suns.size() != 20:
		print("FAIL _test_twenty_suns_one_per_kilometre: %d suns expected 20" % suns.size())
		return 1
	for k in range(20):
		var expected := Vector3(0.0, 0.0, start + 500.0 + 1000.0 * k)
		if not suns[k].is_equal_approx(expected):
			print("FAIL _test_twenty_suns_one_per_kilometre: sun %d at %s expected %s" % [k, suns[k], expected])
			result = 1
	return result

func _test_cylinder_point_on_the_wall() -> int:
	var point: Vector3 = InteriorLayout.cylinder_point(SECTION_RADIUS, 1.0, -300.0)
	if not is_equal_approx(Vector2(point.x, point.y).length(), SECTION_RADIUS) or not is_equal_approx(point.z, -300.0) or not is_equal_approx(atan2(point.y, point.x), 1.0):
		print("FAIL _test_cylinder_point_on_the_wall: %s" % point)
		return 1
	return 0

func _test_every_terrain_chunk_gets_one_to_seven_axis_lights() -> int:
	# 8 lights per object at most; the 8th slot is left for the dock light.
	var lights := _all_axis_lights()
	var result := 0
	for side in [-1.0, 1.0]:
		var center: float = InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, side)
		var start: float = center - SECTION_LENGTH * 0.5
		for along in range(20):
			var z0: float = start + along * 1000.0
			var count: int = InteriorLayout.count_lights_reaching_band(SECTION_RADIUS, z0, z0 + 1000.0, lights)
			if count < 1 or count > 7:
				print("FAIL _test_every_terrain_chunk_gets_one_to_seven_axis_lights: side %s chunk %d reached by %d lights" % [side, along, count])
				result = 1
	return result

func _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights() -> int:
	var lights := _all_axis_lights()
	var result := 0
	var segment_length: float = _bridge_length / 4.0
	for k in range(4):
		var z0: float = -_bridge_length * 0.5 + k * segment_length
		var count: int = InteriorLayout.count_lights_reaching_band(BRIDGE_RADIUS, z0, z0 + segment_length, lights)
		if count < 1 or count > 7:
			print("FAIL _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights: segment %d reached by %d lights" % [k, count])
			result = 1
	return result

func _period() -> float:
	return InteriorLayout.chain_period(SECTION_LENGTH, _bridge_length)

func _test_chain_slot_positions() -> int:
	var p := _period()
	var result := 0
	if not is_equal_approx(p, SECTION_LENGTH + _bridge_length):
		print("FAIL _test_chain_slot_positions: period %f" % p)
		result = 1
	if not is_equal_approx(InteriorLayout.bridge_slot_z(0, p), 0.0) or not is_equal_approx(InteriorLayout.bridge_slot_z(2, p), -2.0 * p) or not is_equal_approx(InteriorLayout.bridge_slot_z(-1, p), p):
		print("FAIL _test_chain_slot_positions: bridge slots not at -slot * period")
		result = 1
	# Slot 0 is piece A's section "ahead", slot -1 the one "behind".
	if not is_equal_approx(InteriorLayout.section_slot_z(0, p), InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, -1.0)) or not is_equal_approx(InteriorLayout.section_slot_z(-1, p), InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, 1.0)):
		print("FAIL _test_chain_slot_positions: sections 0 and -1 are not the old ahead and behind")
		result = 1
	# Section s ends exactly where bridges s and s + 1 end.
	var section_high_end: float = InteriorLayout.section_slot_z(3, p) + SECTION_LENGTH * 0.5
	var section_low_end: float = InteriorLayout.section_slot_z(3, p) - SECTION_LENGTH * 0.5
	if not is_equal_approx(section_high_end, InteriorLayout.bridge_slot_z(3, p) - _bridge_length * 0.5) or not is_equal_approx(section_low_end, InteriorLayout.bridge_slot_z(4, p) + _bridge_length * 0.5):
		print("FAIL _test_chain_slot_positions: section 3 does not meet bridges 3 and 4")
		result = 1
	return result

func _test_ring_indices_wrap() -> int:
	var result := 0
	var cases := [
		# [docked, slot, bridge ring index, section ring index]
		[0, 0, 0, 1],
		[0, -1, 1999, 0],
		[1999, 0, 1999, 0],
		[1999, 1, 0, 1],
		[5, -7, 1998, 1999],
	]
	for c in cases:
		var bridge: int = InteriorLayout.bridge_ring_index(c[0], c[1], 2000)
		var section: int = InteriorLayout.section_ring_index(c[0], c[1], 2000)
		if bridge != c[2] or section != c[3]:
			print("FAIL _test_ring_indices_wrap: docked %d slot %d gave bridge %d section %d, expected %d and %d" % [c[0], c[1], bridge, section, c[2], c[3]])
			result = 1
	return result

func _test_nearest_bridge_slot() -> int:
	var p := _period()
	var result := 0
	for c in [[0.0, 0], [-0.4 * p, 0], [-0.6 * p, 1], [0.7 * p, -1], [-3.2 * p, 3]]:
		var slot: int = InteriorLayout.nearest_bridge_slot(c[0], p)
		if slot != c[1]:
			print("FAIL _test_nearest_bridge_slot: z %f gave slot %d, expected %d" % [c[0], slot, c[1]])
			result = 1
	return result

func _test_nearest_section_slot() -> int:
	# Section slot s is centred at -(s + 0.5) * period (see section_slot_z):
	# exactly there it must give back s, and a point anywhere inside that
	# section (up to half the period either way) must still give s.
	var p := _period()
	var result := 0
	for c in [[0.0, -1], [-0.5 * p, 0], [-1.5 * p, 1], [0.5 * p, -1], [2.5 * p, -3], [-0.9 * p, 0], [-0.1 * p, 0]]:
		var slot: int = InteriorLayout.nearest_section_slot(c[0], p)
		if slot != c[1]:
			print("FAIL _test_nearest_section_slot: z %f gave slot %d, expected %d" % [c[0], slot, c[1]])
			result = 1
	# Round-trip through section_slot_z for a spread of slots and periods.
	for period in [1.0, 21834.0, 500.0]:
		for slot in range(-5, 6):
			var z: float = InteriorLayout.section_slot_z(slot, period)
			var got: int = InteriorLayout.nearest_section_slot(z, period)
			if got != slot:
				print("FAIL _test_nearest_section_slot: round-trip slot %d (period %f) gave %d" % [slot, period, got])
				result = 1
	return result

func _test_sections_within_reach() -> int:
	var p := _period()
	var result := 0
	var cases := [
		# [z, reach in periods, expected slots]
		[0.0, 1.25, [-1, 0]],
		[-0.5 * p, 1.25, [-1, 0, 1]],
		[-2.2 * p, 1.25, [1, 2]],
		[-2.2 * p, 1.5, [1, 2, 3]],
		[3.0 * p, 1.25, [-4, -3]],
	]
	for c in cases:
		var slots: Array = InteriorLayout.sections_within(c[0], p, c[1] * p)
		if slots != c[2]:
			print("FAIL _test_sections_within_reach: z %f reach %f gave %s, expected %s" % [c[0], c[1], slots, c[2]])
			result = 1
	return result

func _test_bridges_of_sections() -> int:
	var result := 0
	for c in [[[-1, 0], [-1, 0, 1]], [[2, 1], [1, 2, 3]], [[], []]]:
		var bridges: Array = InteriorLayout.bridges_of_sections(c[0])
		if bridges != c[1]:
			print("FAIL _test_bridges_of_sections: sections %s gave bridges %s, expected %s" % [c[0], bridges, c[1]])
			result = 1
	return result
