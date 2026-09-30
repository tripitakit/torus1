extends RefCounted

# Base Selene: a command tower, four arms of modules joined by tubes, and six
# landing pads (three at the end of the east arm, three at the west) each
# with a hangar. Laid out on the base's tangent plane (x east, z south,
# metres from the tower), every piece then set on the sphere with its own
# vertical. Built under the moon as one static body (moon.gd).

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const BuildingShapesScript = preload("res://scripts/building_shapes.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")
const DockPadTexture = preload("res://scripts/dock_pad_texture.gd")
const TorusStation = preload("res://scripts/torus_station.gd")

const TOWER_RADIUS := 20.0
const TOWER_HEIGHT := 60.0
const MODULE_SIZE := Vector3(40.0, 10.0, 20.0)  # along the arm, up, across
const MODULE_SPACING := 90.0
const MODULES_PER_ARM := 5
const TUBE_WIDTH := 6.0
const PAD_SIZE := 60.0
const PAD_HEIGHT := 2.0
const PAD_POSITIONS := [560.0, 660.0, 760.0]
const HANGAR_SIZE := Vector3(30.0, 12.0, 40.0)  # x, up, z
const HANGAR_OFFSET := 70.0
const WHITE := Color(0.92, 0.93, 0.95)
const LIGHT_GREY := Color(0.78, 0.8, 0.83)
const TUBE_COLOR := Color(0.7, 0.72, 0.75)
const NUMBER_COLOR := Color(1.0, 0.96, 0.88)

# Every piece: {kind, name, centre (x, z), size (x, up, z), number (pads)}.
static func layout() -> Array:
	var pieces := []
	pieces.append({"kind": "tower", "name": "Tower", "centre": Vector2.ZERO, "size": Vector3(TOWER_RADIUS * 2.0, TOWER_HEIGHT, TOWER_RADIUS * 2.0), "number": 0})
	# Arms: east, west, south, north.
	for arm in [["East", Vector2(1, 0)], ["West", Vector2(-1, 0)], ["South", Vector2(0, 1)], ["North", Vector2(0, -1)]]:
		var direction: Vector2 = arm[1]
		var along_x: bool = direction.y == 0.0
		var module_size := Vector3(MODULE_SIZE.x, MODULE_SIZE.y, MODULE_SIZE.z) if along_x else Vector3(MODULE_SIZE.z, MODULE_SIZE.y, MODULE_SIZE.x)
		var previous_end := TOWER_RADIUS
		for k in range(MODULES_PER_ARM):
			var distance: float = MODULE_SPACING * (k + 1)
			var start: float = distance - MODULE_SIZE.x * 0.5
			pieces.append(_tube("%sTube%d" % [arm[0], k + 1], direction, previous_end, start))
			pieces.append({"kind": "module", "name": "%sModule%d" % [arm[0], k + 1], "centre": direction * distance, "size": module_size, "number": 0})
			previous_end = distance + MODULE_SIZE.x * 0.5
		if not along_x:
			continue
		# Pads out along the east and west arms, each with its hangar.
		for p in range(PAD_POSITIONS.size()):
			var number: int = p + 1 + (0 if direction.x > 0.0 else PAD_POSITIONS.size())
			var centre: Vector2 = direction * PAD_POSITIONS[p]
			pieces.append(_tube("%sPadTube%d" % [arm[0], p + 1], direction, previous_end, PAD_POSITIONS[p] - PAD_SIZE * 0.5))
			pieces.append({"kind": "pad", "name": "Pad%d" % number, "centre": centre, "size": Vector3(PAD_SIZE, PAD_HEIGHT, PAD_SIZE), "number": number})
			pieces.append({"kind": "hangar", "name": "Hangar%d" % number, "centre": centre + Vector2(0.0, HANGAR_OFFSET), "size": HANGAR_SIZE, "number": number})
			pieces.append(_tube("HangarTube%d" % number, Vector2(0, 1), PAD_SIZE * 0.5, HANGAR_OFFSET - HANGAR_SIZE.z * 0.5, centre.x))
			previous_end = PAD_POSITIONS[p] + PAD_SIZE * 0.5
	return pieces

