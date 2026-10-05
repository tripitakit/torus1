extends Node3D

# Selene's interior, after Moonbase Alpha (Space: 1999, year one), built in
# code from SeleneLayout: solid walls of beige panels on the 1.2 m grid, the
# corridors' curved light panels, dark skirting with a glowing strip,
# coffered ceilings with recessed lights, wall computer banks with their
# tape reels, plants; the comm post at the crossing with its video screen,
# button console and direction signs; sliding doors in dark chamfered
# frames that open for anyone near; Main Mission with its window on the
# moon, the Big Screen between computer banks, the window consoles, the
# curved desks with monitors and globe lamps, the Commander's office up its
# steps behind a sliding glass wall; the hangar under the pad and the Travel
# Tube. Its own light and environment: the outside world is detached while
# the pilot is in here.

const SeleneLayout = preload("res://scripts/selene_layout.gd")
const SeleneCrew = preload("res://scripts/selene_crew.gd")

# Whoever is in here (the pilot, the crew): doors open for them.
const PEOPLE_GROUP := "selene_people"
const DOOR_REACH := 2.0
const DOOR_TIME := 0.5
const DOOR_HEIGHT := 2.4
const OFFICE_DOOR_HEIGHT := 3.6
const LIFT_SIZE := 6.0
const LIFT_REACH := 3.0
const WALL_THICK := SeleneLayout.WALL_THICK
const PANEL := Vector2(1.2, 2.4)
const WINDOW_SILL := 1.0
const WINDOW_TOP := 5.2
const CORRIDORS := ["corridor", "side_left", "side_right", "reception"]

const BEIGE := Color(0.86, 0.8, 0.68)
const FLOOR_GREY := Color(0.22, 0.23, 0.25)
const CEILING := Color(0.9, 0.88, 0.83)
const WHITE := Color(0.93, 0.93, 0.92)
const ORANGE := Color(0.95, 0.45, 0.1)
const DARK := Color(0.15, 0.16, 0.18)
const STEEL := Color(0.55, 0.57, 0.6)
const LAMP := Color(1.0, 0.97, 0.9)
const HAZARD := Color(0.95, 0.75, 0.1)
const GLOW := Color(0.95, 0.93, 0.86)
const STRIP := Color(0.55, 0.85, 1.0)
const GREEN := Color(0.3, 1.0, 0.5)

const BLINK_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 panel_color : source_color = vec3(0.15, 0.16, 0.18);
uniform vec2 cells = vec2(12.0, 5.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 cell = floor(UV * cells);
	vec2 inside = fract(UV * cells) - 0.5;
	float h = hash(cell);
	float on = step(0.5, fract(TIME * (0.3 + h * 1.5) + h));
	vec3 lamp = h < 0.33 ? vec3(1.0, 0.25, 0.15) : (h < 0.66 ? vec3(0.3, 1.0, 0.4) : vec3(1.0, 0.85, 0.3));
	float dot_mask = step(length(inside), 0.22);
	ALBEDO = mix(panel_color, lamp * mix(0.25, 1.4, on), dot_mask);
}
"""

# The Big Screen and the monitors: the planet on a scanning display, or
# green readouts.
const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform int mode = 0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float lines = 0.85 + 0.15 * sin(UV.y * 400.0 + TIME * 3.0);
	if (mode == 0) {
		float planet = smoothstep(0.42, 0.4, length(p - vec2(0.15, -0.05)));
		vec3 sky = vec3(0.02, 0.05, 0.12);
		vec3 disc = mix(vec3(0.15, 0.35, 0.7), vec3(0.85, 0.9, 1.0), smoothstep(-0.4, 0.4, p.y + p.x * 0.3));
		ALBEDO = mix(sky, disc, planet) * lines;
	} else if (mode == 1) {
		float row = floor(UV.y * 8.0);
		float bar = step(UV.x, fract(sin(row * 12.7 + floor(TIME * 0.7)) * 43758.5) * 0.8 + 0.1);
		float gap = step(0.25, fract(UV.y * 8.0));
		ALBEDO = vec3(0.05, 0.12, 0.06) + vec3(0.2, 0.9, 0.35) * bar * gap * 0.8;
	} else {
		// The videophone: a face in a blue field.
		float head = smoothstep(0.36, 0.33, length((p - vec2(0.0, 0.15)) * vec2(1.0, 0.8)));
		float body = smoothstep(0.02, 0.0, p.y + 0.35 - abs(p.x) * 0.3) * step(abs(p.x), 0.8);
		vec3 field = vec3(0.1, 0.25, 0.45);
		ALBEDO = mix(field, vec3(0.8, 0.65, 0.55), max(head, body * 0.7)) * lines;
	}
}
"""

# Zero for tests that need no crew; SeleneCrew fills the base otherwise.
var crew_count := 12

var _materials := {}
var _shell: StaticBody3D
var _blink: ShaderMaterial
var _beacons: Array[Node3D] = []

func build() -> void:
	_shell = StaticBody3D.new()
	_shell.name = "Shell"
	add_child(_shell)
	var rooms := Node3D.new()
	rooms.name = "Rooms"
	add_child(rooms)
	_blink = ShaderMaterial.new()
	_blink.shader = Shader.new()
	_blink.shader.code = BLINK_SHADER
	for room in SeleneLayout.rooms():
		if room.name != "tunnel":
			_build_room(room, rooms)
	for wall in SeleneLayout.walls():
		_build_wall(wall, rooms)
	_build_lintels(rooms)
	_build_doors(rooms)
	_build_ramp(rooms)
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	for item in SeleneLayout.furniture():
		_build_item(item, furniture)
	_build_post(furniture)
	_build_light_panels(rooms)
	_build_lift(rooms)
	_build_hangar(rooms)
	_build_window(rooms)
	_build_lights()
	_build_environment()
	_build_tube()
	_build_crew()

func _process(delta: float) -> void:
	for beacon in _beacons:
		beacon.rotate_y(delta * 4.0)

# Where the pilot arrives: in the hangar beside the lift's platform, facing it.
func spawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), SeleneLayout.lift_centre() + Vector3(-4.4, 0.0, -2.4))

func near_lift(point: Vector3) -> bool:
	var half := LIFT_SIZE * 0.5
	var c := SeleneLayout.lift_centre()
	var d := Vector2(maxf(absf(point.x - c.x) - half, 0.0), maxf(absf(point.z - c.z) - half, 0.0))
	return SeleneLayout.room_at(point) == "dock" and d.length() <= LIFT_REACH

func room_name(point: Vector3) -> String:
	var name := SeleneLayout.room_at(point)
	for room in SeleneLayout.rooms():
		if room.name == name:
			return room.label
	return ""

