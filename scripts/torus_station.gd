@tool
extends Node3D

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

@export var planet_radius: float = 1737400.0
@export var orbit_altitude: float = 5212200.0
@export var num_sections: int = 2000
@export var section_radius: float = 2000.0
@export var section_length: float = 20000.0
@export var target_gravity_g: float = 0.7
@export var planet_node: NodePath = NodePath("")

@export_tool_button("Rebuild Station")
var rebuild_action: Callable = build_station

func _ready() -> void:
	build_station()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_rotate_sections(delta)

func _rotate_sections(delta: float) -> void:
	var target_gravity := TorusGeometry.GRAVITY_1G * target_gravity_g
	var omega := TorusGeometry.compute_section_angular_velocity(section_radius, target_gravity)
	for child in get_children():
		if child.name.begins_with("Section"):
			child.rotate_object_local(Vector3.UP, omega * delta)

func _effective_planet_radius() -> float:
	if planet_node.is_empty():
		return planet_radius
	var planet := get_node_or_null(planet_node)
	if planet == null or not ("planet_radius" in planet):
		return planet_radius
	return planet.planet_radius

const HULL_ALBEDO_PATH := "res://assets/textures/station/albedo.png"
const HULL_ROUGHNESS_PATH := "res://assets/textures/station/roughness.png"
const HULL_NORMAL_PATH := "res://assets/textures/station/normal.png"
const HULL_TILE_SIZE := 10.0
const STRIPE_COLOR := Color(0.95, 0.65, 0.05)

func _build_hull_material(circumference: float, length: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(HULL_ALBEDO_PATH)
	mat.roughness_texture = load(HULL_ROUGHNESS_PATH)
	mat.normal_enabled = true
	mat.normal_texture = load(HULL_NORMAL_PATH)
	mat.uv1_scale = Vector3(circumference / HULL_TILE_SIZE, length / HULL_TILE_SIZE, 1.0)
	return mat

func _build_stripe_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STRIPE_COLOR
	mat.emission_enabled = true
	mat.emission = STRIPE_COLOR
	mat.emission_energy_multiplier = 0.3
	return mat

func build_station() -> void:
	for child in get_children():
		if child.name.begins_with("Section") or child.name.begins_with("Bridge"):
			remove_child(child)
			child.queue_free()

	var effective_planet_radius := _effective_planet_radius()
	var hull_material := _build_hull_material(TAU * section_radius, section_length)
	var stripe_material := _build_stripe_material()

	var section_transforms := TorusGeometry.compute_section_transforms(effective_planet_radius, orbit_altitude, num_sections)
	for i in range(section_transforms.size()):
		var section := MeshInstance3D.new()
		section.name = "Section%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = section_radius
		cyl.bottom_radius = section_radius
		cyl.height = section_length
		section.mesh = cyl
		section.material_override = hull_material
		section.transform = section_transforms[i]
		add_child(section)

		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe"
		var stripe_box := BoxMesh.new()
		stripe_box.size = Vector3(2.0, section_length, 2.0)
		stripe.mesh = stripe_box
		stripe.material_override = stripe_material
		stripe.transform.origin = Vector3(0.0, 0.0, section_radius)
		section.add_child(stripe)

	var bridge_length := TorusGeometry.compute_bridge_length(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(effective_planet_radius, orbit_altitude, num_sections, section_length)
	for i in range(bridge_transforms.size()):
		var bridge := MeshInstance3D.new()
		bridge.name = "Bridge%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = section_radius * 0.3
		cyl.bottom_radius = section_radius * 0.3
		cyl.height = max(bridge_length, 0.01)
		bridge.mesh = cyl
		bridge.material_override = hull_material
		bridge.transform = bridge_transforms[i]
		add_child(bridge)
