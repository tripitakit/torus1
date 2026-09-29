extends SceneTree

const SectionLabel = preload("res://scripts/section_label.gd")

func _init():
	var failures := 0
	failures += _test_format_id_pads_to_four_digits()
	failures += _test_glyph_uv_finds_each_cell()
	failures += _test_label_instances_read_left_to_right_from_outside()
	failures += _test_glyph_mesh_follows_the_cylinder_radius()

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

func _test_label_instances_read_left_to_right_from_outside() -> int:
	# Angle 0: an observer outside +Z looks toward -Z with character "up"
	# along tangent +X. Screen-right is therefore local -Y: the first
	# character must start at +Y and each glyph's own X axis must point -Y.
	var instances: Array = SectionLabel.label_instances("01", 0.0, 1000.0, 100.0, 50.0, 10.0)
	var result := 0
	if instances.size() != 2:
		print("FAIL _test_label_instances_read_left_to_right_from_outside: %d instances, expected 2" % instances.size())
		return 1
	var expected_origins := [Vector3(0.0, 55.0, 1000.0), Vector3(0.0, -55.0, 1000.0)]
	var expected_uvs := [SectionLabel.glyph_uv("0"), SectionLabel.glyph_uv("1")]
	for i in range(2):
		var t: Transform3D = instances[i].transform
		if not t.origin.is_equal_approx(expected_origins[i]):
			print("FAIL _test_label_instances_read_left_to_right_from_outside: char %d at %s, expected %s" % [i, t.origin, expected_origins[i]])
			result = 1
		if not t.basis.x.is_equal_approx(Vector3(0.0, -100.0, 0.0)) or not t.basis.y.is_equal_approx(Vector3(50.0, 0.0, 0.0)) or not t.basis.z.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
			print("FAIL _test_label_instances_read_left_to_right_from_outside: char %d basis %s" % [i, t.basis])
			result = 1
		var uv: Rect2 = instances[i].uv
		if not uv.position.is_equal_approx(expected_uvs[i].position):
			print("FAIL _test_label_instances_read_left_to_right_from_outside: char %d uv %s, expected %s" % [i, uv, expected_uvs[i]])
			result = 1
	return result

func _test_glyph_mesh_follows_the_cylinder_radius() -> int:
	# A 400 m-tall glyph on a 1 km-radius hull spans 0.4 radians. Its shared
	# mesh needs intermediate rows on that arc; a single tangent quad leaves
	# both edges visibly floating away from the cylinder.
	var mesh := SectionLabel.build_curved_glyph_mesh(1000.0, 400.0, 4)
	if mesh == null or mesh.get_surface_count() != 1:
		print("FAIL _test_glyph_mesh_follows_the_cylinder_radius: expected one ArrayMesh surface")
		return 1
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var result := 0
	if vertices.size() != 10 or indices.size() != 24:
		print("FAIL _test_glyph_mesh_follows_the_cylinder_radius: got %d vertices/%d indices, expected 10/24" % [vertices.size(), indices.size()])
		result = 1
	var found_recessed_edge := false
	for vertex in vertices:
		var tangent_distance := vertex.y * 400.0
		var radius := Vector2(tangent_distance, 1000.0 + vertex.z).length()
		if not is_equal_approx(radius, 1000.0):
			print("FAIL _test_glyph_mesh_follows_the_cylinder_radius: vertex %s lies at radius %f, expected 1000" % [vertex, radius])
			result = 1
		if vertex.z < -1.0:
			found_recessed_edge = true
	if not found_recessed_edge:
		print("FAIL _test_glyph_mesh_follows_the_cylinder_radius: mesh is still flat")
		result = 1
	return result