# --- building -----------------------------------------------------------

func _mat(color: Color, glow: float = 0.0, unshaded := false) -> Material:
	var key := "%s/%.2f/%s" % [color.to_html(), glow, unshaded]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.7
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = glow
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = m
	return _materials[key]

func _glass() -> Material:
	if not _materials.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.6, 0.75, 0.85, 0.25)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["glass"] = m
	return _materials["glass"]

func _screen(mode: int) -> ShaderMaterial:
	var key := "screen%d" % mode
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = SCREEN_SHADER
		m.set_shader_parameter("mode", mode)
		_materials[key] = m
	return _materials[key]

# Beige panels with dark joints every PANEL, wherever the wall is.
func _wall_material() -> Material:
	if not _materials.has("wall"):
		var image := Image.create_empty(48, 96, false, Image.FORMAT_RGB8)
		image.fill(BEIGE)
		var joint := BEIGE.darkened(0.35)
		for y in range(96):
			image.set_pixel(0, y, joint)
		for x in range(48):
			image.set_pixel(x, 0, joint)
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(image)
		m.roughness = 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(1.0 / PANEL.x, 1.0 / PANEL.y, 1.0 / PANEL.x)
		_materials["wall"] = m
	return _materials["wall"]

func _part(parent: Node3D, mesh: Mesh, material: Material, where: Transform3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = where
	parent.add_child(node)
	return node

func _box(parent: Node3D, size: Vector3, material: Material, where: Transform3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(parent, mesh, material, where)

func _cylinder(parent: Node3D, radius: float, height: float, material: Material, where: Transform3D, top: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	return _part(parent, mesh, material, where)

func _sphere(parent: Node3D, radius: float, material: Material, where: Transform3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _part(parent, mesh, material, where)

func _quad(parent: Node3D, size: Vector2, material: Material, where: Transform3D) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	return _part(parent, mesh, material, where)

func _collide(size: Vector3, where: Transform3D, owner_body: CollisionObject3D = null) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = where
	(owner_body if owner_body != null else _shell).add_child(shape)
	return shape

func _at(x: float, y: float, z: float, turn: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, turn), Vector3(x, y, z))

# Floor slab, and a coffered ceiling: recessed light panels on a grid.
func _build_room(room: Dictionary, parent: Node3D) -> void:
	var r: Rect2 = room.rect
	var centre := r.get_center()
	var floor_y: float = room.floor
	var thick := 0.2 + floor_y
	_box(parent, Vector3(r.size.x, thick, r.size.y), _mat(FLOOR_GREY), _at(centre.x, floor_y - thick * 0.5, centre.y))
	_collide(Vector3(r.size.x, thick, r.size.y), _at(centre.x, floor_y - thick * 0.5, centre.y))
	var top: float = floor_y + room.height
	_box(parent, Vector3(r.size.x, 0.1, r.size.y), _mat(CEILING), _at(centre.x, top + 0.05, centre.y))
	if room.name.begins_with("tube_"):
		return
	var step := 2.4
	var nx := maxi(1, floori(r.size.x / step))
	var nz := maxi(1, floori(r.size.y / step))
	for i in range(nx):
		for j in range(nz):
			var x := r.position.x + r.size.x * (i + 0.5) / nx
			var z := r.position.y + r.size.y * (j + 0.5) / nz
			_box(parent, Vector3(1.6, 0.12, 1.6), _mat(CEILING.darkened(0.15)), _at(x, top - 0.06, z))
			_box(parent, Vector3(1.2, 0.02, 1.2), _mat(GLOW, 0.8), _at(x, top - 0.13, z))

# A solid wall piece, both faces panelled; dark skirting with a glowing
# strip; Main Mission's window wall open between sill and top.
func _build_wall(wall: Dictionary, parent: Node3D) -> void:
	var a: Vector2 = wall.from
	var b: Vector2 = wall.to
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var along := (b - a).normalized()
	var turn := atan2(-along.y, along.x)
	var basis := Basis(Vector3.UP, turn)
	var height: float = wall.height
	var bands := [[0.0, height]]
	if wall.window:
		bands = [[0.0, WINDOW_SILL], [WINDOW_TOP, height]]
	for band in bands:
		_box(parent, Vector3(length, band[1] - band[0], WALL_THICK), _wall_material(), Transform3D(basis, Vector3(mid.x, (band[0] + band[1]) * 0.5, mid.y)))
	_collide(Vector3(length, height, WALL_THICK), Transform3D(basis, Vector3(mid.x, height * 0.5, mid.y)))
	_box(parent, Vector3(length, 0.16, WALL_THICK + 0.04), _mat(DARK), Transform3D(basis, Vector3(mid.x, 0.08, mid.y)))
	var corridor: bool = wall.rooms[0] in CORRIDORS or wall.rooms[1] in CORRIDORS
	if corridor:
		_box(parent, Vector3(length, 0.025, WALL_THICK + 0.06), _mat(STRIP, 1.5), Transform3D(basis, Vector3(mid.x, 0.2, mid.y)))

# Above every doorway the wall over the door, up to the taller side.
func _build_lintels(parent: Node3D) -> void:
	var by_name := {}
	for room in SeleneLayout.rooms():
		by_name[room.name] = room
	for door in SeleneLayout.doors():
		if door.kind == "tunnel":
			continue
		var top := OFFICE_DOOR_HEIGHT if door.kind == "office" else DOOR_HEIGHT
		var high := 0.0
		for side in [door.a, door.b]:
			high = maxf(high, by_name[side].floor + by_name[side].height)
		if door.kind == "open":
			top = minf(by_name[door.a].floor + by_name[door.a].height, by_name[door.b].floor + by_name[door.b].height)
		if high - top < 0.01:
			continue
		var c: Vector3 = door.centre
		var turn := 0.0 if door.axis == "x" else PI * 0.5
		var size := Vector3(door.width, high - top, WALL_THICK)
		_box(parent, size, _wall_material(), Transform3D(Basis(Vector3.UP, turn), Vector3(c.x, (top + high) * 0.5, c.z)))
		_collide(size, Transform3D(Basis(Vector3.UP, turn), Vector3(c.x, (top + high) * 0.5, c.z)))

func _build_doors(parent: Node3D) -> void:
	var doors := Node3D.new()
	doors.name = "Doors"
	add_child(doors)
	var list := SeleneLayout.doors()
	for k in range(list.size()):
		var door: Dictionary = list[k]
		if door.kind in ["open", "tunnel"]:
			continue
		var height := OFFICE_DOOR_HEIGHT if door.kind == "office" else DOOR_HEIGHT
		var node := SlidingDoor.new()
		node.name = "Door_%d" % k
		var panel: Material = _glass() if door.kind == "office" else _mat(WHITE)
		node.setup(door, height, panel, _mat(ORANGE))
		doors.add_child(node)
		_door_frame(parent, door, height, k)

# A dark frame with chamfered top corners, a status light, a number plate
# and the name of the room beyond, on both faces.
func _door_frame(parent: Node3D, door: Dictionary, height: float, number: int) -> void:
	var frame := Node3D.new()
	frame.transform = Transform3D(Basis(Vector3.UP, 0.0 if door.axis == "x" else PI * 0.5), door.centre)
	parent.add_child(frame)
	var w: float = door.width
	var depth := WALL_THICK + 0.12
	for side in [-1.0, 1.0]:
		_box(frame, Vector3(0.16, height, depth), _mat(DARK), _at(side * (w * 0.5 + 0.08), height * 0.5, 0.0))
		var chamfer := _box(frame, Vector3(0.5, 0.16, depth), _mat(DARK), _at(side * (w * 0.5 - 0.12), height - 0.12, 0.0))
		chamfer.rotation.z = side * PI * 0.25
	_box(frame, Vector3(w + 0.32, 0.16, depth), _mat(DARK), _at(0.0, height + 0.08, 0.0))
	var by_name := {}
	for room in SeleneLayout.rooms():
		by_name[room.name] = room
	for face in [1.0, -1.0]:
		var into: Vector2 = (by_name[door.b if face > 0.0 else door.a].rect as Rect2).get_center()
		var local := frame.transform.affine_inverse() * Vector3(into.x, 0.0, into.y)
		var facing: float = signf(local.z) * face
		var z: float = facing * (depth * 0.5 + 0.01)
		_box(frame, Vector3(0.1, 0.1, 0.02), _mat(GREEN, 2.0), _at(w * 0.5 - 0.1, height + 0.08, z))
		var plate := _label("%s-%02d" % ["A", number + 1], 0.07, Color(0.95, 0.95, 0.95))
		plate.transform = Transform3D(Basis(Vector3.UP, 0.0 if facing > 0.0 else PI), Vector3(-w * 0.5 + 0.25, height + 0.08, z + facing * 0.005))
		frame.add_child(plate)
		var other: Dictionary = by_name[door.a if face > 0.0 else door.b]
		var sign := _label(other.label, 0.1, Color(0.12, 0.12, 0.14))
		sign.transform = Transform3D(Basis(Vector3.UP, 0.0 if facing > 0.0 else PI), Vector3(0.0, height + 0.35, z))
		frame.add_child(sign)

# The steps up to the office: a ramp to walk on, three steps drawn.
func _build_ramp(parent: Node3D) -> void:
	var r := SeleneLayout.office_ramp()
	var rise := SeleneLayout.OFFICE_FLOOR
	var run := r.size.x
	var slope := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var centre := r.get_center()
	_collide(Vector3(length, 0.1, r.size.y), Transform3D(Basis(Vector3.BACK, slope), Vector3(centre.x, rise * 0.5 - 0.05 / cos(slope), centre.y)))
	for i in range(3):
		var height := rise * (i + 1) / 3.0
		_box(parent, Vector3(run / 3.0, height, r.size.y), _mat(WHITE.darkened(0.1)), _at(r.position.x + run / 3.0 * (i + 0.5), height * 0.5, centre.y))
		_box(parent, Vector3(0.04, 0.02, r.size.y), _mat(STRIP, 1.5), _at(r.position.x + run / 3.0 * i + 0.03, height + 0.01, centre.y))

func _monitor(parent: Node3D, where: Transform3D, size: Vector2, mode: int) -> void:
	_box(parent, Vector3(size.x + 0.08, size.y + 0.08, 0.08), _mat(DARK), where)
	_quad(parent, size, _screen(mode), where * Transform3D(Basis(), Vector3(0.0, 0.0, 0.041)))

func _reels(parent: Node3D, where: Transform3D) -> void:
	for x in [-0.22, 0.22]:
		var reel := _cylinder(parent, 0.16, 0.04, _mat(Color(0.3, 0.3, 0.32)), where * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.0, 0.0)))
		reel.name = "Reel"
		_cylinder(parent, 0.05, 0.05, _mat(WHITE), where * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.0, 0.01)))

