@tool
extends Node3D

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

@export var planet_radius: float = 500.0
@export var orbit_altitude: float = 1500.0
@export var num_sections: int = 100
@export var section_radius: float = 30.0
@export var section_length: float = 102.83185307179585
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
	var omega := TorusGeometry.compute_section_angular_velocity(section_radius)
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

func build_station() -> void:
	for child in get_children():
		if child.name.begins_with("Section") or child.name.begins_with("Bridge"):
			remove_child(child)
			child.queue_free()

	var effective_planet_radius := _effective_planet_radius()
	var section_transforms := TorusGeometry.compute_section_transforms(effective_planet_radius, orbit_altitude, num_sections)
	for i in range(section_transforms.size()):
		var section := MeshInstance3D.new()
		section.name = "Section%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = section_radius
		cyl.bottom_radius = section_radius
		cyl.height = section_length
		section.mesh = cyl
		section.transform = section_transforms[i]
		add_child(section)

		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe"
		var stripe_box := BoxMesh.new()
		stripe_box.size = Vector3(2.0, section_length, 2.0)
		stripe.mesh = stripe_box
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
		bridge.transform = bridge_transforms[i]
		add_child(bridge)
