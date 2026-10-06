extends RefCounted

# The far-side outposts on the moon's surface (MoonOrbit.OUTPOSTS), as the
# moon's static bodies under "Sites":
#  telescope  the UltraTelescope, Mare Moscoviense: a 60 m dish on a lattice
#             tower turning slowly, an optical dome with its slit open, the
#             control building with the airlock hatch, a pad (number 7)
#  area2      Nuclear Waste Disposal Area 2, Tsiolkovskiy (after Space:
#             1999's "Breakaway"): a cross-shaped field of 35 silo caps, the
#             Eagles' pad with conveyor and lift in its middle, a stack of
#             lead canisters, the laser fence all round with a gate; the
#             round monitoring depot outside it with its hatch, a pad
#             (number 8)
# Each site's frame: origin on the flat ground at its centre, y up, x east,
# z south. Pieces sit on the sphere (MoonBase.ground).

const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonBase = preload("res://scripts/moon_base.gd")

const SITES := MoonOrbit.OUTPOSTS
const PAD_RADIUS := 15.0
const PAD_HEIGHT := 2.0
# Area 2: the cross's arms (width, reach past the middle square), the fence
# that far outside it, its posts at most POST_STEP apart, the gate's width.
const ARM_WIDTH := 40.0
const ARM_REACH := 84.0
const FENCE_OUT := 3.0
const POST_STEP := 10.0
const GATE := 12.0
const GATE_AT := 52.0
const FENCE_HEIGHT := 3.0
const SILO_RADIUS := 3.0
# The buildings: centre, turn (radians about up), and how far the hatch is
# from the centre (it faces the building's +Z).
const BUILDINGS := {
	"telescope": {"at": Vector2(0.0, 0.0), "turn": 0.0, "hatch": 6.0},
	"area2": {"at": Vector2(60.0, -60.0), "turn": PI * 0.75, "hatch": 11.0},
}
const PADS := {"telescope": Vector2(85.0, 85.0), "area2": Vector2(95.0, -95.0)}
# Floodlight masts lighting each site through the lunar night.
const FLOODLIGHTS := {
	"telescope": [Vector2(-30.0, 25.0), Vector2(40.0, -40.0), Vector2(60.0, 60.0)],
	"area2": [Vector2(-60.0, -60.0), Vector2(60.0, 60.0), Vector2(-60.0, 60.0), Vector2(85.0, -40.0)],
}
const FLOOD_HEIGHT := 16.0
const FLOOD_RANGE := 150.0
const DISH_AT := Vector2(0.0, -70.0)
const DOME_AT := Vector2(-50.0, -30.0)
# One turn of the dish every DISH_PERIOD seconds.
const DISH_PERIOD := 240.0

const WHITE := Color(0.92, 0.93, 0.95)
const GREY := Color(0.6, 0.62, 0.65)
const DARK := Color(0.15, 0.16, 0.18)
const ORANGE := Color(0.95, 0.45, 0.1)
const HAZARD := Color(0.95, 0.75, 0.1)
const LASER := Color(1.0, 0.12, 0.08)
const FIELD := Color(0.62, 0.62, 0.6)
const LEAD := Color(0.3, 0.31, 0.33)

static func direction(name: String) -> Vector3:
	return MoonOrbit.direction_of(SITES[name].latitude, SITES[name].longitude)

static func ground_height(name: String) -> float:
	return MoonTerrain.site_height(name)

static func node_name(name: String) -> String:
	return "Telescope" if name == "telescope" else "Area2"

# The site's frame in the moon's: on its flat ground, y up, x east.
static func site_local_transform(name: String) -> Transform3D:
	var up := direction(name)
	var lon := deg_to_rad(SITES[name].longitude)
	var east := Vector3(sin(lon), 0.0, cos(lon))
	return Transform3D(Basis(east, up, east.cross(up)), up * (MoonOrbit.RADIUS + ground_height(name)))

# A point of the site's ground (x, z), on the sphere.
static func ground_point(at: Vector2, height: float) -> Vector3:
	return MoonBase.ground(at.x, at.y, MoonOrbit.RADIUS + height).origin

