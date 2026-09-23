@tool
extends MeshInstance3D

const SURFACE_ALBEDO_PATH := "res://assets/textures/planet/albedo.png"
const SURFACE_ROUGHNESS_PATH := "res://assets/textures/planet/roughness.png"
const SURFACE_NORMAL_PATH := "res://assets/textures/planet/normal.png"

@export var planet_radius: float = 1737400.0

@export_tool_button("Rebuild Planet")
var rebuild_action: Callable = build_planet

func _ready() -> void:
	build_planet()

func _build_surface_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(SURFACE_ALBEDO_PATH)
	mat.roughness_texture = load(SURFACE_ROUGHNESS_PATH)
	mat.normal_enabled = true
	mat.normal_texture = load(SURFACE_NORMAL_PATH)
	return mat

func build_planet() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius
	sphere.height = planet_radius * 2.0
	mesh = sphere
	material_override = _build_surface_material()