func _build_item(item: Dictionary, parent: Node3D) -> void:
	var where: Transform3D = item.transform
	var size: Vector3 = item.size
	var node := Node3D.new()
	node.name = item.kind
	node.transform = where
	parent.add_child(node)
	var solid := true
	match item.kind:
		"desk", "office_desk", "reception_desk", "room_desk":
			# Curved white desks: a top with rounded ends on a recessed body.
			_box(node, Vector3(size.x, 0.06, size.z - size.x), _mat(WHITE), _at(0.0, size.y - 0.03, 0.0))
			for end in [-1.0, 1.0]:
				_cylinder(node, size.x * 0.5, 0.06, _mat(WHITE), _at(0.0, size.y - 0.03, end * (size.z - size.x) * 0.5))
			_box(node, Vector3(size.x * 0.7, size.y - 0.06, size.z * 0.85), _mat(WHITE.darkened(0.08)), _at(0.0, (size.y - 0.06) * 0.5, 0.0))
			_box(node, Vector3(size.x * 0.72, 0.04, size.z * 0.86), _mat(ORANGE), _at(0.0, size.y - 0.12, 0.0))
			if item.kind in ["desk", "office_desk"]:
				# The computer panel and a monitor toward the seat (+X).
				_box(node, Vector3(0.12, 0.4, size.z * 0.6), _mat(DARK), Transform3D(Basis(Vector3.BACK, 0.3), Vector3(-size.x * 0.1, size.y + 0.17, -size.z * 0.12)))
				_quad(node, Vector2(size.z * 0.55, 0.32), _blink, Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -0.3), Vector3(-size.x * 0.1 + 0.07, size.y + 0.17, -size.z * 0.12)))
				_monitor(node, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-size.x * 0.2, size.y + 0.35, size.z * 0.22)), Vector2(0.4, 0.3), 1)
			_cylinder(node, 0.015, 0.45, _mat(WHITE), _at(0.0, size.y + 0.22, size.z * 0.42))
			_sphere(node, 0.13, _mat(LAMP, 2.0), _at(0.0, size.y + 0.5, size.z * 0.42))
		"chair":
			_cylinder(node, 0.25, 0.04, _mat(DARK), _at(0.0, 0.02, 0.0))
			_cylinder(node, 0.04, 0.42, _mat(STEEL), _at(0.0, 0.23, 0.0))
			_cylinder(node, 0.26, 0.08, _mat(ORANGE), _at(0.0, 0.47, 0.0))
			_box(node, Vector3(0.48, 0.42, 0.07), _mat(WHITE), _at(0.0, 0.74, 0.22))
		"big_screen":
			_box(node, Vector3(size.x, size.y + 0.4, size.z + 0.4), _mat(DARK), _at(0.0, 3.0, 0.0))
			_quad(node, Vector2(size.z, size.y), _screen(0), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(size.x * 0.5 + 0.01, 3.0, 0.0)))
			_box(node, Vector3(0.2, 0.08, size.z + 0.4), _mat(ORANGE), _at(size.x * 0.5, 0.7, 0.0))
			solid = false
		"computer_bank", "wall_bank":
			# X5-style bank: dark cabinet, blinking lights, tape reels.
			var front := Basis(Vector3.UP, PI * 0.5 if where.origin.x < 0.0 else -PI * 0.5)
			_box(node, size, _mat(DARK), _at(0.0, size.y * 0.5, 0.0))
			var face := Transform3D(front, Vector3(0.0, 0.0, 0.0)) * Transform3D(Basis(), Vector3(0.0, 0.0, size.x * 0.5 + 0.01))
			_quad(node, Vector2(size.z * 0.9, size.y * 0.35), _blink, face * Transform3D(Basis(), Vector3(0.0, size.y * 0.72, 0.0)))
			_reels(node, face * Transform3D(Basis(), Vector3(-size.z * 0.22, size.y * 0.38, 0.02)))
			_reels(node, face * Transform3D(Basis(), Vector3(size.z * 0.22, size.y * 0.38, 0.02)))
			_box(node, Vector3(size.x + 0.02, 0.06, size.z + 0.02), _mat(ORANGE), _at(0.0, size.y * 0.15, 0.0))
		"window_console":
			_box(node, Vector3(size.x, size.y * 0.8, size.z), _mat(DARK), _at(0.0, size.y * 0.4, 0.0))
			_quad(node, Vector2(size.x * 0.95, size.z * 0.9), _blink, Transform3D(Basis(Vector3.RIGHT, -PI * 0.35), Vector3(0.0, size.y * 0.85, 0.0)))
			for x in [-0.9, 0.0, 0.9]:
				_monitor(node, Transform3D(Basis(Vector3.UP, PI), Vector3(x, size.y + 0.35, -0.15)), Vector2(0.55, 0.4), 1)
		"console", "cabinet", "dispenser", "scanner":
			_box(node, size, _mat(DARK if item.kind == "console" else WHITE), _at(0.0, size.y * 0.5, 0.0))
			_box(node, Vector3(size.x + 0.01, 0.08, size.z + 0.01), _mat(ORANGE), _at(0.0, size.y * 0.85, 0.0))
			var into_room := 1.0 if item.kind == "scanner" or where.origin.z < -5.0 else -1.0
			if item.kind in ["scanner", "dispenser"]:
				_monitor(node, Transform3D(Basis(Vector3.UP, PI if into_room < 0.0 else 0.0), Vector3(0.0, size.y * 0.6, into_room * (size.z * 0.5 + 0.05))), Vector2(size.x * 0.7, 0.35), 1)
		"post":
			solid = false
		"plant":
			_cylinder(node, 0.22, 0.45, _mat(WHITE), _at(0.0, 0.225, 0.0), 0.25)
			_box(node, Vector3(0.48, 0.03, 0.48), _mat(ORANGE), _at(0.0, 0.4, 0.0))
			for k in range(6):
				var angle := k * TAU / 6.0
				_sphere(node, 0.2, _mat(Color(0.2, 0.5, 0.22)), _at(cos(angle) * 0.15, 0.7 + (k % 3) * 0.15, sin(angle) * 0.15))
			_collide(Vector3(0.5, 1.0, 0.5), Transform3D(where.basis, where.origin + Vector3(0.0, 0.5, 0.0)))
			solid = false
		"bed":
			_box(node, Vector3(size.x, size.y * 0.6, size.z), _mat(WHITE), _at(0.0, size.y * 0.3, 0.0))
			_box(node, Vector3(size.x * 0.95, size.y * 0.4, size.z * 0.95), _mat(Color(0.7, 0.82, 0.9)), _at(0.0, size.y * 0.8, 0.0))
			_box(node, Vector3(size.x, 0.6, 0.08), _mat(WHITE), _at(0.0, size.y + 0.1, -size.z * 0.5))
		"table_set":
			_cylinder(node, 0.6, 0.05, _mat(WHITE), _at(0.0, 0.73, 0.0))
			_cylinder(node, 0.06, 0.7, _mat(STEEL), _at(0.0, 0.35, 0.0))
			_cylinder(node, 0.3, 0.03, _mat(DARK), _at(0.0, 0.015, 0.0))
			for k in range(4):
				var angle := k * PI * 0.5
				var seat := Vector3(sin(angle), 0.0, cos(angle)) * 0.85
				_cylinder(node, 0.24, 0.42, _mat(ORANGE), _at(seat.x, 0.21, seat.z), 0.26)
			_collide(Vector3(2.2, 0.75, 2.2), Transform3D(where.basis, where.origin + Vector3(0.0, 0.375, 0.0)))
			solid = false
		"pillar":
			_box(node, size, _mat(STEEL), _at(0.0, size.y * 0.5, 0.0))
			for k in range(4):
				var stripe := _box(node, Vector3(size.x + 0.02, 0.18, size.z + 0.02), _mat(HAZARD if k % 2 == 0 else DARK), _at(0.0, 0.2 + k * 0.18, 0.0))
				stripe.name = "Stripe"
		"booth":
			# The hangar's control booth: dark base, glass all round, a console.
			_box(node, Vector3(size.x, 1.0, size.z), _mat(DARK), _at(0.0, 0.5, 0.0))
			_box(node, Vector3(size.x, size.y - 1.0, size.z), _glass(), _at(0.0, 1.0 + (size.y - 1.0) * 0.5, 0.0))
			_box(node, Vector3(size.x + 0.1, 0.1, size.z + 0.1), _mat(DARK), _at(0.0, size.y, 0.0))
			_quad(node, Vector2(size.z * 0.8, 0.4), _blink, Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.5), Vector3(-size.x * 0.5 - 0.01, 0.95, 0.0)))
	if solid:
		_collide(size, Transform3D(where.basis, where.origin + Vector3(0.0, size.y * 0.5, 0.0)))

