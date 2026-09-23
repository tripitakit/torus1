@tool
extends MeshInstance3D

@export var planet_radius: float = 1737400.0

@export_tool_button("Rebuild Planet")
var rebuild_action: Callable = build_planet

func _ready() -> void:
	build_planet()

func build_planet() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius
	sphere.height = planet_radius * 2.0
	mesh = sphere
