extends SceneTree

const SectionLabel = preload("res://scripts/section_label.gd")

func _init():
	var failures := 0
	failures += _test_format_id_pads_to_four_digits()
	failures += _test_glyph_uv_finds_each_cell()
	failures += _test_label_instances_places_and_sizes_characters()
	failures += _test_four_angles_ninety_degrees_apart()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_format_id_pads_to_four_digits() -> int:
	var result := 0
	for c in [[0, "T1-0001"], [41, "T1-0042"], [1999, "T1-2000"]]:
		if SectionLabel.format_id(c[0]) != c[1]:
			print("FAIL _test_format_id_pads_to_four_digits: index %d gave '%s', expected '%s'" % [c[0], SectionLabel.format_id(c[0]), c[1]])
			result = 1
	return result

func _test_glyph_uv_finds_each_cell() -> int:
	var result := 0
	# GLYPHS = "0123456789T-", 4 columns x 3 rows.
	for c in [["0", Rect2(0.0, 0.0, 0.25, 1.0 / 3.0)], ["3", Rect2(0.75, 0.0, 0.25, 1.0 / 3.0)], ["T", Rect2(0.5, 2.0 / 3.0, 0.25, 1.0 / 3.0)], ["-", Rect2(0.75, 2.0 / 3.0, 0.25, 1.0 / 3.0)]]:
		var uv: Rect2 = SectionLabel.glyph_uv(c[0])
		if not uv.position.is_equal_approx(c[1].position) or not uv.size.is_equal_approx(c[1].size):
			print("FAIL _test_glyph_uv_finds_each_cell: '%s' gave %s, expected %s" % [c[0], uv, c[1]])
			result = 1
	return result

func _test_label_instances_places_and_sizes_characters() -> int:
	# Angle 0: outward = +Z, tangent (character "up") = +X. Two characters,
	# centred along the axis (local Y) with a gap between them.
	var instances: Array = SectionLabel.label_instances("01", 0.0, 1000.0, 100.0, 50.0, 10.0)
	var result := 0
	if instances.size() != 2:
		print("FAIL _test_label_instances_places_and_sizes_characters: %d instances, expected 2" % instances.size())
		return 1
	var expected_origins := [Vector3(0.0, -55.0, 1000.0), Vector3(0.0, 55.0, 1000.0)]
	var expected_uvs := [SectionLabel.glyph_uv("0"), SectionLabel.glyph_uv("1")]
	for i in range(2):
		var t: Transform3D = instances[i].transform
		if not t.origin.is_equal_approx(expected_origins[i]):
			print("FAIL _test_label_instances_places_and_sizes_characters: char %d at %s, expected %s" % [i, t.origin, expected_origins[i]])
			result = 1
		if not t.basis.x.is_equal_approx(Vector3(0.0, 100.0, 0.0)) or not t.basis.y.is_equal_approx(Vector3(50.0, 0.0, 0.0)) or not t.basis.z.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
			print("FAIL _test_label_instances_places_and_sizes_characters: char %d basis %s" % [i, t.basis])
			result = 1
		var uv: Rect2 = instances[i].uv
		if not uv.position.is_equal_approx(expected_uvs[i].position):
			print("FAIL _test_label_instances_places_and_sizes_characters: char %d uv %s, expected %s" % [i, uv, expected_uvs[i]])
			result = 1
	return result

func _test_four_angles_ninety_degrees_apart() -> int:
	var result := 0
	if SectionLabel.ANGLES.size() != 4:
		print("FAIL _test_four_angles_ninety_degrees_apart: %d angles, expected 4" % SectionLabel.ANGLES.size())
		return 1
	for i in range(4):
		if not is_equal_approx(SectionLabel.ANGLES[i], i * PI * 0.5):
			print("FAIL _test_four_angles_ninety_degrees_apart: angle %d is %f" % [i, SectionLabel.ANGLES[i]])
			result = 1
	return result