# The comm post: a white column; on two faces a video screen and below it a
# sloping console of lit buttons; on all four a sign with the way to each
# place (an arrow drawn before each name).
func _build_post(parent: Node3D) -> void:
	var post := Node3D.new()
	post.name = "CommPost"
	post.position = SeleneLayout.POST
	parent.add_child(post)
	var height := 2.8
	_cylinder(post, 0.32, height, _mat(WHITE), _at(0.0, height * 0.5, 0.0))
	_cylinder(post, 0.36, 0.12, _mat(ORANGE), _at(0.0, height - 0.3, 0.0))
	_cylinder(post, 0.4, 0.1, _mat(DARK), _at(0.0, 0.05, 0.0))
	_collide(Vector3(SeleneLayout.POST_SIZE * 0.7, height, SeleneLayout.POST_SIZE * 0.7), _at(SeleneLayout.POST.x, height * 0.5, SeleneLayout.POST.z))
	for face in [1.0, -1.0]:
		var turn := 0.0 if face > 0.0 else PI
		var out := Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
		_box(post, Vector3(0.8, 0.62, 0.3), _mat(WHITE), out * _at(0.0, 1.62, 0.25))
		_monitor(post, out * _at(0.0, 1.62, 0.41), Vector2(0.62, 0.46), 2)
		_box(post, Vector3(0.72, 0.1, 0.36), _mat(WHITE), out * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 1.12, 0.36)))
		_quad(post, Vector2(0.64, 0.3), _blink, out * Transform3D(Basis(Vector3.RIGHT, -0.5 - PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.18, 0.38)))
	for sign_data in SeleneLayout.post_signs():
		var normal: Vector3 = sign_data.normal
		var basis := Basis.looking_at(-normal, Vector3.UP)
		var face := Transform3D(basis, normal * 0.44 + Vector3(0.0, 2.25, 0.0))
		_box(post, Vector3(0.66, 0.66, 0.03), _mat(WHITE), face)
		_box(post, Vector3(0.66, 0.05, 0.035), _mat(ORANGE), face * Transform3D(Basis(), Vector3(0.0, 0.33, 0.0)))
		var lines: Array = sign_data.lines
		for k in range(lines.size()):
			var y := 0.23 - k * 0.115
			var text := _label(lines[k][0], 0.052, Color(0.12, 0.12, 0.14))
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			text.transform = face * Transform3D(Basis(), Vector3(-0.2, y, 0.02))
			post.add_child(text)
			_arrow(post, face * Transform3D(Basis(), Vector3(-0.26, y, 0.02)), lines[k][1])

