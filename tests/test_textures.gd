extends SceneTree

# The baked textures (tools/blender/): sizes, and seamless edges where a set
# repeats.

func _init():
	var failures := 0
	failures += _test_panel_sets_exist_at_2048()
	failures += _test_repeating_panel_sets_have_no_seams()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _image(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null and image.is_compressed():
		image.decompress()
	return image

func _test_panel_sets_exist_at_2048() -> int:
	var result := 0
	for folder in ["bridge", "interior_tube", "interior_cap"]:
		for channel in ["color", "roughness", "normal", "emission"]:
			var path := "res://assets/textures/%s/%s.png" % [folder, channel]
			var image := _image(path)
			if image == null or image.get_size() != Vector2i(2048, 2048):
				print("FAIL _test_panel_sets_exist_at_2048: %s missing or not 2048x2048" % path)
				result = 1
	return result

# Mean colour difference between two pixel columns (or rows).
func _line_difference(image: Image, a: int, b: int, columns: bool) -> float:
	var total := 0.0
	var n := image.get_height() if columns else image.get_width()
	for i in range(0, n, 4):
		var p := image.get_pixel(a, i) if columns else image.get_pixel(i, a)
		var q := image.get_pixel(b, i) if columns else image.get_pixel(i, b)
		total += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
	return total / (n / 4.0)

func _test_repeating_panel_sets_have_no_seams() -> int:
	# Opposite edges should differ no more than two neighbouring lines do
	# anywhere inside (with some slack).
	var result := 0
	for folder in ["bridge", "interior_tube"]:
		var image := _image("res://assets/textures/%s/color.png" % folder)
		if image == null:
			print("FAIL _test_repeating_panel_sets_have_no_seams: no %s colour" % folder)
			result = 1
			continue
		var w := image.get_width()
		var h := image.get_height()
		var across := _line_difference(image, 0, w - 1, true)
		var inside := _line_difference(image, w / 2, w / 2 + 1, true)
		var down := _line_difference(image, 0, h - 1, false)
		var inside_rows := _line_difference(image, h / 2, h / 2 + 1, false)
		if across > inside * 3.0 + 0.05 or down > inside_rows * 3.0 + 0.05:
			print("FAIL _test_repeating_panel_sets_have_no_seams: %s edges differ %.3f / %.3f, inside %.3f / %.3f" % [folder, across, down, inside, inside_rows])
			result = 1
	return result
