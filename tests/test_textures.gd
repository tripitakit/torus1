extends SceneTree

# The baked textures (tools/blender/): sizes, and seamless edges where a set
# repeats.

func _init():
	var failures := 0
	failures += _test_panel_sets_exist_at_2048()
	failures += _test_repeating_panel_sets_have_no_seams()
	failures += _test_planet_maps()
	failures += _test_imported_compressed_with_mipmaps()
	failures += _test_star_map()

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

# Pixel of (latitude, longitude) degrees on an equirectangular map with
# longitude -180 at its left edge.
func _at(image: Image, latitude: float, longitude: float) -> Color:
	var x := int((longitude + 180.0) / 360.0 * image.get_width()) % image.get_width()
	var y := clampi(int((90.0 - latitude) / 180.0 * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixelv(Vector2i(x, y))

func _test_planet_maps() -> int:
	# NASA's Earth (tools/earth_maps.py): colour, city lights and clouds at
	# 8192 x 4096, relief and roughness at 4096 x 2048. Oceans darker and
	# glossier than land, Paris lit at night and the open Pacific not, the
	# clouds a grey cover map with both clear and overcast skies.
	var result := 0
	var sizes := {
		"res://assets/textures/planet/color.jpg": Vector2i(8192, 4096),
		"res://assets/textures/planet/lights.jpg": Vector2i(8192, 4096),
		"res://assets/textures/clouds/clouds.jpg": Vector2i(8192, 4096),
		"res://assets/textures/planet/roughness.png": Vector2i(4096, 2048),
		"res://assets/textures/planet/normal.png": Vector2i(4096, 2048),
	}
	for path in sizes:
		var image := _image(path)
		if image == null or image.get_size() != sizes[path]:
			print("FAIL _test_planet_maps: %s missing or not %s" % [path, sizes[path]])
			return 1
	var colour := _image("res://assets/textures/planet/color.jpg")
	var rough := _image("res://assets/textures/planet/roughness.png")
	var lights := _image("res://assets/textures/planet/lights.jpg")
	var pacific := Vector2(0.0, -150.0)
	var sahara := Vector2(23.0, 13.0)
	var paris := Vector2(48.86, 2.35)
	if _at(colour, pacific.x, pacific.y).get_luminance() > _at(colour, sahara.x, sahara.y).get_luminance() - 0.2:
		print("FAIL _test_planet_maps: the Pacific not darker than the Sahara")
		result = 1
	if _at(rough, pacific.x, pacific.y).r > _at(rough, sahara.x, sahara.y).r - 0.3:
		print("FAIL _test_planet_maps: the Pacific not glossier than the Sahara")
		result = 1
	if _at(lights, paris.x, paris.y).get_luminance() < 0.3 or _at(lights, pacific.x, pacific.y).get_luminance() > 0.05:
		print("FAIL _test_planet_maps: Paris %.2f, Pacific %.2f at night" % [_at(lights, paris.x, paris.y).get_luminance(), _at(lights, pacific.x, pacific.y).get_luminance()])
		result = 1
	var clouds := _image("res://assets/textures/clouds/clouds.jpg")
	var clear := false
	var cloudy := false
	for y in range(0, clouds.get_height(), 64):
		for x in range(0, clouds.get_width(), 64):
			var cover := clouds.get_pixel(x, y).r
			clear = clear or cover < 0.1
			cloudy = cloudy or cover > 0.9
	if not clear or not cloudy:
		print("FAIL _test_planet_maps: clear skies %s, overcast %s" % [clear, cloudy])
		result = 1
	return result

func _test_imported_compressed_with_mipmaps() -> int:
	# Every baked texture goes to the GPU VRAM-compressed with mipmaps (as the
	# station's do): without mipmaps panels and stripes shimmer when small on
	# screen, and uncompressed they took ~200 MB. Normal maps are imported as
	# normal maps. Set explicitly: the 3D auto-detection only runs in the
	# editor.
	var result := 0
	var paths := []
	for folder in ["bridge", "interior_tube", "interior_cap"]:
		for channel in ["color", "roughness", "normal", "emission"]:
			paths.append("res://assets/textures/%s/%s.png" % [folder, channel])
	paths.append("res://assets/textures/planet/color.jpg")
	paths.append("res://assets/textures/planet/lights.jpg")
	for channel in ["roughness", "normal"]:
		paths.append("res://assets/textures/planet/%s.png" % channel)
	paths.append("res://assets/textures/clouds/clouds.jpg")
	paths.append("res://assets/textures/sky/stars.png")
	paths.append("res://assets/textures/labels/atlas.png")
	for path in paths:
		var config := ConfigFile.new()
		if config.load(path + ".import") != OK:
			print("FAIL _test_imported_compressed_with_mipmaps: no %s.import" % path)
			result = 1
			continue
		var normal_map: int = 1 if path.ends_with("normal.png") else 0
		if config.get_value("params", "compress/mode", -1) != 2 or config.get_value("params", "mipmaps/generate", false) != true or config.get_value("params", "detect_3d/compress_to", -1) != 0 or config.get_value("params", "compress/normal_map", -1) != normal_map:
			print("FAIL _test_imported_compressed_with_mipmaps: %s imports with mode %s, mipmaps %s, normal map %s" % [path, config.get_value("params", "compress/mode", -1), config.get_value("params", "mipmaps/generate", false), config.get_value("params", "compress/normal_map", -1)])
			result = 1
	return result

func _test_star_map() -> int:
	# 8192 x 4096 with plenty of clearly visible stars.
	var image := _image("res://assets/textures/sky/stars.png")
	if image == null or image.get_size() != Vector2i(8192, 4096):
		print("FAIL _test_star_map: missing or not 8192x4096")
		return 1
	var bright := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).get_luminance() > 0.35:
				bright += 1
	# Stars are 1-2 px with their peak on one pixel, most faint by design:
	# about 5000 pixels over 0.35 on the whole map, a quarter of them here.
	if bright < 500:
		print("FAIL _test_star_map: only %d clearly visible star pixels on a quarter of the map" % bright)
		return 1
	return 0
