extends Node3D

# Selene's interior, after Moonbase Alpha (Space: 1999, year one), built in
# code from SeleneLayout: beige wall panels on the 1.2 m grid, curved light
# panels down the corridors, the comm post at the crossing, sliding doors
# that open for anyone near, Main Mission with its window on the moon, the
# Big Screen, the desks with their globe lamps and blinking computer panels,
# the Commander's office up its steps behind a sliding wall; the dock under
# the pad and the Travel Tube. Its own light and environment: the outside
# world is detached while the pilot is in here.

const SeleneLayout = preload("res://scripts/selene_layout.gd")
const SeleneCrew = preload("res://scripts/selene_crew.gd")

# Whoever is in here (the pilot, the crew): doors open for them.
const PEOPLE_GROUP := "selene_people"
const DOOR_REACH := 2.0
const DOOR_TIME := 0.5
const DOOR_HEIGHT := 2.2
const OFFICE_DOOR_HEIGHT := 3.6
const LIFT_SIZE := 6.0
const LIFT_REACH := 3.0
const WALL_THICK := 0.2
const PANEL := Vector2(1.2, 2.4)
const WINDOW_SILL := 1.0
const WINDOW_TOP := 4.3

const BEIGE := Color(0.86, 0.8, 0.68)
const FLOOR_GREY := Color(0.24, 0.25, 0.27)
const CEILING := Color(0.9, 0.88, 0.83)
const WHITE := Color(0.93, 0.93, 0.92)
const ORANGE := Color(0.95, 0.45, 0.1)
const DARK := Color(0.17, 0.18, 0.2)
const LAMP := Color(1.0, 0.97, 0.9)
const HAZARD := Color(0.95, 0.75, 0.1)

