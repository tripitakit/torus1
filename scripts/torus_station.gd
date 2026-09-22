@tool
extends Node3D

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

@export var planet_radius: float = 500.0
@export var orbit_altitude: float = 1500.0
@export var num_sections: int = 100
@export var section_radius: float = 30.0
@export var section_length: float = 80.0

@export_tool_button("Rebuild Station")
var rebuild_action: Callable = build_station

func _ready() -> void:
	build_station()

func build_station() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var section_transforms := TorusGeometry.compute_section_transforms(planet_radius, orbit_altitude, num_sections)
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

	var bridge_length := TorusGeometry.compute_bridge_length(planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(planet_radius, orbit_altitude, num_sections, section_length)
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