# A tube along `direction` from `from` to `to` metres out (offset sideways
# to x = `shift` for the hangar tubes, which run along z).
static func _tube(tube_name: String, direction: Vector2, from: float, to: float, shift := 0.0) -> Dictionary:
	var length: float = to - from
	var centre: Vector2 = direction * (from + to) * 0.5 + Vector2(shift, 0.0)
	var along_x: bool = direction.y == 0.0
	var size := Vector3(length, TUBE_WIDTH, TUBE_WIDTH) if along_x else Vector3(TUBE_WIDTH, TUBE_WIDTH, length)
	return {"kind": "tube", "name": tube_name, "centre": centre, "size": size, "number": 0}

# Pads 1-6 in order.
static func pad_centres() -> Array[Vector2]:
	var centres: Array[Vector2] = []
	centres.resize(6)
	for piece in layout():
		if piece.kind == "pad":
			centres[piece.number - 1] = piece.centre
	return centres

# The ground under tangent point (x, z) in the base's frame (origin on the
# surface at the tower, y the local up there), and the local vertical.
static func ground(x: float, z: float, radius: float) -> Transform3D:
	var height: float = sqrt(radius * radius - x * x - z * z)
	var up := Vector3(x, height, z) / radius
	return Transform3D(Basis(Quaternion(Vector3.UP, up)), Vector3(x, height - radius, z))

# A piece's transform in the base's frame: centred at half its height
# above the ground, with the local vertical.
static func piece_transform(piece: Dictionary, radius: float) -> Transform3D:
	var at := ground(piece.centre.x, piece.centre.y, radius)
	return Transform3D(at.basis, at.origin + at.basis.y * piece.size.y * 0.5)

# Builds meshes and colliders into `base` (the moon's Base body).
static func build(base: StaticBody3D, radius: float) -> void:
	var building_material := ShaderMaterial.new()
	var building_shader := Shader.new()
	building_shader.code = TerrainDressingScript.BUILDING_SHADER
	building_material.shader = building_shader
	building_material.set_shader_parameter("glow_energy", TerrainDressingScript.BUILDING_GLOW_ENERGY)
	var tube_material := StandardMaterial3D.new()
	tube_material.albedo_color = TUBE_COLOR
	tube_material.roughness = 0.6
	tube_material.metallic = 0.3
	var lamp_mesh := QuadMesh.new()
	lamp_mesh.size = Vector2.ONE
	var lamp_material := ShaderMaterial.new()
	var lamp_shader := Shader.new()
	lamp_shader.code = TorusStation.LAMP_SHADER
	lamp_material.shader = lamp_shader
	lamp_material.set_shader_parameter("lamp_size", TorusStation.LAMP_SIZE)
	lamp_material.set_shader_parameter("min_pixels", TorusStation.LAMP_MIN_PIXELS)
	lamp_material.set_shader_parameter("lamp_color", TorusStation.LAMP_COLOR)
	lamp_material.set_shader_parameter("period", TorusStation.LAMP_PERIOD)
	lamp_material.set_shader_parameter("on_time", TorusStation.LAMP_ON_TIME)
	var buildings := {SectionPlanScript.Style.RING_TOWER: [], SectionPlanScript.Style.BLOCK: []}
	for piece in layout():
		var where := piece_transform(piece, radius)
		var collision := CollisionShape3D.new()
		collision.name = piece.name + "Collider"
		collision.transform = where
		match piece.kind:
			"tower":
				collision.shape = _tower_shape()
				buildings[SectionPlanScript.Style.RING_TOWER].append([where, piece])
			"module", "hangar":
				collision.shape = _box(piece.size)
				buildings[SectionPlanScript.Style.BLOCK].append([where, piece])
			"tube":
				collision.shape = _box(piece.size)
				base.add_child(_tube_mesh(piece, where, tube_material))
			"pad":
				collision.shape = _box(piece.size)
				base.add_child(_pad(piece, where, lamp_mesh, lamp_material))
		base.add_child(collision)
	for style in buildings:
		base.add_child(_buildings(style, buildings[style], building_material))

