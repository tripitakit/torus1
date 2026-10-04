extends RefCounted

# The moon rover's looks, made of simple shapes in the Apollo rover's
# colours: a light grey frame, gold panels, black mesh wheels, a roll bar,
# an umbrella antenna. The origin is where the wheels touch the ground, -Z
# the nose. Seen only from the driver's seat: the dashboard, the bonnet,
# the front wheels and the roll bar's posts are what the camera shows.

const WHEEL_RADIUS := 0.4
const WHEEL_WIDTH := 0.25
const FRAME := Color(0.78, 0.78, 0.76)
const GOLD := Color(0.85, 0.65, 0.2)
const TYRE := Color(0.06, 0.06, 0.06)
const SCREEN := Color(0.03, 0.05, 0.06)

static func build(rover: Node3D) -> void:
	var frame := _material(FRAME, 0.6, 0.3)
	var gold := _material(GOLD, 0.35, 0.8)
	var tyre := _material(TYRE, 0.9, 0.0)
	var screen := _material(SCREEN, 0.2, 0.0)
	# Chassis, bonnet, rear deck.
	_box(rover, "Chassis", Vector3(1.6, 0.25, 3.1), Vector3(0.0, 0.65, 0.0), frame)
	_box(rover, "Bonnet", Vector3(1.5, 0.12, 0.5), Vector3(0.0, 0.84, -1.3), gold)
	_box(rover, "Deck", Vector3(1.5, 0.3, 0.7), Vector3(0.0, 0.92, 1.15), gold)
	# Dashboard with two dark screens, in front of the driver.
	_box(rover, "Dashboard", Vector3(1.1, 0.3, 0.12), Vector3(0.0, 1.0, -1.32), frame)
	_box(rover, "ScreenL", Vector3(0.35, 0.2, 0.02), Vector3(-0.25, 1.02, -1.255), screen)
	_box(rover, "ScreenR", Vector3(0.35, 0.2, 0.02), Vector3(0.25, 1.02, -1.255), screen)
	# Roll bar: two posts and a top bar over the seats.
	_box(rover, "PostL", Vector3(0.06, 0.95, 0.06), Vector3(-0.75, 1.25, -0.45), frame)
	_box(rover, "PostR", Vector3(0.06, 0.95, 0.06), Vector3(0.75, 1.25, -0.45), frame)
	_box(rover, "RollBar", Vector3(1.56, 0.06, 0.06), Vector3(0.0, 1.72, -0.45), frame)
	# Umbrella antenna behind.
	_box(rover, "Mast", Vector3(0.04, 0.9, 0.04), Vector3(0.5, 1.5, 1.3), frame)
	var dish := MeshInstance3D.new()
	dish.name = "Dish"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.45
	cone.height = 0.15
	dish.mesh = cone
	dish.material_override = gold
	dish.position = Vector3(0.5, 2.0, 1.3)
	rover.add_child(dish)
	# Wheels: a pivot (steers) holding a Spin node (rolls) holding the tyre.
	for wheel in [["WheelFL", -1.0, -1.0], ["WheelFR", 1.0, -1.0], ["WheelRL", -1.0, 1.0], ["WheelRR", 1.0, 1.0]]:
		var pivot := Node3D.new()
		pivot.name = wheel[0]
		pivot.position = Vector3(wheel[1] * 0.9, WHEEL_RADIUS, wheel[2] * 1.25)
		rover.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var tyre_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = WHEEL_RADIUS
		cylinder.bottom_radius = WHEEL_RADIUS
		cylinder.height = WHEEL_WIDTH
		cylinder.radial_segments = 16
		tyre_mesh.mesh = cylinder
		tyre_mesh.material_override = tyre
		tyre_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		spin.add_child(tyre_mesh)
		# A gold hub, so the turning shows.
		_box(spin, "Hub", Vector3(WHEEL_WIDTH + 0.02, 0.5, 0.08), Vector3.ZERO, gold)

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
