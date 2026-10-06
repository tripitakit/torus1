extends "res://scripts/alpha_interior.gd"

# A far-side outpost's building inside (TelescopeLayout, DepotLayout), on the
# Alpha-style builder: the airlock with its suit lockers and turning warning
# lights, the hatch to the surface (shut: K takes the pilot out), the room
# beyond with its window on the dish or the silo field. Nobody about.

const HATCH_REACH := 2.5

var _beacons: Array[Node3D] = []

func build() -> void:
	build_shell()
	_build_hatch(get_node("Rooms") as Node3D)

func _process(delta: float) -> void:
	for beacon in _beacons:
		beacon.rotate_y(delta * 4.0)

func spawn_transform() -> Transform3D:
	return layout.spawn()

func near_hatch(point: Vector3) -> bool:
	var hatch: Transform3D = layout.hatch()
	return layout.room_at(point) == "airlock" and Vector2(point.x - hatch.origin.x, point.z - hatch.origin.z).length() <= HATCH_REACH

# The hatch: a heavy panel with hazard bands, a red light and the way out
# written above; two turning amber lights either side.
func _build_hatch(parent: Node3D) -> void:
	var hatch: Transform3D = layout.hatch()
	var height := DOOR_HEIGHT
	var panel := Transform3D(hatch.basis, hatch.origin + Vector3(0.0, height * 0.5, 0.0))
	_box(parent, Vector3(1.8, height, 0.16), _mat(STEEL), panel)
	_collide(Vector3(1.8, height, 0.2), panel)
	for k in range(5):
		_box(parent, Vector3(1.8, 0.12, 0.18), _mat(HAZARD if k % 2 == 0 else DARK), Transform3D(hatch.basis, hatch.origin + Vector3(0.0, 0.3 + k * 0.12, 0.0)))
	_cylinder(parent, 0.25, 0.08, _mat(DARK), Transform3D(hatch.basis * Basis(Vector3.RIGHT, PI * 0.5), hatch.origin + Vector3(0.0, 1.3, -0.1)))
	_box(parent, Vector3(0.14, 0.14, 0.04), _mat(Color(1.0, 0.2, 0.15), 2.5), Transform3D(hatch.basis, hatch.origin + Vector3(0.6, 2.0, -0.1)))
	for side in [-1.0, 1.0]:
		var beacon := Node3D.new()
		beacon.position = hatch.origin + hatch.basis * Vector3(side * 1.4, 2.7, -0.2)
		parent.add_child(beacon)
		_sphere(beacon, 0.1, _mat(Color(1.0, 0.55, 0.1), 2.5), _at(0.0, 0.0, 0.0))
		_box(beacon, Vector3(0.26, 0.05, 0.04), _mat(Color(1.0, 0.7, 0.2), 3.0), _at(0.0, 0.0, 0.0))
		_beacons.append(beacon)

# Beyond the window: the dish and the dome ("dish"), or the silo field and its
# laser fence ("field"), under the black sky.
func _view_texture(kind: String) -> ImageTexture:
	var w := 512
	var h := 192
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 2024
	noise.frequency = 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# The window shows the texture's middle band: the horizon low in it.
	var horizon := 135.0
	for y in range(h):
		for x in range(w):
			if y > horizon + noise.get_noise_1d(x * 0.5) * 6.0:
				var g := 0.42 + noise.get_noise_2d(x * 2.0, y * 4.0) * 0.06 + (y - horizon) / h * 0.12
				image.set_pixel(x, y, Color(g, g, g))
			else:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.01))
	for i in range(160):
		image.set_pixelv(Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, 100)), Color(1, 1, 1) * rng.randf_range(0.4, 1.0))
	if kind == "dish":
		# The dish: a white bowl tipped up on its tower; the dome to the side.
		var centre := Vector2(250.0, 100.0)
		for y in range(h):
			for x in range(w):
				if absf(x - centre.x) < 4.0 + (y - centre.y) * 0.12 and y > centre.y and y < horizon + 4.0:
					image.set_pixel(x, y, Color(0.6, 0.62, 0.65))
				var d := Vector2((x - centre.x) / 80.0, (y - centre.y + 6.0) / 30.0)
				if d.length() < 1.0:
					image.set_pixel(x, y, Color(0.92, 0.92, 0.9).darkened(0.3 * (1.0 - d.length())))
				var dome := Vector2((x - 420.0) / 34.0, (y - 135.0) / 26.0)
				if dome.length() < 1.0 and y <= 135:
					image.set_pixel(x, y, Color(0.85, 0.86, 0.88) if absf(x - 420.0) > 4.0 else Color(0.05, 0.05, 0.06))
	else:
		# The silo field: a pale cross on the ground, dark caps, the fence's
		# posts and red beams along its edge.
		for y in range(124, h):
			var depth := float(y - 124) / (h - 124)
			var half_arm := 30.0 + depth * 60.0
			var half_span := 120.0 + depth * 200.0
			var mid := 256.0
			var in_arm := absf(y - 150.0) < 6.0 + depth * 10.0
			for x in range(w):
				var cross_on := absf(x - mid) < half_arm or (in_arm and absf(x - mid) < half_span)
				if cross_on:
					image.set_pixel(x, y, Color(0.6, 0.6, 0.58))
		for k in range(14):
			var x := 256 + (k - 7) * 28
			for y in range(128, 140):
				image.set_pixel(clampi(x, 0, w - 1), y, Color(0.75, 0.75, 0.78))
		for y in [131, 134, 137]:
			for x in range(60, 452):
				image.set_pixel(x, y, Color(1.0, 0.15, 0.1))
		for k in range(10):
			var c := Vector2(160 + k * 22, 160 + (k % 3) * 8)
			for y in range(int(c.y) - 3, int(c.y) + 4):
				for x in range(int(c.x) - 6, int(c.x) + 7):
					if Vector2((x - c.x) / 6.0, (y - c.y) / 3.0).length() < 1.0:
						image.set_pixel(x, y, Color(0.25, 0.25, 0.27))
	return ImageTexture.create_from_image(image)