static func _ground(name: String, at: Vector2) -> Transform3D:
	return MoonBase.ground(at.x, at.y, MoonOrbit.RADIUS + ground_height(name))

# The building's frame in the site's: on the ground, turned.
static func building_transform(name: String) -> Transform3D:
	var b: Dictionary = BUILDINGS[name]
	var at := _ground(name, b.at)
	return Transform3D(at.basis * Basis(Vector3.UP, b.turn), at.origin)

# The hatch in the site's frame: its middle on the ground, +Z outward.
static func hatch_local(name: String) -> Transform3D:
	return building_transform(name) * Transform3D(Basis(), Vector3(0.0, 0.0, BUILDINGS[name].hatch))

# The pad's top centre in the site's frame, y up.
static func pad_local(name: String) -> Transform3D:
	var at := _ground(name, PADS[name])
	return Transform3D(at.basis, at.origin + at.basis.y * PAD_HEIGHT)

# --- Area 2's field ------------------------------------------------------

# The silo caps (x, z): 12 west, 12 south, 7 north, 4 east, in pairs down
# each arm.
static func silos() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in range(6):
		var d := 32.0 + k * 12.0
		for side in [-10.0, 10.0]:
			out.append(Vector2(-d, side))
			out.append(Vector2(side, d))
	for k in range(3):
		var d := 32.0 + k * 12.0
		for side in [-10.0, 10.0]:
			out.append(Vector2(side, -d))
	out.append(Vector2(0.0, -68.0))
	for side in [-10.0, 10.0]:
		out.append(Vector2(32.0, side))
		out.append(Vector2(44.0, side))
	return out

static func cross_area() -> float:
	return ARM_WIDTH * ARM_WIDTH + 4.0 * ARM_WIDTH * ARM_REACH

# The fence's corners round the cross, FENCE_OUT outside it, in order.
static func fence_outline() -> Array[Vector2]:
	var w := ARM_WIDTH * 0.5 + FENCE_OUT
	var t := ARM_WIDTH * 0.5 + ARM_REACH + FENCE_OUT
	return [Vector2(-w, -t), Vector2(w, -t), Vector2(w, -w), Vector2(t, -w), Vector2(t, w), Vector2(w, w),
		Vector2(w, t), Vector2(-w, t), Vector2(-w, w), Vector2(-t, w), Vector2(-t, -w), Vector2(-w, -w)]

# The posts all round, at most POST_STEP apart, leaving the gate (GATE wide,
# on the east arm's north side at x = GATE_AT, by the depot).
static func fence_posts() -> Array[Vector2]:
	var corners := fence_outline()
	var posts: Array[Vector2] = []
	for k in range(corners.size()):
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % corners.size()]
		var gated := is_equal_approx(a.y, b.y) and a.y < 0.0 and minf(a.x, b.x) < GATE_AT and maxf(a.x, b.x) > GATE_AT
		if not gated:
			var count := ceili(a.distance_to(b) / POST_STEP)
			for i in range(count):
				posts.append(a.lerp(b, float(i) / count))
			continue
		# Up to the gate and on from it.
		var dir := signf(b.x - a.x)
		var near := Vector2(GATE_AT - dir * GATE * 0.5, a.y)
		var far := Vector2(GATE_AT + dir * GATE * 0.5, a.y)
		for leg in [[a, near], [far, b]]:
			var count := ceili((leg[0] as Vector2).distance_to(leg[1]) / POST_STEP)
			for i in range(count + (1 if leg[1] == near else 0)):
				posts.append((leg[0] as Vector2).lerp(leg[1], float(i) / count))
	return posts

# --- building -----------------------------------------------------------

