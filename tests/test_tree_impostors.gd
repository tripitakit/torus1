extends SceneTree

# The trees' impostors: the baked atlases (a picture in every cell), the
# cards, the material sized per variant, and the hand-over between the
# detailed tree and its impostor.

const TreeModels = preload("res://scripts/tree_models.gd")

func _init():
	var failures := 0
	failures += _test_atlases()
	failures += _test_cards()
	failures += _test_material()
	failures += _test_hand_over()
	failures += _test_far_colours()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_atlases() -> int:
	for path in [TreeModels.IMPOSTOR_SIDE_PATH, TreeModels.IMPOSTOR_TOP_PATH]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		var side := TreeModels.IMPOSTOR_CELL * TreeModels.IMPOSTOR_GRID
		if image == null or image.get_width() != side or image.get_height() != side or not image.detect_alpha():
			print("FAIL _test_atlases: %s" % path)
			return 1
		for k in range(25):
			var corner := Vector2i(k % 5, k / 5) * TreeModels.IMPOSTOR_CELL
			var opaque := 0
			for y in range(0, TreeModels.IMPOSTOR_CELL, 4):
				for x in range(0, TreeModels.IMPOSTOR_CELL, 4):
					if image.get_pixelv(corner + Vector2i(x, y)).a > 0.5:
						opaque += 1
			if opaque < 40:
				print("FAIL _test_atlases: %s cell %d nearly empty (%d)" % [path, k, opaque])
				return 1
	return 0

# Two upright crossed cards and a level one: six triangles.
func _test_cards() -> int:
	var mesh := TreeModels.impostor_mesh()
	var box := mesh.get_aabb()
	if mesh.get_faces().size() != 6 * 3 or absf(box.size.y - 1.0) > 0.001 or absf(box.position.y) > 0.001:
		print("FAIL _test_cards: %d faces, box %s" % [mesh.get_faces().size() / 3, box])
		return 1
	return 0

func _test_material() -> int:
	var m := TreeModels.impostor_material()
	var sizes: PackedFloat32Array = m.get_shader_parameter("side_sizes")
	var tops: PackedFloat32Array = m.get_shader_parameter("top_sizes")
	if m.get_shader_parameter("side_atlas") == null or m.get_shader_parameter("top_atlas") == null or sizes.size() != 25 or tops.size() != 25 or not is_equal_approx(m.get_shader_parameter("detail_from"), TreeModels.DETAIL):
		print("FAIL _test_material")
		return 1
	for k in range(25):
		if sizes[k] < 1.0 or tops[k] <= 0.0:
			print("FAIL _test_material: variant %d sizes %.2f, %.2f" % [k, sizes[k], tops[k]])
			return 1
	return 0

# The detailed tree's share falls from 1 to 0 over the last FADE metres
# before DETAIL; the impostor has the rest of the pixels.
func _test_hand_over() -> int:
	var cases := [[TreeModels.DETAIL - TreeModels.FADE - 1.0, 0.0], [TreeModels.DETAIL - TreeModels.FADE * 0.5, 0.5], [TreeModels.DETAIL + 1.0, 1.0]]
	for c in cases:
		if absf(TreeModels.fade_share(c[0]) - c[1]) > 0.001:
			print("FAIL _test_hand_over: %.1f m gave %.2f" % [c[0], TreeModels.fade_share(c[0])])
			return 1
	var near: ShaderMaterial = TreeModels.variants()[0].mesh.surface_get_material(0)
	if not is_equal_approx(near.get_shader_parameter("fade"), TreeModels.FADE) or not is_equal_approx(TreeModels.impostor_material().get_shader_parameter("fade"), TreeModels.FADE):
		print("FAIL _test_hand_over: the two fades differ")
		return 1
	return 0

# Each variant's average leaf colour from the bake, for the far shapes.
func _test_far_colours() -> int:
	var colours: PackedVector3Array = TreeModels.far_material().get_shader_parameter("colours")
	if colours.size() != 25:
		print("FAIL _test_far_colours: %d" % colours.size())
		return 1
	for k in range(25):
		var c := colours[k]
		if c.length() < 0.05 or (k < 20 and c.y < 0.05):
			print("FAIL _test_far_colours: variant %d %s" % [k, c])
			return 1
	return 0
