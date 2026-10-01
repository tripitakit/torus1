extends SceneTree

# The NASA maps as converted by tools/moon_maps.py: sizes, the maria darker
# than the highlands, Plato's floor below its rim.

const COLOR_PATH := "res://assets/textures/moon/color.jpg"
const NORMAL_PATH := "res://assets/textures/moon/normal.png"
const HEIGHTS_PATH := "res://assets/moon/heights.bin"
const HEIGHT_SIZE := Vector2i(4096, 2048)

func _init():
	var failures := 0
	failures += _test_sizes()
	failures += _test_maria_darker()
	failures += _test_plato_floor_below_its_rim()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# Pixel of (latitude, longitude) degrees on a `size` map.
func _pixel(latitude: float, longitude: float, size: Vector2i) -> Vector2i:
	return Vector2i(int((longitude + 180.0) / 360.0 * size.x) % size.x, clampi(int((90.0 - latitude) / 180.0 * size.y), 0, size.y - 1))

func _height(bytes: PackedByteArray, latitude: float, longitude: float) -> float:
	var p := _pixel(latitude, longitude, HEIGHT_SIZE)
	return bytes.decode_s16((p.y * HEIGHT_SIZE.x + p.x) * 2)

func _test_sizes() -> int:
	var colour := load(COLOR_PATH) as Texture2D
	var normal := load(NORMAL_PATH) as Texture2D
	var bytes := FileAccess.get_file_as_bytes(HEIGHTS_PATH)
	if colour == null or colour.get_size() != Vector2(8192, 4096) or normal == null or normal.get_size() != Vector2(4096, 2048) or bytes.size() != HEIGHT_SIZE.x * HEIGHT_SIZE.y * 2:
		print("FAIL _test_sizes: colour %s, normal %s, %d height bytes" % [colour.get_size() if colour else null, normal.get_size() if normal else null, bytes.size()])
		return 1
	return 0

func _test_maria_darker() -> int:
	# Mare Imbrium (33 N, 16 W) against the southern highlands (30 S, 5 E).
	var image := (load(COLOR_PATH) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	var size := Vector2i(image.get_width(), image.get_height())
	var mare := image.get_pixelv(_pixel(33.0, -16.0, size)).get_luminance()
	var highland := image.get_pixelv(_pixel(-30.0, 5.0, size)).get_luminance()
	if mare > highland - 0.1:
		print("FAIL _test_maria_darker: mare %.2f, highlands %.2f" % [mare, highland])
		return 1
	return 0

func _test_plato_floor_below_its_rim() -> int:
	# Plato (51.6 N, 9.4 W, 101 km across, ~14.5 km on our moon): the floor
	# a few hundred metres below the rim (scaled).
	var bytes := FileAccess.get_file_as_bytes(HEIGHTS_PATH)
	var floor_height := _height(bytes, 51.6, -9.4)
	var rim := _height(bytes, 51.6, -9.4 + 1.9 / cos(deg_to_rad(51.6)))
	if rim - floor_height < 150.0:
		print("FAIL _test_plato_floor_below_its_rim: floor %.0f m, rim %.0f m" % [floor_height, rim])
		return 1
	return 0
