extends SceneTree

const InteriorLayout = preload("res://scripts/interior_layout.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

const SECTION_RADIUS := 2000.0
const SECTION_LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const SUN_RANGE := 2600.0
const BRIDGE_LIGHT_RANGE := 900.0

var _bridge_length: float = TorusGeometry.compute_bridge_length(1737400.0, 5212200.0, 2000, SECTION_LENGTH)

func _init():
	var failures := 0
	failures += _test_sections_sit_either_side_of_the_bridge()
	failures += _test_twenty_suns_one_per_kilometre()
	failures += _test_cylinder_point_on_the_wall()
	failures += _test_every_terrain_chunk_gets_one_to_seven_axis_lights()
	failures += _test_every_bridge_tube_segment_gets_one_to_seven_axis_lights()

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
	for k in range(3):
		lights.append(Vector2(_bridge_length * (k - 1) / 3.0, BRIDGE_LIGHT_RANGE))
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
