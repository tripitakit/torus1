extends Node3D

# The subspace tunnel seen from the cockpit during a portal transit: a
# long tube round the ship, streaks of blue and violet light racing past,
# a bright core far ahead, and a white flash on the way in and out. The
# tube is opaque: the world outside does not show through. A child of the
# void-cruiser, along its axis (nose -Z).

const RADIUS := 45.0
const LENGTH := 6000.0
const CORE_SIZE := 400.0
const FLASH_TIME := 0.4
const FLASH_LAYER := 90
const TUBE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// UV.x round the tube, UV.y along it: streaks stretched along, racing
	// toward the camera, a slow twist round.
	float round_way = UV.x * 48.0 + TIME * 0.4;
	float along = UV.y * 30.0 + TIME * 9.0;
	float streak = noise(vec2(round_way, along * 0.15));
	streak = pow(streak, 6.0) * 3.0;
	float glow = noise(vec2(UV.x * 6.0 - TIME * 0.2, UV.y * 4.0 + TIME * 1.5));
	vec3 violet = vec3(0.45, 0.2, 0.9);
	vec3 blue = vec3(0.2, 0.55, 1.0);
	vec3 colour = mix(violet, blue, glow) * (0.25 + 0.5 * glow) + vec3(0.8, 0.9, 1.0) * streak;
	ALBEDO = colour;
}
"""
const CORE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 7.0);
	ALBEDO = vec3(0.75, 0.85, 1.0) * pow(max(1.0 - r, 0.0), 2.0) * 2.0 * pulse;
}
"""

var running := false
var _flash_left := 0.0

func _ready() -> void:
	if get_node_or_null("Tube") == null:
		build()

func build() -> void:
	visible = false
	var tube_material := ShaderMaterial.new()
	var tube_shader := Shader.new()
	tube_shader.code = TUBE_SHADER
	tube_material.shader = tube_shader
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS
	cylinder.bottom_radius = RADIUS
	cylinder.height = LENGTH
	cylinder.radial_segments = 48
	cylinder.rings = 8
	var tube := MeshInstance3D.new()
	tube.name = "Tube"
	tube.mesh = cylinder
	tube.material_override = tube_material
	# The cylinder's axis (Y) along the ship's Z.
	tube.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tube)
	var core_material := ShaderMaterial.new()
	var core_shader := Shader.new()
	core_shader.code = CORE_SHADER
	core_material.shader = core_shader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * CORE_SIZE
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = quad
	core.material_override = core_material
	core.position = Vector3(0.0, 0.0, -LENGTH * 0.5 + 50.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var layer := CanvasLayer.new()
	layer.name = "FlashLayer"
	layer.layer = FLASH_LAYER
	add_child(layer)
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.color = Color(1.0, 1.0, 1.0, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)

func start() -> void:
	running = true
	visible = true
	_flash()

func stop() -> void:
	running = false
	visible = false
	_flash()

func _process(delta: float) -> void:
	advance(delta)

# The flash fades over FLASH_TIME.
func advance(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	(get_node("FlashLayer/Flash") as ColorRect).color.a = _flash_left / FLASH_TIME

func _flash() -> void:
	_flash_left = FLASH_TIME
	(get_node("FlashLayer/Flash") as ColorRect).color.a = 1.0