static func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func _mesh(parent: Node3D, mesh: Mesh, material: Material, where: Transform3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = where
	parent.add_child(node)
	return node

static func _box(parent: Node3D, size: Vector3, material: Material, where: Transform3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, material, where)

static func _cylinder(parent: Node3D, radius: float, height: float, material: Material, where: Transform3D, top := -1.0, sides := 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	return _mesh(parent, mesh, material, where)

static func _solid(body: StaticBody3D, shape: Shape3D, where: Transform3D) -> void:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.transform = where
	body.add_child(node)

static func _box_shape(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box

static func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return shape

# A piece standing on the ground at `at`, `lift` above it, turned.
static func _on(name: String, at: Vector2, lift: float, turn := 0.0) -> Transform3D:
	var g := _ground(name, at)
	return Transform3D(g.basis * Basis(Vector3.UP, turn), g.origin + g.basis.y * lift)

# Builds the site `name` into `body` (its frame the site's).
static func build(body: StaticBody3D, name: String) -> void:
	var m := {"white": _mat(WHITE), "grey": _mat(GREY), "dark": _mat(DARK), "orange": _mat(ORANGE), "hazard": _mat(HAZARD),
		"laser": _mat(LASER, 3.0), "field": _mat(FIELD), "lead": _mat(LEAD), "lamp": _mat(Color(1.0, 0.7, 0.3), 2.5), "glass": _mat(Color(0.1, 0.15, 0.22))}
	_pad(body, name, m)
	for at: Vector2 in FLOODLIGHTS[name]:
		_floodlight(body, name, at, m)
	if name == "telescope":
		_telescope(body, m)
		_building_box(body, name, m)
	else:
		_area2(body, m)
		_depot(body, name, m)

static func _pad(body: StaticBody3D, name: String, m: Dictionary) -> void:
	var at := _on(name, PADS[name], PAD_HEIGHT * 0.5)
	_cylinder(body, PAD_RADIUS, PAD_HEIGHT, m.grey, at, -1.0, 32)
	_cylinder(body, PAD_RADIUS + 0.05, 0.1, m.orange, at * Transform3D(Basis(), Vector3(0.0, PAD_HEIGHT * 0.5 - 0.3, 0.0)), -1.0, 32)
	_cylinder(body, PAD_RADIUS * 0.6, 0.02, m.dark, at * Transform3D(Basis(), Vector3(0.0, PAD_HEIGHT * 0.5 + 0.01, 0.0)), PAD_RADIUS * 0.55, 32)
	_solid(body, _cylinder_shape(PAD_RADIUS, PAD_HEIGHT), at)
	for k in range(4):
		var a := k * PI * 0.5 + PI * 0.25
		var lamp := Vector3(cos(a), 0.0, sin(a)) * (PAD_RADIUS - 0.8)
		_cylinder(body, 0.3, 0.2, m.lamp, at * Transform3D(Basis(), lamp + Vector3(0.0, PAD_HEIGHT * 0.5 + 0.1, 0.0)))

# A mast with a lamp head and a light shining over the site.
static func _floodlight(body: StaticBody3D, name: String, at: Vector2, m: Dictionary) -> void:
	var foot := _on(name, at, 0.0)
	_cylinder(body, 0.25, FLOOD_HEIGHT, m.grey, foot * Transform3D(Basis(), Vector3(0.0, FLOOD_HEIGHT * 0.5, 0.0)), 0.15, 8)
	_box(body, Vector3(2.4, 0.8, 0.8), m.dark, foot * Transform3D(Basis(), Vector3(0.0, FLOOD_HEIGHT, 0.0)))
	_box(body, Vector3(2.2, 0.6, 0.05), _mat(Color(1.0, 0.95, 0.85), 4.0), foot * Transform3D(Basis(), Vector3(0.0, FLOOD_HEIGHT, 0.42)))
	_solid(body, _cylinder_shape(0.3, FLOOD_HEIGHT), foot * Transform3D(Basis(), Vector3(0.0, FLOOD_HEIGHT * 0.5, 0.0)))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 2.0
	light.omni_range = FLOOD_RANGE
	light.omni_attenuation = 0.8
	light.transform = foot * Transform3D(Basis(), Vector3(0.0, FLOOD_HEIGHT + 1.0, 0.0))
	body.add_child(light)

# The control building (14 x 12 m, 6 high): the hatch on +Z under its
# hazard bands, the window band toward the dish (-Z), a mast on the roof.
static func _building_box(body: StaticBody3D, name: String, m: Dictionary) -> void:
	var frame := building_transform(name)
	var size := Vector3(14.0, 6.0, 12.0)
	_box(body, size, m.white, frame * Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)))
	_solid(body, _box_shape(size), frame * Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0)))
	_box(body, Vector3(size.x + 0.1, 0.4, size.z + 0.1), m.orange, frame * Transform3D(Basis(), Vector3(0.0, size.y - 0.6, 0.0)))
	_box(body, Vector3(size.x - 2.0, 1.6, 0.1), m.glass, frame * Transform3D(Basis(), Vector3(0.0, 3.2, -size.z * 0.5 - 0.02)))
	_hatch(body, frame * Transform3D(Basis(), Vector3(0.0, 0.0, size.z * 0.5)), m)
	_cylinder(body, 0.15, 6.0, m.grey, frame * Transform3D(Basis(), Vector3(4.0, size.y + 3.0, 2.0)))
	_cylinder(body, 0.4, 0.3, m.lamp, frame * Transform3D(Basis(), Vector3(4.0, size.y + 6.1, 2.0)))

