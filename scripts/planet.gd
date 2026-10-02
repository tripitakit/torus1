@tool
extends MeshInstance3D

# The planet, with NASA's Earth maps (tools/earth_maps.py): the surface with
# a cloud layer that turns slowly over it, city lights on the night side, and
# an atmosphere rim. The clouds are drawn by the surface's own shader: a separate sphere
# 10 km up z-fought the surface from thousands of km away (the compatibility
# renderer's depth buffer cannot part them over a 2 m .. 69 000 km range).

const SURFACE_ALBEDO_PATH := "res://assets/textures/planet/color.jpg"
const CITY_LIGHTS_PATH := "res://assets/textures/planet/lights.jpg"
const SURFACE_ROUGHNESS_PATH := "res://assets/textures/planet/roughness.png"
const SURFACE_NORMAL_PATH := "res://assets/textures/planet/normal.png"
const CLOUDS_PATH := "res://assets/textures/clouds/clouds.jpg"
# The maps turn round the axis by this share of a turn: 15 E (Europe and
# Africa) faces +Z, the ring's start on the sunlit side. SphereMesh lays u
# from +Z toward +X; the maps start at 180 W.
const LONGITUDE_OFFSET := 195.0 / 360.0
# The city lights' glow at full night.
const LIGHTS_ENERGY := 1.5
# Atmosphere shell above the surface (metres), and the clouds' turn
# (seconds per turn, relative to the surface).
const ATMOSPHERE_HEIGHT := 40000.0
const SURFACE_SEGMENTS := 768
const SURFACE_RINGS := 384
const CLOUD_TURN := 3600.0
const SURFACE_SHADER := """
shader_type spatial;
uniform sampler2D surface_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// The cloud cover (grey: 0 clear, 1 overcast) and the city lights.
uniform sampler2D clouds : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D city_lights : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
// The maps' turn round the axis, and the clouds' own turn over the surface,
// as fractions of the map's width (u is longitude).
uniform float longitude_offset = 0.0;
uniform float cloud_offset = 0.0;
// Toward the sun, in world space; the lights glow where it is below the
// horizon, fading in across the terminator (see night_share()).
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);
uniform float lights_energy = 1.5;
varying vec3 world_normal;
void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec2 uv = UV + vec2(longitude_offset, 0.0);
	float cover = texture(clouds, uv + vec2(cloud_offset, 0.0)).r;
	ALBEDO = mix(texture(surface_color, uv).rgb, vec3(1.0), cover);
	ROUGHNESS = mix(texture(surface_roughness, uv).r, 1.0, cover);
	NORMAL_MAP = mix(texture(surface_normal, uv).rgb, vec3(0.5, 0.5, 1.0), cover);
	float night = 1.0 - smoothstep(-0.1, 0.1, dot(normalize(world_normal), normalize(sun_direction)));
	EMISSION = texture(city_lights, uv).rgb * night * (1.0 - 0.8 * cover) * lights_energy;
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
	var sun := get_node_or_null(sun_path) as Node3D if is_inside_tree() and not sun_path.is_empty() else null
	if sun != null:
		# A DirectionalLight3D shines along its -Z: the sun lies along +Z.
		set_sun_direction(sun.global_transform.basis.z.normalized())

# Toward the sun (world): the atmosphere glows and the city lights go out on
# the side it lights.
func set_sun_direction(direction: Vector3) -> void:
	var surface := material_override as ShaderMaterial
	if surface != null:
		surface.set_shader_parameter("sun_direction", direction)
	var air := get_node_or_null("Atmosphere") as MeshInstance3D
	if air != null:
		(air.material_override as ShaderMaterial).set_shader_parameter("sun_direction", direction)

# The longitude (degrees, east positive) the maps show along `direction`
# (the planet's own axes).
static func longitude_at(direction: Vector3) -> float:
	var u := fposmod(atan2(direction.x, direction.z) / TAU + LONGITUDE_OFFSET, 1.0)
	return u * 360.0 - 180.0

# How dark it is where the sun is `sun_dot` (its direction against the
# ground's up) above the horizon: 0 by day, 1 by night, a blend within about
# 6 degrees of the horizon. As the surface shader lights the cities.
static func night_share(sun_dot: float) -> float:
	return 1.0 - smoothstep(-0.1, 0.1, sun_dot)

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
	mat.set_shader_parameter("city_lights", load(CITY_LIGHTS_PATH))
	mat.set_shader_parameter("longitude_offset", LONGITUDE_OFFSET)
	mat.set_shader_parameter("cloud_offset", 0.0)
	mat.set_shader_parameter("lights_energy", LIGHTS_ENERGY)
	return mat

func _sphere(radius: float, segments := 64, rings := 32) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = segments
	sphere.rings = rings
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
	# Fine faces: a crash stops the ship on the true sphere (void_cruiser.gd),
	# and 768 x 384 faces sag at most ~30 m inside it (64 x 32 sagged 4 km).
	mesh = _sphere(planet_radius, SURFACE_SEGMENTS, SURFACE_RINGS)
	material_override = _build_surface_material()
	var shader := Shader.new()
	shader.code = ATMOSPHERE_SHADER
	var air := ShaderMaterial.new()
	air.shader = shader
	air.set_shader_parameter("sun_direction", Vector3(0.0, 0.0, 1.0))
	_layer("Atmosphere", planet_radius + ATMOSPHERE_HEIGHT, air)
