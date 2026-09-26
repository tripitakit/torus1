extends SceneTree

const BuildingShapes = preload("res://scripts/building_shapes.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

func _init():
	var failures := 0
	failures += _test_one_named_shape_per_style()
	failures += _test_every_shape_fits_the_unit_box_on_its_base()
	failures += _test_faces_wind_the_way_their_normals_point()
	failures += _test_at_most_256_triangles()
	failures += _test_every_shape_has_roof_and_walls()
	failures += _test_every_hull_holds_its_shape()
	failures += _test_spire_ends_in_a_thin_antenna()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _arrays(style: int) -> Array:
	return BuildingShapes.mesh(style).surface_get_arrays(0)

func _test_one_named_shape_per_style() -> int:
	if BuildingShapes.NAMES.size() != SectionPlan.Style.size():
		print("FAIL _test_one_named_shape_per_style: %d names for %d styles" % [BuildingShapes.NAMES.size(), SectionPlan.Style.size()])
		return 1
	if BuildingShapes.mesh(SectionPlan.Style.DOME) != BuildingShapes.mesh(SectionPlan.Style.DOME):
		print("FAIL _test_one_named_shape_per_style: meshes are rebuilt instead of shared")
		return 1
	return 0

func _test_every_shape_fits_the_unit_box_on_its_base() -> int:
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var vertices: PackedVector3Array = _arrays(style)[Mesh.ARRAY_VERTEX]
		var box := AABB(vertices[0], Vector3.ZERO)
		var base := AABB(Vector3.ZERO, Vector3.ZERO)
		var base_started := false
		for v in vertices:
			box = box.expand(v)
			if is_equal_approx(v.y, -0.5):
				if not base_started:
					base = AABB(v, Vector3.ZERO)
					base_started = true
				base = base.expand(v)
		var inside := box.position.x >= -0.5001 and box.end.x <= 0.5001 and box.position.z >= -0.5001 and box.end.z <= 0.5001
		var spans := is_equal_approx(box.position.y, -0.5) and is_equal_approx(box.end.y, 0.5)
		var footprint := base_started and base.size.x >= 0.9 and base.size.z >= 0.9
		if not inside or not spans or not footprint:
			print("FAIL _test_every_shape_fits_the_unit_box_on_its_base: %s box %s base %s" % [BuildingShapes.NAMES[style], box, base])
			result = 1
	return result

func _test_faces_wind_the_way_their_normals_point() -> int:
	# Godot's front face normal is opposite to (b - a) x (c - a).
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var arrays := _arrays(style)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for t in range(0, vertices.size(), 3):
			var cross := (vertices[t + 1] - vertices[t]).cross(vertices[t + 2] - vertices[t])
			if cross.dot(normals[t]) >= 0.0 or not is_equal_approx(normals[t].length(), 1.0):
				print("FAIL _test_faces_wind_the_way_their_normals_point: %s triangle at vertex %d winds against its normal %s" % [BuildingShapes.NAMES[style], t, normals[t]])
				result = 1
				break
	return result

func _test_at_most_256_triangles() -> int:
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var vertices: PackedVector3Array = _arrays(style)[Mesh.ARRAY_VERTEX]
		if vertices.size() > BuildingShapes.MAX_TRIANGLES * 3 or vertices.size() % 3 != 0:
			print("FAIL _test_at_most_256_triangles: %s has %d vertices" % [BuildingShapes.NAMES[style], vertices.size()])
			result = 1
	return result

func _test_every_shape_has_roof_and_walls() -> int:
	# The shader paints facades only where |n.y| < 0.5: every shape needs both.
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var normals: PackedVector3Array = _arrays(style)[Mesh.ARRAY_NORMAL]
		var roof := false
		var wall := false
		for n in normals:
			roof = roof or n.y > 0.9
			wall = wall or absf(n.y) < 0.5
		if not roof or not wall:
			print("FAIL _test_every_shape_has_roof_and_walls: %s roof %s walls %s" % [BuildingShapes.NAMES[style], roof, wall])
			result = 1
	return result

func _directions() -> Array:
	var dirs := []
	for x in [-1.0, 0.0, 1.0]:
		for y in [-1.0, 0.0, 1.0]:
			for z in [-1.0, 0.0, 1.0]:
				if x != 0.0 or y != 0.0 or z != 0.0:
					dirs.append(Vector3(x, y, z).normalized())
	return dirs

func _test_every_hull_holds_its_shape() -> int:
	# In every direction the hull reaches at least as far as the mesh.
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var hull: PackedVector3Array = BuildingShapes.hull_points(style)
		var vertices: PackedVector3Array = _arrays(style)[Mesh.ARRAY_VERTEX]
		if hull.size() < 4:
			print("FAIL _test_every_hull_holds_its_shape: %s hull has %d points" % [BuildingShapes.NAMES[style], hull.size()])
			result = 1
			continue
		for d: Vector3 in _directions():
			var hull_reach := -INF
			for p in hull:
				hull_reach = maxf(hull_reach, p.dot(d))
			var mesh_reach := -INF
			for v in vertices:
				mesh_reach = maxf(mesh_reach, v.dot(d))
			if hull_reach < mesh_reach - 1e-4:
				print("FAIL _test_every_hull_holds_its_shape: %s hull short by %f toward %s" % [BuildingShapes.NAMES[style], mesh_reach - hull_reach, d])
				result = 1
				break
	return result

func _test_spire_ends_in_a_thin_antenna() -> int:
	var vertices: PackedVector3Array = _arrays(SectionPlan.Style.SPIRE)[Mesh.ARRAY_VERTEX]
	for v in vertices:
		if v.y > 0.45 and (absf(v.x) > 0.05 or absf(v.z) > 0.05):
			print("FAIL _test_spire_ends_in_a_thin_antenna: vertex %s near the top is too wide" % v)
			return 1
	return 0