# A small flat arrow on a sign: "↑" ahead, "↓" back, "→", "←".
func _arrow(parent: Node3D, where: Transform3D, arrow: String) -> void:
	var angle := {"↑": 0.0, "←": PI * 0.5, "↓": PI, "→": -PI * 0.5}[arrow] as float
	var holder := Node3D.new()
	holder.transform = where * Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
	parent.add_child(holder)
	_box(holder, Vector3(0.03, 0.05, 0.01), _mat(ORANGE), _at(0.0, -0.02, 0.0))
	var head := PrismMesh.new()
	head.size = Vector3(0.085, 0.05, 0.01)
	_part(holder, head, _mat(ORANGE), _at(0.0, 0.028, 0.0))

# The corridors' curved light panels: half-cylinders in a dark frame along
# every corridor face, clear of doors and wall banks.
func _build_light_panels(parent: Node3D) -> void:
	var busy := []
	for door in SeleneLayout.doors():
		busy.append([Vector2(door.centre.x, door.centre.z), door.width * 0.5 + 0.7])
	for item in SeleneLayout.furniture():
		if item.kind in ["wall_bank", "plant"]:
			busy.append([Vector2(item.transform.origin.x, item.transform.origin.z), 1.6])
	for wall in SeleneLayout.walls():
		var a: Vector2 = wall.from
		var b: Vector2 = wall.to
		var along := (b - a).normalized()
		var length := a.distance_to(b)
		var turn := atan2(-along.y, along.x)
		for side in [0, 1]:
			if not (wall.rooms[side] in CORRIDORS):
				continue
			var normal: Vector2 = wall.normal * (1.0 if side == 1 else -1.0)
			var s := 0.9
			while s < length - 0.6:
				var p := a + along * s
				var clear := true
				for spot in busy:
					if p.distance_to(spot[0]) < spot[1]:
						clear = false
				if clear:
					var at := p + normal * (WALL_THICK * 0.5)
					var face := Basis(Vector3.UP, turn)
					_box(parent, Vector3(0.9, 2.1, 0.04), _mat(DARK), Transform3D(face, Vector3(at.x, 1.55, at.y)))
					var tube := _cylinder(parent, 0.34, 1.9, _mat(GLOW, 0.7), Transform3D(face, Vector3(at.x, 1.55, at.y)))
					tube.scale = Vector3(1.0, 1.0, 0.45)
				s += 2.4

func _build_lift(parent: Node3D) -> void:
	var c := SeleneLayout.lift_centre()
	_box(parent, Vector3(LIFT_SIZE, 0.04, LIFT_SIZE), _mat(DARK), _at(c.x, 0.02, c.z))
	for side in range(4):
		var turn := side * PI * 0.5
		var edge := Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, LIFT_SIZE * 0.5 - 0.15)
		_box(parent, Vector3(LIFT_SIZE, 0.05, 0.3), _mat(HAZARD, 0.4), _at(c.x + edge.x, 0.025, c.z + edge.z, turn))
		var corner := Basis(Vector3.UP, turn) * Vector3(LIFT_SIZE * 0.5 + 0.4, 0.0, LIFT_SIZE * 0.5 + 0.4)
		_cylinder(parent, 0.14, 0.3, _mat(DARK), _at(c.x + corner.x, 0.15, c.z + corner.z))
		var beacon := Node3D.new()
		beacon.position = Vector3(c.x + corner.x, 0.42, c.z + corner.z)
		parent.add_child(beacon)
		_sphere(beacon, 0.12, _mat(Color(1.0, 0.55, 0.1), 2.5), _at(0.0, 0.0, 0.0))
		_box(beacon, Vector3(0.3, 0.06, 0.04), _mat(Color(1.0, 0.7, 0.2), 3.0), _at(0.0, 0.0, 0.0))
		_beacons.append(beacon)
	# The shaft up to the pad: a dark square in the ceiling with a rim.
	_box(parent, Vector3(LIFT_SIZE, 0.06, LIFT_SIZE), _mat(Color(0.05, 0.05, 0.06)), _at(c.x, 7.96, c.z))
	for side in range(4):
		var turn := side * PI * 0.5
		var edge := Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, LIFT_SIZE * 0.5)
		_box(parent, Vector3(LIFT_SIZE + 0.4, 0.4, 0.2), _mat(HAZARD), _at(c.x + edge.x, 7.8, c.z + edge.z, turn))