const BLINK_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 panel_color : source_color = vec3(0.17, 0.18, 0.2);
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

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float planet = smoothstep(0.42, 0.4, length(p - vec2(0.15, -0.05)));
	float lines = 0.85 + 0.15 * sin(UV.y * 400.0 + TIME * 3.0);
	vec3 sky = vec3(0.02, 0.05, 0.12);
	vec3 disc = mix(vec3(0.15, 0.35, 0.7), vec3(0.85, 0.9, 1.0), smoothstep(-0.4, 0.4, p.y + p.x * 0.3));
	ALBEDO = mix(sky, disc, planet) * lines;
}
"""

# Zero for tests that need no crew; SeleneCrew fills the base otherwise.
var crew_count := 20

var _materials := {}
var _shell: StaticBody3D
var _blink: ShaderMaterial

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
		_build_room(room, rooms)
	for wall in SeleneLayout.walls():
		_build_wall(wall, rooms)
	_build_lintels(rooms)
	_build_doors()
	_build_ramp(rooms)
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	for item in SeleneLayout.furniture():
		_build_item(item, furniture)
	_build_light_panels(rooms)
	_build_lift(rooms)
	_build_window(rooms)
	_build_signs(rooms)
	_build_lights()
	_build_environment()
	_build_crew()

# Where the pilot arrives: in the dock beside the lift's platform, facing it.
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

# The Travel Tube stop a point is in ("dock", "centre"), or "".
func tube_stop_at(point: Vector3) -> String:
	match SeleneLayout.room_at(point):
		"tube_dock":
			return "dock"
		"tube_centre":
			return "centre"
	return ""

# Riding the tube from `from_stop`: where one gets off.
func tube_ride(from_stop: String) -> Transform3D:
	var stops := SeleneLayout.tube_stops()
	return stops.centre if from_stop == "dock" else stops.dock

# --- building -----------------------------------------------------------

func _mat(color: Color, glow: float = 0.0, unshaded := false) -> Material:
	var key := "%s/%.2f/%s" % [color.to_html(), glow, unshaded]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = glow
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = m
	return _materials[key]

# Beige panels with dark joints every PANEL (UV in panels).
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
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# One panel per texture repeat, wherever the wall is.
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

func _cylinder(parent: Node3D, radius: float, height: float, material: Material, where: Transform3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
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

func _build_room(room: Dictionary, parent: Node3D) -> void:
	var r: Rect2 = room.rect
	var centre := r.get_center()
	var floor_y: float = room.floor
	# A slab under the floor (thick for the raised office).
	var thick := 0.2 + floor_y
	_box(parent, Vector3(r.size.x, thick, r.size.y), _mat(FLOOR_GREY), _at(centre.x, floor_y - thick * 0.5, centre.y))
	_collide(Vector3(r.size.x, thick, r.size.y), _at(centre.x, floor_y - thick * 0.5, centre.y))
	var ceiling := PlaneMesh.new()
	ceiling.size = r.size
	ceiling.flip_faces = true
	_part(parent, ceiling, _mat(CEILING), _at(centre.x, floor_y + room.height, centre.y))

# A wall piece: drawn on its room's side of the line, with a box behind it
# to walk into; Main Mission's window wall is open between sill and top.
func _build_wall(wall: Dictionary, parent: Node3D) -> void:
	var a: Vector2 = wall.from
	var b: Vector2 = wall.to
	var inward: Vector2 = wall.inward
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5 + inward * WALL_THICK * 0.5
	var along := (b - a).normalized()
	var turn := atan2(-along.y, along.x)
	var bands := [[0.0, wall.height]]
	if wall.window:
		bands = [[0.0, WINDOW_SILL], [WINDOW_TOP, wall.height]]
	for band in bands:
		var quad := QuadMesh.new()
		quad.size = Vector2(length, band[1] - band[0])
		_part(parent, quad, _wall_material(), Transform3D(Basis(Vector3.UP, turn), Vector3(mid.x, wall.floor + (band[0] + band[1]) * 0.5, mid.y)))
	var centre := (a + b) * 0.5
	_collide(Vector3(length, wall.height, WALL_THICK), Transform3D(Basis(Vector3.UP, turn), Vector3(centre.x, wall.floor + wall.height * 0.5, centre.y)))

# Above every doorway, the wall over the door on both sides.
func _build_lintels(parent: Node3D) -> void:
	var by_name := {}
	for room in SeleneLayout.rooms():
		by_name[room.name] = room
	for door in SeleneLayout.doors():
		var top := OFFICE_DOOR_HEIGHT if door.kind == "office" else DOOR_HEIGHT
		if door.kind == "open":
			top = SeleneLayout.CORRIDOR_HEIGHT
		for side in [door.a, door.b]:
			var room: Dictionary = by_name[side]
			var r: Rect2 = room.rect
			var high: float = room.floor + room.height
			if high - top < 0.01:
				continue
			var c: Vector3 = door.centre
			var into := (r.get_center() - Vector2(c.x, c.z))
			var across := Vector2(0.0, signf(into.y)) if door.axis == "x" else Vector2(signf(into.x), 0.0)
			var where := Vector2(c.x, c.z) + across * WALL_THICK * 0.5
			var turn := 0.0 if door.axis == "x" else PI * 0.5
			var quad := QuadMesh.new()
			quad.size = Vector2(door.width, high - top)
			_part(parent, quad, _wall_material(), Transform3D(Basis(Vector3.UP, turn), Vector3(where.x, (top + high) * 0.5, where.y)))
			_collide(Vector3(door.width, high - top, WALL_THICK), Transform3D(Basis(Vector3.UP, turn), Vector3(c.x, (top + high) * 0.5, c.z)))

func _build_doors() -> void:
	var doors := Node3D.new()
	doors.name = "Doors"
	add_child(doors)
	var list := SeleneLayout.doors()
	for k in range(list.size()):
		var door: Dictionary = list[k]
		if door.kind == "open":
			continue
		var node := SlidingDoor.new()
		node.name = "Door_%d" % k
		node.setup(door, OFFICE_DOOR_HEIGHT if door.kind == "office" else DOOR_HEIGHT, _mat(WHITE), _mat(ORANGE))
		doors.add_child(node)

# The steps up to the office: a ramp to walk on, three steps drawn.
func _build_ramp(parent: Node3D) -> void:
	var r := SeleneLayout.office_ramp()
	var rise := SeleneLayout.OFFICE_FLOOR
	var run := r.size.x
	var slope := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var centre := r.get_center()
	var tilt := Basis(Vector3.BACK, slope)
	_collide(Vector3(length, 0.1, r.size.y), Transform3D(tilt, Vector3(centre.x, rise * 0.5 - 0.05 / cos(slope), centre.y)))
	for i in range(3):
		var height := rise * (i + 1) / 3.0
		_box(parent, Vector3(run / 3.0, height, r.size.y), _mat(WHITE.darkened(0.1)), _at(r.position.x + run / 3.0 * (i + 0.5), height * 0.5, centre.y))

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
			# White top on a white body, a dark computer panel on the sitting
			# side (+X) for Main Mission's desks, a globe lamp at one end.
			_box(node, Vector3(size.x, 0.06, size.z), _mat(WHITE), _at(0.0, size.y - 0.03, 0.0))
			_box(node, Vector3(size.x * 0.8, size.y - 0.06, size.z * 0.9), _mat(WHITE.darkened(0.05)), _at(0.0, (size.y - 0.06) * 0.5, 0.0))
			if item.kind == "desk":
				var face := QuadMesh.new()
				face.size = Vector2(size.z * 0.85, 0.4)
				_box(node, Vector3(0.1, 0.45, size.z * 0.85), _mat(DARK), _at(0.0, size.y + 0.22, 0.0))
				_part(node, face, _blink, _at(0.051, size.y + 0.22, 0.0, PI * 0.5))
			_cylinder(node, 0.015, 0.45, _mat(WHITE), _at(0.0, size.y + 0.22, size.z * 0.4))
			var globe := SphereMesh.new()
			globe.radius = 0.12
			globe.height = 0.24
			_part(node, globe, _mat(LAMP, 2.0), _at(0.0, size.y + 0.5, size.z * 0.4))
		"chair":
			_cylinder(node, 0.04, 0.42, _mat(DARK), _at(0.0, 0.21, 0.0))
			_box(node, Vector3(0.5, 0.08, 0.5), _mat(ORANGE), _at(0.0, 0.46, 0.0))
			_box(node, Vector3(0.5, 0.45, 0.08), _mat(WHITE), _at(0.0, 0.72, 0.22))
		"big_screen":
			_box(node, size, _mat(DARK), _at(0.0, 2.4, 0.0))
			var screen := QuadMesh.new()
			screen.size = Vector2(size.z - 0.3, size.y - 0.3)
			var m := ShaderMaterial.new()
			m.shader = Shader.new()
			m.shader.code = SCREEN_SHADER
			_part(node, screen, m, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(size.x * 0.5 + 0.01, 2.4, 0.0)))
			solid = false
		"console", "cabinet", "dispenser":
			_box(node, size, _mat(DARK if item.kind == "console" else WHITE), _at(0.0, size.y * 0.5, 0.0))
			var face := QuadMesh.new()
			face.size = Vector2(size.x * 0.9, size.y * 0.5)
			var front_material: Material = _blink if item.kind == "console" else _mat(ORANGE)
			_part(node, face, front_material, _at(0.0, size.y * 0.6, size.z * 0.5 + 0.01, PI if item.kind == "console" else 0.0))
		"post":
			_cylinder(node, 0.3, size.y, _mat(WHITE), _at(0.0, size.y * 0.5, 0.0))
			_cylinder(node, 0.32, 0.1, _mat(ORANGE), _at(0.0, 1.9, 0.0))
		"bed":
			_box(node, Vector3(size.x, size.y * 0.6, size.z), _mat(WHITE), _at(0.0, size.y * 0.3, 0.0))
			_box(node, Vector3(size.x * 0.95, size.y * 0.4, size.z * 0.95), _mat(Color(0.7, 0.82, 0.9)), _at(0.0, size.y * 0.8, 0.0))
		"table_set":
			_cylinder(node, 0.6, 0.05, _mat(WHITE), _at(0.0, 0.73, 0.0))
			_cylinder(node, 0.06, 0.7, _mat(WHITE), _at(0.0, 0.35, 0.0))
			for k in range(4):
				var angle := k * PI * 0.5
				var seat := Vector3(sin(angle), 0.0, cos(angle)) * 0.85
				_box(node, Vector3(0.45, 0.42, 0.45), _mat(ORANGE), _at(seat.x, 0.21, seat.z, angle))
			_collide(Vector3(2.2, 0.75, 2.2), Transform3D(where.basis, where.origin + Vector3(0.0, 0.375, 0.0)))
			solid = false
	if solid:
		_collide(size, Transform3D(where.basis, where.origin + Vector3(0.0, size.y * 0.5, 0.0)))

# The corridors' curved light panels: glowing panels along both walls,
# every second panel.
func _build_light_panels(parent: Node3D) -> void:
	for wall in SeleneLayout.walls():
		if not (wall.room in ["corridor", "side_left", "side_right", "reception"]):
			continue
		var a: Vector2 = wall.from
		var b: Vector2 = wall.to
		var along := (b - a).normalized()
		var inward: Vector2 = wall.inward
		var length := a.distance_to(b)
		var turn := atan2(-along.y, along.x)
		var s := PANEL.x
		while s + PANEL.x * 0.5 < length:
			var p := a + along * s + inward * (WALL_THICK * 0.5 + 0.06)
			var bulge := Basis(Vector3.UP, turn)
			_box(parent, Vector3(0.8, 1.6, 0.08), _mat(Color(0.95, 0.93, 0.86), 0.35), Transform3D(bulge, Vector3(p.x, 1.25, p.y)))
			s += PANEL.x * 2.0

func _build_lift(parent: Node3D) -> void:
	var c := SeleneLayout.lift_centre()
	_box(parent, Vector3(LIFT_SIZE, 0.04, LIFT_SIZE), _mat(DARK), _at(c.x, 0.02, c.z))
	for side in range(4):
		var turn := side * PI * 0.5
		var edge := Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, LIFT_SIZE * 0.5 - 0.15)
		_box(parent, Vector3(LIFT_SIZE, 0.05, 0.3), _mat(HAZARD, 0.4), _at(c.x + edge.x, 0.025, c.z + edge.z, turn))
		var corner := Basis(Vector3.UP, turn) * Vector3(LIFT_SIZE * 0.5 + 0.4, 0.0, LIFT_SIZE * 0.5 + 0.4)
		_cylinder(parent, 0.12, 0.3, _mat(Color(1.0, 0.6, 0.1), 2.0), _at(c.x + corner.x, 0.15, c.z + corner.z))
	# The shaft up to the pad: a dark square in the ceiling.
	var shaft := PlaneMesh.new()
	shaft.size = Vector2(LIFT_SIZE, LIFT_SIZE)
	shaft.flip_faces = true
	_part(parent, shaft, _mat(Color(0.05, 0.05, 0.06)), _at(c.x, 4.79, c.z))

# Main Mission's window: mullions every panel and, beyond, the moon's
# surface under a black sky with the planet (a painted backdrop).
func _build_window(parent: Node3D) -> void:
	var room: Rect2
	for r in SeleneLayout.rooms():
		if r.name == "main_mission":
			room = r.rect
	var z := room.position.y
	var x := room.position.x
	while x <= room.end.x + 0.01:
		_box(parent, Vector3(0.12, WINDOW_TOP - WINDOW_SILL, 0.15), _mat(WHITE), _at(x, (WINDOW_SILL + WINDOW_TOP) * 0.5, z))
		x += PANEL.x * 2.0
	var backdrop := QuadMesh.new()
	backdrop.size = Vector2(80.0, 30.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _moonscape()
	_part(parent, backdrop, m, _at(room.get_center().x, 6.0, z - 25.0))

func _moonscape() -> ImageTexture:
	var w := 512
	var h := 192
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 1999
	noise.frequency = 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	for y in range(h):
		for x in range(w):
			var horizon := 120.0 + noise.get_noise_1d(x * 0.6) * 14.0
			if y > horizon:
				var g := 0.42 + noise.get_noise_2d(x, y * 2.5) * 0.12 + (y - horizon) / h * 0.15
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

# The comm post's direction signs and a sign over every door.
func _build_signs(parent: Node3D) -> void:
	var lines := ["MAIN MISSION", "MEDICAL CENTRE", "CREW QUARTERS", "RECREATION", "TRAVEL TUBE"]
	for side in range(4):
		var turn := side * PI * 0.5
		var label := _label("\n".join(lines), 0.06)
		label.transform = Transform3D(Basis(Vector3.UP, turn), SeleneLayout.POST + Vector3(0.0, 2.15, 0.0) + Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, 0.33))
		parent.add_child(label)
	var by_name := {}
	for room in SeleneLayout.rooms():
		by_name[room.name] = room
	for door in SeleneLayout.doors():
		if door.kind == "open":
			continue
		for pair in [[door.a, door.b], [door.b, door.a]]:
			var here: Dictionary = by_name[pair[0]]
			var there: Dictionary = by_name[pair[1]]
			var c: Vector3 = door.centre
			var into: Vector2 = (here.rect as Rect2).get_center() - Vector2(c.x, c.z)
			var normal := Vector3(0.0, 0.0, signf(into.y)) if door.axis == "x" else Vector3(signf(into.x), 0.0, 0.0)
			var label := _label(there.label, 0.09)
			var top := OFFICE_DOOR_HEIGHT if door.kind == "office" else DOOR_HEIGHT
			label.transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), c + normal * (WALL_THICK * 0.5 + 0.02) + Vector3(0.0, top + 0.12, 0.0))
			parent.add_child(label)

func _label(text: String, size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = size / 32.0
	label.font_size = 32
	label.modulate = Color(0.15, 0.15, 0.18)
	label.outline_size = 0
	label.double_sided = false
	return label

# A few warm lights per room, more in the big ones.
func _build_lights() -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	add_child(lights)
	for room in SeleneLayout.rooms():
		var r: Rect2 = room.rect
		var nx := maxi(1, roundi(r.size.x / 8.0))
		var nz := maxi(1, roundi(r.size.y / 8.0))
		for i in range(nx):
			for j in range(nz):
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.95, 0.85)
				light.light_energy = 1.2
				light.omni_range = maxf(r.size.x / nx, r.size.y / nz) * 1.2 + room.height
				light.position = Vector3(r.position.x + r.size.x * (i + 0.5) / nx, room.floor + room.height - 0.3, r.position.y + r.size.y * (j + 0.5) / nz)
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

# Main Mission's operators at their desks, the crew at work on their feet,
# the walkers on their rounds; all open the doors.
func _build_crew() -> void:
	if crew_count == 0:
		return
	var crew := Node3D.new()
	crew.name = "Crew"
	add_child(crew)
	var members := []
	for seat: Transform3D in SeleneLayout.seats():
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
		# Standing at their work (the clip "Working" kneels to hammer the floor).
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

# A sliding door (or the office's sliding wall): its panels slide aside in
# DOOR_TIME when someone of PEOPLE_GROUP is within DOOR_REACH, and back once
# nobody is; it stops nobody while open.
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
