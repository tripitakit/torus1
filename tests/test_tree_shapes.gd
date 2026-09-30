extends SceneTree

# The two low-poly tree meshes: unit size, faces outward, trunk and crown
# told apart by the vertex colour's alpha.

const TreeShapes = preload("res://scripts/tree_shapes.gd")

func _init():
	var failures := 0
	for entry in [["conifer", TreeShapes.conifer(), TreeShapes.CONIFER_WIDTH], ["broadleaf", TreeShapes.broadleaf(), TreeShapes.BROADLEAF_WIDTH]]:
		failures += _test_unit_size(entry[0], entry[1])
		failures += _test_crown_width(entry[0], entry[1], entry[2])
		failures += _test_faces_point_outward(entry[0], entry[1])
		failures += _test_trunk_and_crown_colours(entry[0], entry[1])

	# The far versions: the same tree, a handful of triangles.
	for entry in [["far conifer", TreeShapes.far_conifer(), TreeShapes.CONIFER_WIDTH], ["far broadleaf", TreeShapes.far_broadleaf(), TreeShapes.BROADLEAF_WIDTH]]:
		failures += _test_far_shape(entry[0], entry[1])
		failures += _test_crown_width(entry[0], entry[1], entry[2])
		failures += _test_faces_point_outward(entry[0], entry[1])

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)

func _test_unit_size(tree_name: String, mesh: ArrayMesh) -> int:
	var vertices: PackedVector3Array = _arrays(mesh)[Mesh.ARRAY_VERTEX]
	var low := INF
	var high := -INF
	var widest := 0.0
	for v in vertices:
		low = minf(low, v.y)
		high = maxf(high, v.y)
		widest = maxf(widest, Vector2(v.x, v.z).length())
	@warning_ignore("integer_division")
	var triangles: int = vertices.size() / 3
	if not is_equal_approx(low, 0.0) or not is_equal_approx(high, 1.0) or widest > 0.4 or triangles < 20 or triangles > 80:
		print("FAIL _test_unit_size (%s): y %f..%f, radius %f, %d triangles" % [tree_name, low, high, widest, triangles])
		return 1
	return 0

func _test_far_shape(tree_name: String, mesh: ArrayMesh) -> int:
	var vertices: PackedVector3Array = _arrays(mesh)[Mesh.ARRAY_VERTEX]
	var low := INF
	var high := -INF
	for v in vertices:
		low = minf(low, v.y)
		high = maxf(high, v.y)
	@warning_ignore("integer_division")
	var triangles: int = vertices.size() / 3
	if triangles > 8 or not is_equal_approx(high, 1.0) or low > 0.35:
		print("FAIL _test_far_shape (%s): %d triangles, y %f..%f" % [tree_name, triangles, low, high])
		return 1
	return 0

func _test_crown_width(tree_name: String, mesh: ArrayMesh, width: float) -> int:
	# The widest the crown gets, across: the dressing divides by it so a
	# tree's crown is its planned share of the height.
	var widest := 0.0
	for v in (_arrays(mesh)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		widest = maxf(widest, 2.0 * Vector2(v.x, v.z).length())
	if absf(widest - width) > 0.001:
		print("FAIL _test_crown_width (%s): crown %f across, constant says %f" % [tree_name, widest, width])
		return 1
	return 0

func _test_faces_point_outward(tree_name: String, mesh: ArrayMesh) -> int:
	# Front faces (Godot's winding: normal (c - a) x (b - a)) look away from
	# the trunk's axis; the only horizontal faces are bottom discs, facing
	# down. The stored normals match the winding.
	var arrays := _arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for t in range(0, vertices.size(), 3):
		var a := vertices[t]
		var b := vertices[t + 1]
		var c := vertices[t + 2]
		var n: Vector3 = (c - a).cross(b - a).normalized()
		var centre: Vector3 = (a + b + c) / 3.0
		var outward: bool = n.y < 0.0 if absf(n.y) > 0.99 else n.dot(Vector3(centre.x, 0.0, centre.z)) > 0.0
		# Stored normals are compressed (about 1e-4): compare by direction.
		if not outward or normals[t].dot(n) < 0.999:
			print("FAIL _test_faces_point_outward (%s): triangle %d normal %s at %s" % [tree_name, t / 3, n, centre])
			return 1
	return 0

func _test_trunk_and_crown_colours(tree_name: String, mesh: ArrayMesh) -> int:
	# Alpha 0 on the trunk (the only part below 0.14), 1 on the crown.
	var arrays := _arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var crown := 0
	for i in range(vertices.size()):
		if vertices[i].y < 0.14 and colors[i].a != 0.0:
			print("FAIL _test_trunk_and_crown_colours (%s): vertex %s low but not trunk" % [tree_name, vertices[i]])
			return 1
		if colors[i].a == 1.0:
			crown += 1
	if crown == 0:
		print("FAIL _test_trunk_and_crown_colours (%s): no crown vertex" % tree_name)
		return 1
	return 0
