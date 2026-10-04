extends RefCounted

# The rover's looks: a Moon Buggy (Space: 1999), low poly. A low white
# platform with a red-orange stripe each side and a raised nose, four big
# ribbed wheels under white fenders, two seats and a low console with
# status lights under a glass dome, two round lamps in the nose, a cargo
# box and a whip antenna behind. The origin is where the wheels touch the
# ground, -Z the nose; from the driver's eye (moon_rover.gd EYE) the front
# wheels and fenders show at the view's lower corners.

const WHEEL_RADIUS := 0.4
const WHEEL_WIDTH := 0.3
const WHITE := Color(0.9, 0.9, 0.88)
const STRIPE := Color(0.88, 0.3, 0.08)
const GREY := Color(0.45, 0.47, 0.5)
const TYRE := Color(0.07, 0.07, 0.07)
const SEAT := Color(0.2, 0.22, 0.25)

static func build(rover: Node3D) -> void:
	var white := _material(WHITE, 0.55, 0.1)
	var stripe := _material(STRIPE, 0.5, 0.1)
	var grey := _material(GREY, 0.5, 0.5)
	var tyre := _material(TYRE, 0.9, 0.0)
	var seat := _material(SEAT, 0.8, 0.0)
	# Platform, raised nose, stripes.
	_box(rover, "Platform", Vector3(1.5, 0.22, 2.9), Vector3(0.0, 0.66, 0.05), white)
	_box(rover, "Nose", Vector3(1.4, 0.3, 0.35), Vector3(0.0, 0.82, -1.5), white)
	_box(rover, "StripeL", Vector3(0.03, 0.08, 2.9), Vector3(-0.765, 0.68, 0.05), stripe)
	_box(rover, "StripeR", Vector3(0.03, 0.08, 2.9), Vector3(0.765, 0.68, 0.05), stripe)
	# Round lamps in the nose (the HeadlightL/R lights sit just ahead).
	for lamp in [["LampL", -0.5], ["LampR", 0.5]]:
		var disc := MeshInstance3D.new()
		disc.name = lamp[0]
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.13
		cylinder.bottom_radius = 0.13
		cylinder.height = 0.06
		disc.mesh = cylinder
		disc.material_override = _glow(Color(1.0, 0.95, 0.8))
		disc.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		disc.position = Vector3(lamp[1], 0.84, -1.66)
		rover.add_child(disc)
	# Seats and the console with its status lights.
	_box(rover, "SeatL", Vector3(0.5, 0.12, 0.5), Vector3(-0.35, 0.83, 0.1), seat)
	_box(rover, "SeatR", Vector3(0.5, 0.12, 0.5), Vector3(0.35, 0.83, 0.1), seat)
	_box(rover, "BackL", Vector3(0.5, 0.55, 0.1), Vector3(-0.35, 1.1, 0.38), seat)
	_box(rover, "BackR", Vector3(0.5, 0.55, 0.1), Vector3(0.35, 1.1, 0.38), seat)
	_box(rover, "Console", Vector3(0.7, 0.22, 0.25), Vector3(0.0, 0.88, -0.75), grey)
	for k in range(4):
		var colour := Color(0.3, 1.0, 0.4) if k % 2 == 0 else Color(1.0, 0.7, 0.2)
		_box(rover, "Status%d" % k, Vector3(0.06, 0.04, 0.02), Vector3(-0.21 + k * 0.14, 0.95, -0.62), _glow(colour))
	# The glass dome over the seats, its thin ring down on the platform
	# (higher up it read as a bar across the view).
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 1.05
	sphere.is_hemisphere = true
	sphere.radial_segments = 24
	sphere.rings = 8
	dome.mesh = sphere
	dome.material_override = _glass()
	dome.position = Vector3(0.0, 0.8, -0.2)
	rover.add_child(dome)
	var ring := MeshInstance3D.new()
	ring.name = "DomeRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.03
	torus.outer_radius = 1.07
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = white
	ring.position = Vector3(0.0, 0.8, -0.2)
	rover.add_child(ring)
	# Cargo box and whip antenna behind.
	_box(rover, "Cargo", Vector3(1.1, 0.45, 0.45), Vector3(0.0, 1.0, 1.25), white)
	_box(rover, "CargoStripe", Vector3(1.12, 0.06, 0.47), Vector3(0.0, 1.05, 1.25), stripe)
	_box(rover, "Antenna", Vector3(0.03, 1.1, 0.03), Vector3(0.45, 1.75, 1.35), grey)
	# Wheels: a pivot (steers) holding a Spin node (rolls) holding the tyre,
	# its ribs and a hub; a fender over each.
	for wheel in [["FL", -1.0, -1.0], ["FR", 1.0, -1.0], ["RL", -1.0, 1.0], ["RR", 1.0, 1.0]]:
		var pivot := Node3D.new()
		pivot.name = "Wheel" + wheel[0]
		pivot.position = Vector3(wheel[1] * 0.9, WHEEL_RADIUS, wheel[2] * 1.25)
		rover.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var tyre_mesh := MeshInstance3D.new()
		tyre_mesh.name = "Tyre"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = WHEEL_RADIUS - 0.04
		cylinder.bottom_radius = WHEEL_RADIUS - 0.04
		cylinder.height = WHEEL_WIDTH
		cylinder.radial_segments = 16
		tyre_mesh.mesh = cylinder
		tyre_mesh.material_override = tyre
		tyre_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		spin.add_child(tyre_mesh)
		for k in range(8):
			var rib := MeshInstance3D.new()
			rib.name = "Rib%d" % k
			var rib_box := BoxMesh.new()
			rib_box.size = Vector3(WHEEL_WIDTH, 0.06, 0.12)
			rib.mesh = rib_box
			rib.material_override = tyre
			var angle := TAU * k / 8.0
			rib.rotation = Vector3(angle, 0.0, 0.0)
			rib.position = Vector3(0.0, cos(angle), -sin(angle)) * (WHEEL_RADIUS - 0.03)
			spin.add_child(rib)
		_box(spin, "Hub", Vector3(WHEEL_WIDTH + 0.02, 0.22, 0.22), Vector3.ZERO, grey)
		_box(rover, "Fender" + wheel[0], Vector3(0.38, 0.06, 0.85), Vector3(wheel[1] * 0.9, 0.9, wheel[2] * 1.25), white)

static func _box(parent: Node3D, part: String, size: Vector3, at: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = part
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)

static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

static func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

# Faint blue glass, seen from inside too.
static func _glass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.6, 0.85, 1.0, 0.1)
	material.roughness = 0.05
	material.metallic_specular = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material