# A hatch on a wall (its frame on the ground, +Z out): a steel door with
# hazard bands in a dark frame, a red light.
static func _hatch(body: StaticBody3D, at: Transform3D, m: Dictionary) -> void:
	_box(body, Vector3(2.6, 3.0, 0.3), m.dark, at * Transform3D(Basis(), Vector3(0.0, 1.5, 0.05)))
	_box(body, Vector3(1.8, 2.4, 0.32), m.grey, at * Transform3D(Basis(), Vector3(0.0, 1.2, 0.07)))
	for k in range(3):
		_box(body, Vector3(1.8, 0.14, 0.34), m.hazard, at * Transform3D(Basis(), Vector3(0.0, 0.35 + k * 0.28, 0.08)))
	_box(body, Vector3(0.2, 0.2, 0.1), _mat(Color(1.0, 0.2, 0.1), 3.0), at * Transform3D(Basis(), Vector3(0.0, 2.75, 0.25)))

# The dish on its lattice tower (turning: "DishTurn") and the optical dome.
static func _telescope(body: StaticBody3D, m: Dictionary) -> void:
	var name := "telescope"
	var base := _on(name, DISH_AT, 0.0)
	# Tower: four legs and bracing up to the turntable.
	for corner in [Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)]:
		var leg := Transform3D(base.basis * Basis(Vector3(corner.y, 0.0, -corner.x).normalized(), 0.08), base.origin + base.basis * Vector3(corner.x, 13.0, corner.y))
		_box(body, Vector3(0.6, 26.0, 0.6), m.grey, leg)
	for k in range(4):
		_box(body, Vector3(8.6, 0.3, 0.3), m.grey, base * Transform3D(Basis(Vector3.UP, k * PI * 0.5), Vector3(0.0, 6.0 + k * 5.0, 4.0 - k * 0.4)))
	_solid(body, _box_shape(Vector3(9.0, 26.0, 9.0)), base * Transform3D(Basis(), Vector3(0.0, 13.0, 0.0)))
	_cylinder(body, 6.0, 1.0, m.white, base * Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)))
	var turn := Node3D.new()
	turn.name = "DishTurn"
	turn.transform = base * Transform3D(Basis(), Vector3(0.0, 26.0, 0.0))
	body.add_child(turn)
	_cylinder(turn, 4.0, 1.5, m.white, Transform3D(Basis(), Vector3(0.0, 0.75, 0.0)))
	_box(turn, Vector3(2.0, 6.0, 2.0), m.grey, Transform3D(Basis(), Vector3(0.0, 4.0, 0.0)))
	# The bowl: a shallow cap tipped 40 degrees up, rim 60 m across.
	var bowl := SphereMesh.new()
	bowl.radius = 30.0
	bowl.height = 16.0
	bowl.is_hemisphere = true
	bowl.radial_segments = 32
	bowl.rings = 8
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-130.0))
	var bowl_material := _mat(WHITE)
	bowl_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(turn, bowl, bowl_material, Transform3D(tilt, Vector3(0.0, 9.0, 0.0)))
	var mouth := tilt * Vector3(0.0, -1.0, 0.0)
	for k in range(3):
		var a := k * TAU / 3.0
		var rim := tilt * Vector3(cos(a) * 26.0, 0.0, sin(a) * 26.0) + Vector3(0.0, 9.0, 0.0)
		var feed := Vector3(0.0, 9.0, 0.0) + mouth * 20.0
		var strut := feed - rim
		_box(turn, Vector3(0.3, strut.length(), 0.3), m.grey, Transform3D(Basis(Quaternion(Vector3.UP, strut.normalized())), rim + strut * 0.5))
	_cylinder(turn, 1.2, 3.0, m.orange, Transform3D(Basis(Quaternion(Vector3.UP, mouth)), Vector3(0.0, 9.0, 0.0) + mouth * 20.0))
	# The dome: a drum and a hemisphere with the slit open on a tilted tube.
	var dome := _on(name, DOME_AT, 0.0)
	_cylinder(body, 10.0, 4.0, m.white, dome * Transform3D(Basis(), Vector3(0.0, 2.0, 0.0)), -1.0, 32)
	_solid(body, _cylinder_shape(10.0, 14.0), dome * Transform3D(Basis(), Vector3(0.0, 7.0, 0.0)))
	var cap := SphereMesh.new()
	cap.radius = 10.0
	cap.height = 10.0
	cap.is_hemisphere = true
	cap.radial_segments = 32
	cap.rings = 8
	_mesh(body, cap, m.white, dome * Transform3D(Basis(), Vector3(0.0, 4.0, 0.0)))
	_box(body, Vector3(2.4, 9.0, 10.4), m.dark, dome * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 9.5, -2.5)))
	_cylinder(body, 1.0, 7.0, m.grey, dome * Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0.0, 8.0, -1.5)))
	_box(body, Vector3(20.2, 0.3, 0.3), m.orange, dome * Transform3D(Basis(), Vector3(0.0, 3.9, 0.0)))