# The hangar: beams across the roof, pipes along the walls.
func _build_hangar(parent: Node3D) -> void:
	var r := SeleneLayout.room_rect("dock")
	for z in [-5.0, 5.0]:
		_box(parent, Vector3(r.size.x, 0.6, 0.5), _mat(STEEL), _at(r.get_center().x, 7.5, z))
	for x in [r.position.x + 1.0, r.end.x - 1.0]:
		_box(parent, Vector3(0.5, 0.6, r.size.y), _mat(STEEL), _at(x, 7.5, r.get_center().y))
	for k in range(3):
		var y := 5.5 + k * 0.35
		for x in [r.position.x + 0.25, r.end.x - 0.25]:
			_cylinder(parent, 0.1, r.size.y - 0.6, _mat(ORANGE if k == 1 else STEEL), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, r.get_center().y)))

# Main Mission's window: mullions every two panels and, beyond, the moon's
# surface under a black sky with the planet (a painted backdrop).
func _build_window(parent: Node3D) -> void:
	var room := SeleneLayout.room_rect("main_mission")
	var z := room.position.y
	var x := room.position.x
	while x <= room.end.x + 0.01:
		_box(parent, Vector3(0.14, WINDOW_TOP - WINDOW_SILL, 0.3), _mat(WHITE), _at(x, (WINDOW_SILL + WINDOW_TOP) * 0.5, z))
		x += PANEL.x * 2.0
	_box(parent, Vector3(room.size.x, 0.12, 0.4), _mat(WHITE), _at(room.get_center().x, WINDOW_SILL, z))
	var backdrop := QuadMesh.new()
	backdrop.size = Vector2(90.0, 34.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _moonscape()
	_part(parent, backdrop, m, _at(room.get_center().x, 7.0, z - 25.0))

func _moonscape() -> ImageTexture:
	var w := 512
	var h := 192
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 1999
	noise.frequency = 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var craters := []
	for i in range(40):
		craters.append(Vector3(rng.randf_range(0.0, w), rng.randf_range(125.0, h), rng.randf_range(3.0, 14.0)))
	for y in range(h):
		for x in range(w):
			var horizon := 120.0 + noise.get_noise_1d(x * 0.6) * 14.0
			if y > horizon:
				var g := 0.45 + noise.get_noise_2d(x * 2.0, y * 4.0) * 0.06 + (y - horizon) / h * 0.15
				for c: Vector3 in craters:
					var d := Vector2((x - c.x) / c.z, (y - c.y) / (c.z * 0.35)).length()
					if d < 1.0:
						g += -0.12 * (1.0 - d) if d < 0.8 else 0.1
				image.set_pixel(x, y, Color(g, g, g * 1.02))
			else:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.01))
	for i in range(160):
		var star := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, 100))
		var b := rng.randf_range(0.4, 1.0)
		image.set_pixelv(star, Color(b, b, b))
	var planet := Vector2(150.0, 45.0)
	for y in range(h):
		for x in range(w):
			var d := Vector2(x, y).distance_to(planet)
			if d < 26.0:
				var lit := clampf((x - planet.x + 18.0) / 40.0, 0.0, 1.0)
				image.set_pixel(x, y, Color(0.12, 0.3, 0.65).lerp(Color(0.85, 0.9, 1.0), lit * 0.6 + noise.get_noise_2d(x * 3.0, y * 3.0) * 0.3))
	return ImageTexture.create_from_image(image)

func _label(text: String, size: float, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = size / 32.0
	label.font_size = 32
	label.modulate = colour
	label.outline_size = 0
	label.double_sided = false
	return label

# A few warm lights per room, more in the big ones.
func _build_lights() -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	add_child(lights)
	for room in SeleneLayout.rooms():
		if room.name == "tunnel":
			continue
		var r: Rect2 = room.rect
		var nx := maxi(1, roundi(r.size.x / 8.0))
		var nz := maxi(1, roundi(r.size.y / 8.0))
		for i in range(nx):
			for j in range(nz):
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.95, 0.85)
				light.light_energy = 1.1
				light.omni_range = maxf(r.size.x / nx, r.size.y / nz) * 1.2 + room.height
				light.position = Vector3(r.position.x + r.size.x * (i + 0.5) / nx, room.floor + room.height - 0.4, r.position.y + r.size.y * (j + 0.5) / nz)
				lights.add_child(light)

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.95, 0.9, 0.82)
	environment.ambient_light_energy = 0.45
	world.environment = environment
	add_child(world)

# --- the Travel Tube ----------------------------------------------------

var _car: TubeCar

func tube_car() -> Node3D:
	return _car

# The stop the car stands at ("dock", "centre"), "" while it runs.
func car_stop() -> String:
	return _car.stop

func in_car(point: Vector3) -> bool:
	return _car.holds(point)

# Off to the other stop with whoever is aboard; false while it runs.
func start_ride() -> bool:
	if _car.stop == "":
		return false
	_car.run_to("centre" if _car.stop == "dock" else "dock")
	return true

# The car, empty, to `stop` (from in front of its door).
func call_car(stop: String) -> bool:
	if _car.stop == "" or _car.stop == stop:
		return false
	_car.run_to(stop)
	return true

# The stop whose Travel Tube door a point stands before, or "".
func near_tube_door(point: Vector3) -> String:
	for stop in ["dock", "centre"]:
		var door := (SeleneLayout.tube_stops()[stop] as Transform3D).origin + Vector3(0.0, 0.0, -1.8)
		var room := "dock" if stop == "dock" else "reception"
		if SeleneLayout.room_at(point) == room and Vector2(point.x - door.x, point.z - door.z).length() <= 2.5:
			return stop
	return ""

# The tunnel between the stations: floor, walls, roof, a rail, light rings
# every 6 m; and the car, at the hangar's stop.
func _build_tube() -> void:
	var r := SeleneLayout.room_rect("tunnel")
	var tube := Node3D.new()
	tube.name = "Tube"
	add_child(tube)
	var centre := r.get_center()
	var height := 3.6
	_box(tube, Vector3(r.size.x, 0.2, r.size.y + 0.4), _mat(FLOOR_GREY.darkened(0.3)), _at(centre.x, -0.1, centre.y))
	_collide(Vector3(r.size.x, 0.2, r.size.y), _at(centre.x, -0.1, centre.y))
	_box(tube, Vector3(r.size.x, 0.2, r.size.y + 0.4), _mat(STEEL.darkened(0.4)), _at(centre.x, height + 0.1, centre.y))
	for z in [r.position.y - 0.1, r.end.y + 0.1]:
		_box(tube, Vector3(r.size.x, height, 0.2), _mat(STEEL.darkened(0.3)), _at(centre.x, height * 0.5, z))
	for z in [centre.y - 0.8, centre.y + 0.8]:
		_box(tube, Vector3(r.size.x, 0.08, 0.1), _mat(STEEL), _at(centre.x, 0.04, z))
	var x := r.position.x + 3.0
	while x < r.end.x:
		for z in [r.position.y + 0.05, r.end.y - 0.05]:
			_box(tube, Vector3(0.25, height, 0.1), _mat(STRIP, 2.0), _at(x, height * 0.5, z))
		_box(tube, Vector3(0.25, 0.1, r.size.y), _mat(STRIP, 2.0), _at(x, height - 0.05, centre.y))
		x += 6.0
	_car = TubeCar.new()
	_car.name = "Car"
	add_child(_car)
	_car.setup(self)