static func _box(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box

# The tower's hexagonal prism (its unit mesh scaled to the tower's size).
static func _tower_shape() -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for p in BuildingShapesScript.hull_points(SectionPlanScript.Style.RING_TOWER):
		points.append(p * Vector3(TOWER_RADIUS * 2.0, TOWER_HEIGHT, TOWER_RADIUS * 2.0))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape

# One MultiMesh of `style` for the tower or the modules and hangars, with
# the interior's facade shader: window bands, cool white light.
static func _buildings(style: int, entries: Array, material: ShaderMaterial) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = BuildingShapesScript.mesh(style)
	multimesh.instance_count = entries.size()
	for i in range(entries.size()):
		var where: Transform3D = entries[i][0]
		var piece: Dictionary = entries[i][1]
		multimesh.set_instance_transform(i, Transform3D(where.basis.scaled_local(piece.size), where.origin))
		multimesh.set_instance_color(i, WHITE if piece.kind != "hangar" else LIGHT_GREY)
		# Facade 0 (bands), accent 1 (cool white), 60% lit, a seed.
		multimesh.set_instance_custom_data(i, Color(0.0, 1.0, 0.6, fposmod(i * 0.618034, 1.0)))
	var node := MultiMeshInstance3D.new()
	node.name = BuildingShapesScript.NAMES[style]
	node.multimesh = multimesh
	node.material_override = material
	node.custom_aabb = AABB(Vector3(-900.0, -60.0, -900.0), Vector3(1800.0, 140.0, 1800.0))
	return node

# A tube as a cylinder along its long side.
static func _tube_mesh(piece: Dictionary, where: Transform3D, material: Material) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	var along_x: bool = piece.size.x > piece.size.z
	cylinder.height = piece.size.x if along_x else piece.size.z
	cylinder.top_radius = TUBE_WIDTH * 0.5
	cylinder.bottom_radius = TUBE_WIDTH * 0.5
	cylinder.radial_segments = 12
	var node := MeshInstance3D.new()
	node.name = piece.name
	node.mesh = cylinder
	node.material_override = material
	# The cylinder stands along y: lay it along x or z.
	var lay := Basis(Vector3.BACK, PI * 0.5) if along_x else Basis(Vector3.RIGHT, PI * 0.5)
	node.transform = Transform3D(where.basis * lay, where.origin)
	return node

# A pad: the station's pad plate on a 2 m block, four blinking lamps on its
# corners and its number lying on it.
static func _pad(piece: Dictionary, where: Transform3D, lamp_mesh: QuadMesh, lamp_material: ShaderMaterial) -> Node3D:
	var pad := Node3D.new()
	pad.name = piece.name
	pad.transform = where
	var block := MeshInstance3D.new()
	block.name = "Block"
	var box := BoxMesh.new()
	box.size = piece.size
	block.mesh = box
	block.material_override = DockPadTexture.platform_material(PAD_SIZE)
	pad.add_child(block)
	var top: float = PAD_HEIGHT * 0.5
	var half: float = PAD_SIZE * (0.5 - DockPadTexture.LAMP_INSET)
	var k := 0
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			var lamp := MeshInstance3D.new()
			lamp.name = "Lamp_%d" % k
			lamp.mesh = lamp_mesh
			lamp.material_override = lamp_material
			lamp.position = Vector3(a * half, top + 0.5, b * half)
			lamp.visibility_range_end = TorusStation.LAMP_RANGE
			lamp.extra_cull_margin = TorusStation.LAMP_CULL_MARGIN
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pad.add_child(lamp)
			k += 1
	var number := Label3D.new()
	number.name = "Number"
	number.text = str(piece.number)
	number.font_size = 256
	number.pixel_size = 0.06
	number.modulate = NUMBER_COLOR
	number.shaded = false
	# Lying on the pad, readable from above.
	number.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, top + 0.3, 0.0))
	pad.add_child(number)
	return pad