# Area 2's field: the pale cross, the silo caps, the Eagles' pad with the
# conveyor and lift, the canisters, the laser fence.
static func _area2(body: StaticBody3D, m: Dictionary) -> void:
	var name := "area2"
	var half := ARM_WIDTH * 0.5
	var reach := half + ARM_REACH
	for strip in [Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0)]:
		var centre := Vector2(strip.x, strip.z) * (half + ARM_REACH * 0.5)
		var size := Vector3(ARM_WIDTH, 0.1, ARM_WIDTH) if strip == Vector3.ZERO else (Vector3(ARM_REACH, 0.1, ARM_WIDTH) if strip.x != 0.0 else Vector3(ARM_WIDTH, 0.1, ARM_REACH))
		_box(body, size, m.field, _on(name, centre, 0.04))
	for at: Vector2 in silos():
		var cap := _on(name, at, 0.3)
		_cylinder(body, SILO_RADIUS, 0.6, m.grey, cap)
		_cylinder(body, SILO_RADIUS + 0.05, 0.2, m.hazard, cap * Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)))
		_cylinder(body, 0.5, 0.02, m.dark, cap * Transform3D(Basis(), Vector3(0.0, 0.31, 0.0)))
		for k in range(3):
			# The trefoil: three dark blades round the middle.
			_box(body, Vector3(0.9, 0.02, 1.4), m.dark, cap * Transform3D(Basis(Vector3.UP, k * TAU / 3.0), Vector3(0.0, 0.31, 0.0)) * Transform3D(Basis(), Vector3(0.0, 0.0, 1.4)))
		_solid(body, _cylinder_shape(SILO_RADIUS, 0.6), cap)
	# The Eagles' pad in the middle, the conveyor and the lift down to the pits.
	var pad := _on(name, Vector2.ZERO, 0.25)
	_cylinder(body, 15.0, 0.5, m.grey, pad, -1.0, 32)
	_cylinder(body, 15.05, 0.1, m.orange, pad * Transform3D(Basis(), Vector3(0.0, 0.2, 0.0)), -1.0, 32)
	_solid(body, _cylinder_shape(15.0, 0.5), pad)
	_box(body, Vector3(11.0, 0.8, 1.6), m.dark, _on(name, Vector2(21.0, 0.0), 0.8))
	for k in range(10):
		_cylinder(body, 0.15, 1.6, m.grey, _on(name, Vector2(16.0 + k, 0.0), 1.25) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	_solid(body, _box_shape(Vector3(11.0, 1.4, 1.6)), _on(name, Vector2(21.0, 0.0), 0.7))
	var lift := _on(name, Vector2(28.0, 0.0), 3.0)
	_box(body, Vector3(3.0, 6.0, 3.0), m.white, lift)
	_box(body, Vector3(3.1, 0.4, 3.1), m.hazard, lift * Transform3D(Basis(), Vector3(0.0, 2.6, 0.0)))
	_solid(body, _box_shape(Vector3(3.0, 6.0, 3.0)), lift)
	# Lead canisters waiting by the pad.
	for i in range(3):
		for j in range(3):
			for level in range(2):
				_cylinder(body, 0.6, 1.4, m.lead, _on(name, Vector2(-15.0 + i * 1.3, 15.0 + j * 1.3), 0.7 + level * 1.4), -1.0, 12)
	_solid(body, _box_shape(Vector3(4.0, 2.8, 4.0)), _on(name, Vector2(-13.7, 16.3), 1.4))
	# The laser fence: posts with a red lamp, three beams between them.
	var posts := fence_posts()
	for k in range(posts.size()):
		var a: Vector2 = posts[k]
		_cylinder(body, 0.12, FENCE_HEIGHT, m.white, _on(name, a, FENCE_HEIGHT * 0.5), -1.0, 8)
		_cylinder(body, 0.18, 0.2, m.laser, _on(name, a, FENCE_HEIGHT + 0.1), -1.0, 8)
		var b: Vector2 = posts[(k + 1) % posts.size()]
		var span := a.distance_to(b)
		if span > POST_STEP + 0.01:
			continue
		var mid := (a + b) * 0.5
		var turn := atan2(-(b - a).y, (b - a).x)
		for y in [0.6, 1.4, 2.2]:
			_box(body, Vector3(span, 0.04, 0.04), m.laser, _on(name, mid, y, turn))
		_solid(body, _box_shape(Vector3(span, FENCE_HEIGHT, 0.2)), _on(name, mid, FENCE_HEIGHT * 0.5, turn))
	# The gate's two tall posts.
	for side in [-1.0, 1.0]:
		_cylinder(body, 0.25, 4.5, m.orange, _on(name, Vector2(GATE_AT + side * GATE * 0.5, -(ARM_WIDTH * 0.5 + FENCE_OUT)), 2.25), -1.0, 8)

# The round monitoring depot (22 m across, 6 high): window band toward the
# field (-Z), the hatch on the far side, a mast.
static func _depot(body: StaticBody3D, name: String, m: Dictionary) -> void:
	var frame := building_transform(name)
	_cylinder(body, 11.0, 6.0, m.white, frame * Transform3D(Basis(), Vector3(0.0, 3.0, 0.0)), -1.0, 32)
	_solid(body, _cylinder_shape(11.0, 6.0), frame * Transform3D(Basis(), Vector3(0.0, 3.0, 0.0)))
	_cylinder(body, 11.05, 0.4, m.orange, frame * Transform3D(Basis(), Vector3(0.0, 5.4, 0.0)), -1.0, 32)
	_cylinder(body, 9.0, 0.6, m.grey, frame * Transform3D(Basis(), Vector3(0.0, 6.3, 0.0)), 7.0, 32)
	_box(body, Vector3(10.0, 1.6, 0.4), m.glass, frame * Transform3D(Basis(), Vector3(0.0, 3.2, -10.85)))
	_hatch(body, frame * Transform3D(Basis(), Vector3(0.0, 0.0, 11.0)), m)
	_cylinder(body, 0.15, 8.0, m.grey, frame * Transform3D(Basis(), Vector3(-5.0, 10.0, 3.0)))
	_cylinder(body, 0.4, 0.3, m.lamp, frame * Transform3D(Basis(), Vector3(-5.0, 14.1, 3.0)))