# Main Mission's operators at their desks, the crew at work on their feet,
# the walkers on their rounds; all open the doors.
func _build_crew() -> void:
	if crew_count == 0:
		return
	var crew := Node3D.new()
	crew.name = "Crew"
	add_child(crew)
	var members := []
	for seat: Transform3D in SeleneLayout.crew_seats():
		var member := SeleneCrew.new_member("main_mission")
		member.transform = seat
		members.append(member)
		crew.add_child(member)
		member.sit()
	for worker in SeleneLayout.workers():
		var member := SeleneCrew.new_member(worker.department)
		member.transform = worker.transform
		crew.add_child(member)
		members.append(member)
		member.idle()
	var routes := SeleneLayout.routes()
	for k in range(routes.size()):
		var member := SeleneCrew.new_member(routes[k].department)
		crew.add_child(member)
		member.walk_route(routes[k].points, k)
		members.append(member)
	for k in range(members.size()):
		members[k].name = "Member_%02d" % k
		members[k].add_to_group(PEOPLE_GROUP)

# The Travel Tube's car: a kinematic box with benches, windows, a control
# panel with the line's map, a door on its -Z side that is shut while it
# runs. It runs along X from stop to stop (2 s up to speed, 2 s braking,
# ~10 s in all), carrying whoever is aboard.
class TubeCar extends AnimatableBody3D:
	const SIZE := Vector3(4.4, 2.8, 3.2)
	const DOOR_WIDTH := 1.8
	const RAMP := 2.0
	const TOP_SPEED := 25.0
	var stop := "dock"
	var _from := 0.0
	var _to := 0.0
	var _time := 0.0
	var _target := ""
	var _door := 0.0
	var _door_panel: Node3D
	var _door_shape: CollisionShape3D
	var _map: ShaderMaterial

	const MAP_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float progress = 0.0;
