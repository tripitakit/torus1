@tool
extends MeshInstance3D

# An Earth-like planet (maps baked by tools/blender/planet_textures.py): the
# surface with a cloud layer that turns slowly over it, and an atmosphere
# rim. The clouds are drawn by the surface's own shader: a separate sphere
# 10 km up z-fought the surface from thousands of km away (the compatibility
# renderer's depth buffer cannot part them over a 2 m .. 69 000 km range).

const SURFACE_ALBEDO_PATH := "res://assets/textures/planet/color.png"
const SURFACE_ROUGHNESS_PATH := "res://assets/textures/planet/roughness.png"
const SURFACE_NORMAL_PATH := "res://assets/textures/planet/normal.png"
const CLOUDS_PATH := "res://assets/textures/clouds/clouds.png"
# Atmosphere shell above the surface (metres), and the clouds' turn
# (seconds per turn, relative to the surface).
const ATMOSPHERE_HEIGHT := 40000.0
const CLOUD_TURN := 3600.0
const SURFACE_SHADER := """
shader_type spatial;
uniform sampler2D surface_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds : source_color, filter_linear_mipmap, repeat_enable;
// Turn of the clouds as a fraction of the map's width (u is longitude).
uniform float cloud_offset = 0.0;
void fragment() {
	float cover = texture(clouds, UV + vec2(cloud_offset, 0.0)).a;
	ALBEDO = mix(texture(surface_color, UV).rgb, vec3(1.0), cover);
	ROUGHNESS = mix(texture(surface_roughness, UV).r, 1.0, cover);
	NORMAL_MAP = mix(texture(surface_normal, UV).rgb, vec3(0.5, 0.5, 1.0), cover);
}
"""
const ATMOSPHERE_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
// Toward the sun, in world space.
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);
uniform vec4 glow : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform float falloff = 4.0;
varying vec3 world_normal;
void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), falloff);
	float day = clamp(dot(world_normal, normalize(sun_direction)) + 0.25, 0.0, 1.0);
	ALBEDO = glow.rgb * rim * day * 2.0;
}
"""

@export var planet_radius: float = 1737400.0
# The scene's sun; the atmosphere glows on the side it lights.
@export var sun_path: NodePath = NodePath("../../SunLight")

@export_tool_button("Rebuild Planet")
var rebuild_action: Callable = build_planet

func _ready() -> void:
	build_planet()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_turn_clouds(delta)
	var air := get_node_or_null("Atmosphere") as MeshInstance3D
	var sun := get_node_or_null(sun_path) as Node3D if is_inside_tree() and not sun_path.is_empty() else null
	if air != null and sun != null:
		# A DirectionalLight3D shines along its -Z: the sun lies along +Z.
		(air.material_override as ShaderMaterial).set_shader_parameter("sun_direction", sun.global_transform.basis.z.normalized())

func _turn_clouds(delta: float) -> void:
	var surface := material_override as ShaderMaterial
	if surface == null:
		return
	var offset: float = surface.get_shader_parameter("cloud_offset")
	surface.set_shader_parameter("cloud_offset", fposmod(offset + delta / CLOUD_TURN, 1.0))

func _build_surface_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SURFACE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("surface_color", load(SURFACE_ALBEDO_PATH))
	mat.set_shader_parameter("surface_roughness", load(SURFACE_ROUGHNESS_PATH))
	mat.set_shader_parameter("surface_normal", load(SURFACE_NORMAL_PATH))
	mat.set_shader_parameter("clouds", load(CLOUDS_PATH))
	mat.set_shader_parameter("cloud_offset", 0.0)
	return mat

func _sphere(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	return sphere

# Replaces the child `layer_name` with a fresh sphere of `radius`.
func _layer(layer_name: String, radius: float, material: Material) -> MeshInstance3D:
	var old := get_node_or_null(layer_name)
	if old != null:
		remove_child(old)
		old.free()
	var layer := MeshInstance3D.new()
	layer.name = layer_name
	layer.mesh = _sphere(radius)
	layer.material_override = material
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(layer)
	return layer

func build_planet() -> void:
	mesh = _sphere(planet_radius)
	material_override = _build_surface_material()
	var shader := Shader.new()
	shader.code = ATMOSPHERE_SHADER
	var air := ShaderMaterial.new()
	air.shader = shader
	air.set_shader_parameter("sun_direction", Vector3(0.0, 0.0, 1.0))
	_layer("Atmosphere", planet_radius + ATMOSPHERE_HEIGHT, air)
