extends SceneTree

# Bakes the moon's crater maps (run once, headless, with the double build):
#   <binary> --headless --path . -s tools/moon_textures.gd
# Writes assets/textures/moon/color.png and normal.png: equirectangular,
# u = longitude from atan2(z, x) (+0.5), v = colatitude from +Y, as the moon
# shader reads them. Normal map in tangent space: x east, y north.

const WIDTH := 2048
const HEIGHT := 1024
const RADIUS := 250000.0
const CRATERS := 700
const CRATER_RADIUS := Vector2(1000.0, 60000.0)
# No crater centre this close to Base Selene (moon.gd: 30 degrees from the
# sub-planet point, which is the moon's local -X).
const BASE_DIRECTION := Vector3(-0.8660254, 0.5, 0.0)
const BASE_CLEARANCE := 8000.0
const NORMAL_STRENGTH := 3.0
const OUT_DIR := "res://assets/textures/moon/"

func _init() -> void:
	var start := Time.get_ticks_msec()
	var heights := _heights()
	_save(_color(heights), OUT_DIR + "color.png")
	_save(_normals(heights), OUT_DIR + "normal.png")
	print("moon textures written in %d ms" % (Time.get_ticks_msec() - start))
	quit()

static func _direction(column: float, row: float) -> Vector3:
	var longitude: float = (column / WIDTH - 0.5) * TAU
	var colatitude: float = row / HEIGHT * PI
	return Vector3(sin(colatitude) * cos(longitude), cos(colatitude), sin(colatitude) * sin(longitude))

# Bowls with raised rims, each touching only its own box of pixels.
func _heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(WIDTH * HEIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var made := 0
	while made < CRATERS:
		var z := rng.randf_range(-1.0, 1.0)
		var turn := rng.randf() * TAU
		var ring := sqrt(1.0 - z * z)
		var centre := Vector3(ring * cos(turn), z, ring * sin(turn))
		# Many small craters, few large.
		var radius: float = CRATER_RADIUS.x * pow(CRATER_RADIUS.y / CRATER_RADIUS.x, pow(rng.randf(), 2.5))
		if acos(clampf(centre.dot(BASE_DIRECTION), -1.0, 1.0)) * RADIUS < BASE_CLEARANCE + radius:
			continue
		made += 1
		var depth := 0.2 * radius
		var reach: float = radius * 1.6 / RADIUS
		var colatitude := acos(clampf(centre.y, -1.0, 1.0))
		var longitude := atan2(centre.z, centre.x)
		var row_from := maxi(0, floori((colatitude - reach) / PI * HEIGHT))
		var row_to := mini(HEIGHT - 1, ceili((colatitude + reach) / PI * HEIGHT))
		for row in range(row_from, row_to + 1):
			var row_colatitude: float = (row + 0.5) / HEIGHT * PI
			var span: float = reach / maxf(sin(row_colatitude), 0.001)
			var columns := WIDTH if span >= PI else ceili(span / TAU * WIDTH) * 2 + 2
			var column_from := 0 if span >= PI else floori((longitude / TAU + 0.5) * WIDTH) - columns / 2
			for c in range(column_from, column_from + columns):
				var column := posmod(c, WIDTH)
				var here := _direction(column + 0.5, row + 0.5)
				var d: float = acos(clampf(here.dot(centre), -1.0, 1.0)) * RADIUS
				if d > radius * 1.6:
					continue
				var bowl: float = -depth * (1.0 - (d / radius) * (d / radius)) if d < radius else 0.0
				var rim: float = 0.25 * depth * exp(-pow((d - radius) / (0.25 * radius), 2.0))
				heights[row * WIDTH + column] += bowl + rim
	return heights

func _color(heights: PackedFloat32Array) -> Image:
	var maria := FastNoiseLite.new()
	maria.seed = 7
	maria.frequency = 2.2
	var fine := FastNoiseLite.new()
	fine.seed = 11
	fine.frequency = 24.0
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	for row in range(HEIGHT):
		for column in range(WIDTH):
			var here := _direction(column + 0.5, row + 0.5)
			var dark: float = clampf(maria.get_noise_3dv(here) * 2.0, 0.0, 1.0)
			var grey: float = 0.42 + 0.06 * fine.get_noise_3dv(here) - 0.12 * dark + 0.08 * clampf(heights[row * WIDTH + column] / 3000.0, -1.0, 1.0)
			image.set_pixel(column, row, Color(grey, grey, grey * 0.97))
	return image

func _normals(heights: PackedFloat32Array) -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	var north_step: float = PI * RADIUS / HEIGHT
	for row in range(HEIGHT):
		var east_step: float = maxf(TAU * RADIUS * sin((row + 0.5) / HEIGHT * PI) / WIDTH, north_step * 0.05)
		for column in range(WIDTH):
			var east: float = (heights[row * WIDTH + posmod(column + 1, WIDTH)] - heights[row * WIDTH + posmod(column - 1, WIDTH)]) / (2.0 * east_step)
			# North is toward smaller rows.
			var north: float = (heights[maxi(row - 1, 0) * WIDTH + column] - heights[mini(row + 1, HEIGHT - 1) * WIDTH + column]) / (2.0 * north_step)
			var n := Vector3(-east * NORMAL_STRENGTH, -north * NORMAL_STRENGTH, 1.0).normalized()
			image.set_pixel(column, row, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return image

func _save(image: Image, path: String) -> void:
	image.generate_mipmaps()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := image.save_png(path)
	if error != OK:
		print("SCRIPT ERROR: could not save %s (%d)" % [path, error])