void fragment() {
	vec3 colour = vec3(0.04, 0.06, 0.1);
	float line = step(abs(UV.y - 0.5), 0.03) * step(0.08, UV.x) * step(UV.x, 0.92);
	colour = mix(colour, vec3(0.3, 0.6, 1.0), line);
	for (int i = 0; i < 2; i++) {
		float end = i == 0 ? 0.08 : 0.92;
		colour = mix(colour, vec3(1.0), step(length(vec2((UV.x - end) * 2.0, UV.y - 0.5)), 0.06));
	}
	float x = mix(0.08, 0.92, progress);
	float dot_on = step(length(vec2((UV.x - x) * 2.0, UV.y - 0.5)), 0.09) * step(0.5, fract(TIME * 2.0));
	ALBEDO = mix(colour, vec3(1.0, 0.6, 0.1), dot_on);
}
"""

	func setup(base) -> void:
		sync_to_physics = false
		transform = SeleneLayout.tube_stops().dock
		var white: Material = base._mat(WHITE)
		var dark: Material = base._mat(DARK)
		var half := SIZE * 0.5
		# Floor and roof.
		base._box(self, Vector3(SIZE.x, 0.1, SIZE.z), base._mat(FLOOR_GREY), Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)))
		base._collide(Vector3(SIZE.x, 0.1, SIZE.z), Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), self)
		base._box(self, Vector3(SIZE.x, 0.1, SIZE.z), white, Transform3D(Basis(), Vector3(0.0, SIZE.y, 0.0)))
		base._box(self, Vector3(SIZE.x - 0.6, 0.02, 0.5), base._mat(GLOW, 0.9), Transform3D(Basis(), Vector3(0.0, SIZE.y - 0.06, 0.0)))
		# The back (+Z) and the ends: low walls, windows, a band above.
		for wall in [[Vector3(0.0, 0.0, half.z), Vector3(SIZE.x, 0.0, 0.1)], [Vector3(half.x, 0.0, 0.0), Vector3(0.1, 0.0, SIZE.z)], [Vector3(-half.x, 0.0, 0.0), Vector3(0.1, 0.0, SIZE.z)]]:
			var at: Vector3 = wall[0]
			var size: Vector3 = wall[1]
			base._box(self, Vector3(maxf(size.x, 0.1), 1.0, maxf(size.z, 0.1)), white, Transform3D(Basis(), at + Vector3(0.0, 0.5, 0.0)))
			base._box(self, Vector3(maxf(size.x, 0.1), 1.0, maxf(size.z, 0.1)), base._glass(), Transform3D(Basis(), at + Vector3(0.0, 1.5, 0.0)))
			base._box(self, Vector3(maxf(size.x, 0.1), 0.8, maxf(size.z, 0.1)), white, Transform3D(Basis(), at + Vector3(0.0, 2.4, 0.0)))
			base._box(self, Vector3(maxf(size.x, 0.1) + 0.02, 0.06, maxf(size.z, 0.1) + 0.02), base._mat(ORANGE), Transform3D(Basis(), at + Vector3(0.0, 1.0, 0.0)))
			base._collide(Vector3(maxf(size.x, 0.1), SIZE.y, maxf(size.z, 0.1)), Transform3D(Basis(), at + Vector3(0.0, SIZE.y * 0.5, 0.0)), self)
		# The front (-Z): wall either side of the door, the door.
		var side := (SIZE.x - DOOR_WIDTH) * 0.5
		for sx in [-1.0, 1.0]:
			var at := Vector3(sx * (DOOR_WIDTH * 0.5 + side * 0.5), SIZE.y * 0.5, -half.z)
			base._box(self, Vector3(side, SIZE.y, 0.1), white, Transform3D(Basis(), at))
			base._collide(Vector3(side, SIZE.y, 0.1), Transform3D(Basis(), at), self)
		_door_panel = Node3D.new()
		add_child(_door_panel)
		base._box(_door_panel, Vector3(DOOR_WIDTH, SIZE.y - 0.3, 0.06), white, Transform3D(Basis(), Vector3(0.0, (SIZE.y - 0.3) * 0.5, -half.z)))
		base._box(_door_panel, Vector3(DOOR_WIDTH, 0.1, 0.08), base._mat(ORANGE), Transform3D(Basis(), Vector3(0.0, 1.0, -half.z)))
		_door_shape = base._collide(Vector3(DOOR_WIDTH, SIZE.y, 0.1), Transform3D(Basis(), Vector3(0.0, SIZE.y * 0.5, -half.z)), self)
		base._box(self, Vector3(DOOR_WIDTH, 0.3, 0.1), white, Transform3D(Basis(), Vector3(0.0, SIZE.y - 0.15, -half.z)))
		# Benches along the ends, the panel with the map by the door.
		for sx in [-1.0, 1.0]:
			base._box(self, Vector3(0.5, 0.45, SIZE.z - 0.6), base._mat(ORANGE), Transform3D(Basis(), Vector3(sx * (half.x - 0.35), 0.25, 0.1)))
			base._box(self, Vector3(0.1, 0.5, SIZE.z - 0.6), white, Transform3D(Basis(), Vector3(sx * (half.x - 0.12), 0.7, 0.1)))
		var panel_at := Transform3D(Basis(), Vector3(-half.x + 1.0, 1.4, -half.z + 0.06))
		base._box(self, Vector3(0.9, 0.7, 0.06), dark, panel_at)
		_map = ShaderMaterial.new()
		_map.shader = Shader.new()
		_map.shader.code = MAP_SHADER
		base._quad(self, Vector2(0.8, 0.3), _map, panel_at * Transform3D(Basis(), Vector3(0.0, 0.15, 0.035)))
		base._quad(self, Vector2(0.8, 0.25), base._blink, panel_at * Transform3D(Basis(), Vector3(0.0, -0.17, 0.035)))
		var sign: Label3D = base._label("TRAVEL TUBE", 0.12, Color(0.12, 0.12, 0.14))
		sign.transform = Transform3D(Basis(), Vector3(0.0, SIZE.y - 0.15, -half.z - 0.06)) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		add_child(sign)

	func holds(point: Vector3) -> bool:
		var local := to_local(point)
		return absf(local.x) < SIZE.x * 0.5 and absf(local.z) < SIZE.z * 0.5 and local.y > -0.5 and local.y < SIZE.y

	func door_closed() -> bool:
		return not _door_shape.disabled

	func run_to(target: String) -> void:
		_target = target
		_from = position.x
		_to = (SeleneLayout.tube_stops()[target] as Transform3D).origin.x
		_time = 0.0
		stop = ""

	# Distance covered `t` seconds into a run of `length`.
	static func covered(t: float, length: float) -> float:
		var accel := TOP_SPEED / RAMP
		var ramp_distance := 0.5 * TOP_SPEED * RAMP
		var cruise := (length - 2.0 * ramp_distance) / TOP_SPEED
		if t < RAMP:
			return 0.5 * accel * t * t
		if t < RAMP + cruise:
			return ramp_distance + TOP_SPEED * (t - RAMP)
		var left := maxf(2.0 * RAMP + cruise - t, 0.0)
		return length - 0.5 * accel * left * left

	func _physics_process(delta: float) -> void:
		var wanted := 0.0
		if stop != "":
			for person in get_tree().get_nodes_in_group(PEOPLE_GROUP):
				var p := to_local((person as Node3D).global_position)
				if absf(p.x) < DOOR_WIDTH and absf(p.z + SIZE.z * 0.5) < DOOR_REACH:
					wanted = 1.0
		_door = move_toward(_door, wanted, delta / DOOR_TIME)
		_door_panel.position.x = DOOR_WIDTH * _door
		_door_shape.disabled = stop != "" and _door > 0.3
		if stop != "":
			return
		# Shut first, then away.
		if _door > 0.0:
			return
		_time += delta
		var length := absf(_to - _from)
		var x := _from + signf(_to - _from) * covered(_time, length)
		var dx := x - position.x
		for person in get_tree().get_nodes_in_group(PEOPLE_GROUP):
			if holds((person as Node3D).global_position):
				(person as Node3D).global_position.x += dx
		position.x = x
		_map.set_shader_parameter("progress", clampf(x / SeleneLayout.DOCK_X, 0.0, 1.0))
		if _time >= 2.0 * RAMP + (length - TOP_SPEED * RAMP) / TOP_SPEED:
			position.x = _to
			stop = _target

# A sliding door (or the office's sliding glass wall): its panels slide
# aside in DOOR_TIME when someone of PEOPLE_GROUP is within DOOR_REACH, and
# back once nobody is; it stops nobody while open.
class SlidingDoor extends Node3D:
	var _amount := 0.0
	var _panels: Array[Node3D] = []
	var _closed_at: Array[float] = []
	var _slide: Array[float] = []
	var _shape: CollisionShape3D

	func setup(door: Dictionary, height: float, panel_material: Material, stripe_material: Material) -> void:
		position = door.centre
		rotation.y = 0.0 if door.axis == "x" else PI * 0.5
		var width: float = door.width
		var halves := 1 if door.kind == "door" else 2
		var panel_width := width / halves
		for k in range(halves):
			var holder := Node3D.new()
			add_child(holder)
			var centre := -width * 0.5 + panel_width * (k + 0.5)
			holder.position.x = centre
			var mesh := BoxMesh.new()
			mesh.size = Vector3(panel_width, height, 0.08)
			var panel := MeshInstance3D.new()
			panel.mesh = mesh
			panel.material_override = panel_material
			panel.position.y = height * 0.5
			holder.add_child(panel)
			var stripe_mesh := BoxMesh.new()
			stripe_mesh.size = Vector3(panel_width, 0.12, 0.1)
			var stripe := MeshInstance3D.new()
			stripe.mesh = stripe_mesh
			stripe.material_override = stripe_material
			stripe.position.y = height * 0.55
			holder.add_child(stripe)
			_panels.append(holder)
			_closed_at.append(centre)
			# One panel slides by its width; of two, each to its own side.
			_slide.append(panel_width * (1.0 if halves == 1 or k == 1 else -1.0))
		var body := StaticBody3D.new()
		add_child(body)
		_shape = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, height, 0.12)
		_shape.shape = box
		_shape.position.y = height * 0.5
		body.add_child(_shape)

	func open_amount() -> float:
		return _amount

	func _physics_process(delta: float) -> void:
		var wanted := 0.0
		for person in get_tree().get_nodes_in_group(PEOPLE_GROUP):
			var p: Vector3 = (person as Node3D).global_position - global_position
			if Vector2(p.x, p.z).length() <= DOOR_REACH and absf(p.y) < 3.0:
				wanted = 1.0
				break
		_amount = move_toward(_amount, wanted, delta / DOOR_TIME)
		for k in range(_panels.size()):
			_panels[k].position.x = _closed_at[k] + _slide[k] * _amount
		_shape.disabled = _amount > 0.3
