extends SceneTree

# Quaternius' trees (CC0): five kinds of five variants, each one unit tall
# with its trunk's foot on the origin, leaves cut out by their texture; which
# variant a tree is, from where it stands.

const TreeModels = preload("res://scripts/tree_models.gd")

func _init():
	var failures := 0
	failures += _test_twenty_five_variants()
	failures += _test_unit_tall_on_the_trunk()
	failures += _test_leaves_cut_out()
	failures += _test_variant_fixed_by_place()
	failures += _test_kinds_by_tree()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_twenty_five_variants() -> int:
	var variants := TreeModels.variants()
	var kinds := {}
	for v in variants:
		kinds[v.kind] = kinds.get(v.kind, 0) + 1
	if variants.size() != 25 or kinds != {"pine": 5, "birch": 5, "maple": 5, "normal": 5, "dead": 5}:
		print("FAIL _test_twenty_five_variants: %d, %s" % [variants.size(), kinds])
		return 1
	return 0

func _test_unit_tall_on_the_trunk() -> int:
	for v in TreeModels.variants():
		var mesh: ArrayMesh = v.mesh
		var box := mesh.get_aabb()
		var foot := Vector2.ZERO
		var n := 0
		var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for p in points:
			if p.y < 0.02:
				foot += Vector2(p.x, p.z)
				n += 1
		foot /= maxf(n, 1)
		if absf(box.size.y - 1.0) > 0.01 or absf(box.position.y) > 0.01 or foot.length() > 0.03:
			print("FAIL _test_unit_tall_on_the_trunk: %s %d box %s, foot %s" % [v.kind, v.index, box, foot])
			return 1
	return 0

func _test_leaves_cut_out() -> int:
	for v in TreeModels.variants():
		var mesh: ArrayMesh = v.mesh
		var leafy := 0
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s) as ShaderMaterial
			if m == null or m.get_shader_parameter("albedo_tex") == null:
				print("FAIL _test_leaves_cut_out: %s %d surface %d material %s" % [v.kind, v.index, s, m])
				return 1
			if m.get_shader_parameter("leaves"):
				leafy += 1
		if (v.kind == "dead") != (leafy == 0):
			print("FAIL _test_leaves_cut_out: %s %d with %d leafy surfaces" % [v.kind, v.index, leafy])
			return 1
	return 0

func _test_variant_fixed_by_place() -> int:
	var at := Vector3(123.4, -1980.2, 567.8)
	var a := TreeModels.variant_for(at, false, 200.0)
	var b := TreeModels.variant_for(at, false, 200.0)
	var spread := {}
	for k in range(200):
		spread[TreeModels.variant_for(Vector3(k * 17.0, -1990.0, k * 9.0), false, 100.0)] = true
	if a != b or spread.size() < 12:
		print("FAIL _test_variant_fixed_by_place: %d vs %d, %d variants in 200 trees" % [a, b, spread.size()])
		return 1
	return 0

# Conifers are pines; broadleaves maples, normals and birches, a few dead
# ones up near the treeline only.
func _test_kinds_by_tree() -> int:
	var variants := TreeModels.variants()
	var dead_high := 0
	for k in range(1000):
		var at := Vector3(k * 13.0, -1985.0, k * 7.0)
		var pine: String = variants[TreeModels.variant_for(at, true, 500.0)].kind
		var low: String = variants[TreeModels.variant_for(at, false, 100.0)].kind
		var high: String = variants[TreeModels.variant_for(at, false, 520.0)].kind
		if pine != "pine" or not (low in ["birch", "maple", "normal"]) or high == "pine":
			print("FAIL _test_kinds_by_tree: %s, %s, %s" % [pine, low, high])
			return 1
		if high == "dead":
			dead_high += 1
	if dead_high < 20 or dead_high > 100:
		print("FAIL _test_kinds_by_tree: %d dead of 1000 near the treeline" % dead_high)
		return 1
	return 0
