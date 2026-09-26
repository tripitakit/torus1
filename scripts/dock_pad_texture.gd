extends RefCounted

# The docking pad's sci-fi look, drawn in code: dark metal plates with
# seams, a black-and-yellow hazard border, a glowing cyan landing ring with a
# cross-hair and chevrons pointing in, and green lamps at the corners. Built
# once and shared by the pads outside and the platforms inside the bridges.

const SIZE := 256
const PLATE_COLOR := Color(0.16, 0.17, 0.19)
const SEAM_COLOR := Color(0.07, 0.075, 0.085)
const HAZARD_YELLOW := Color(0.95, 0.75, 0.1)
const HAZARD_BLACK := Color(0.05, 0.05, 0.05)
const MARK_COLOR := Color(0.2, 0.85, 1.0)
const LAMP_COLOR := Color(0.3, 1.0, 0.4)
# Sizes as fractions of the pad side.
const BORDER := 0.07
const STRIPE_PIXELS := 12
const PLATE_PIXELS := 32
const RING_RADIUS := 0.3
const RING_HALF_WIDTH := 0.012
const INNER_RING_RADIUS := 0.12
const INNER_RING_HALF_WIDTH := 0.008
const CROSS_HALF_WIDTH := 0.005
const CHEVRON_NEAR := 0.33
const CHEVRON_DEPTH := 0.035
const CHEVRON_HALF_SPAN := 0.07
const LAMP_INSET := 0.13
const LAMP_RADIUS := 0.025
const GLOW_ENERGY := 2.0

static var _albedo: ImageTexture
static var _emission: ImageTexture
static var _pad_material: StandardMaterial3D
static var _platform_materials := {}

static func albedo_texture() -> ImageTexture:
	_build()
	return _albedo

static func emission_texture() -> ImageTexture:
	_build()
	return _emission

# For a mesh with its own 0..1 UVs across the pad (the pads outside).
static func pad_material() -> StandardMaterial3D:
	if _pad_material == null:
		_pad_material = StandardMaterial3D.new()
		_pad_material.albedo_texture = albedo_texture()
		_pad_material.metallic = 0.5
		_pad_material.roughness = 0.6
		_pad_material.emission_enabled = true
		# Multiply: only the marks and lamps glow, not the whole pad.
		_pad_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_pad_material.emission = Color.WHITE
		_pad_material.emission_texture = emission_texture()
		_pad_material.emission_energy_multiplier = GLOW_ENERGY
	return _pad_material

# For a box `size` metres wide (the platforms inside): the image is
# projected in the box's own frame, once across its top.
static func platform_material(size: float) -> StandardMaterial3D:
	if not _platform_materials.has(size):
		var material := pad_material().duplicate() as StandardMaterial3D
		material.uv1_triplanar = true
		material.uv1_world_triplanar = false
		material.uv1_scale = Vector3.ONE / size
		material.uv1_offset = Vector3(0.5, 0.5, 0.5)
		_platform_materials[size] = material
	return _platform_materials[size]

static func _build() -> void:
	if _albedo != null:
		return
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var emission := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in range(SIZE):
		for x in range(SIZE):
			var glow := _glow_at(x, y)
			emission.set_pixel(x, y, glow)
			albedo.set_pixel(x, y, glow if glow != Color.BLACK else _surface_at(x, y))
	_albedo = ImageTexture.create_from_image(albedo)
	_emission = ImageTexture.create_from_image(emission)

# The painted, non-glowing surface: hazard border or metal plates.
static func _surface_at(x: int, y: int) -> Color:
	var u := (x + 0.5) / SIZE
	var v := (y + 0.5) / SIZE
	if minf(minf(u, v), minf(1.0 - u, 1.0 - v)) < BORDER:
		return HAZARD_YELLOW if posmod(floori(float(x + y) / STRIPE_PIXELS), 2) == 0 else HAZARD_BLACK
	if x % PLATE_PIXELS < 2 or y % PLATE_PIXELS < 2:
		return SEAM_COLOR
	# Each plate a shade lighter or darker, so the pad reads as metal panels.
	var shade: float = (hash(Vector2i(floori(float(x) / PLATE_PIXELS), floori(float(y) / PLATE_PIXELS))) % 5 - 2) * 0.01
	return Color(PLATE_COLOR.r + shade, PLATE_COLOR.g + shade, PLATE_COLOR.b + shade)

# What glows: landing marks in cyan, corner lamps in green, else black.
static func _glow_at(x: int, y: int) -> Color:
	var u := (x + 0.5) / SIZE
	var v := (y + 0.5) / SIZE
	for corner in [Vector2(LAMP_INSET, LAMP_INSET), Vector2(1.0 - LAMP_INSET, LAMP_INSET), Vector2(LAMP_INSET, 1.0 - LAMP_INSET), Vector2(1.0 - LAMP_INSET, 1.0 - LAMP_INSET)]:
		if Vector2(u, v).distance_to(corner) < LAMP_RADIUS:
			return LAMP_COLOR
	var du := u - 0.5
	var dv := v - 0.5
	var r := sqrt(du * du + dv * dv)
	if absf(r - RING_RADIUS) < RING_HALF_WIDTH or absf(r - INNER_RING_RADIUS) < INNER_RING_HALF_WIDTH:
		return MARK_COLOR
	if r < RING_RADIUS - 0.04 and (absf(du) < CROSS_HALF_WIDTH or absf(dv) < CROSS_HALF_WIDTH):
		return MARK_COLOR
	# Four chevrons outside the ring, their tips pointing at the centre.
	for axis in [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]:
		var along: float = du * axis.x + dv * axis.y
		var across: float = absf(du * axis.y - dv * axis.x)
		var edge: float = CHEVRON_NEAR + across * 0.8
		if across < CHEVRON_HALF_SPAN and along > edge and along < edge + CHEVRON_DEPTH:
			return MARK_COLOR
	return Color.BLACK
