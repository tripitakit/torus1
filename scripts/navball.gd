extends Control

# Attitude indicator: a sphere coloured by direction (sky above the ring's
# plane, ground below, a 30 degree grid, prograde and radial markers) seen
# by a camera in its own little world. The sphere never turns: the shader
# gets the attitude matrix (Attitude.navball_matrix) and paints each point
# with the direction it stands for. A fixed yellow wing symbol marks the
# nose.

const PANEL_SIZE := Vector2(200.0, 200.0)
const BALL_PIXELS := 180
const WING_COLOR := Color(1.0, 0.85, 0.2)
const WING_WIDTH := 3.0
const BALL_SHADER := """
shader_type spatial;
render_mode unshaded;

uniform mat3 attitude = mat3(1.0);

varying vec3 direction;

const vec3 SKY = vec3(0.25, 0.5, 0.85);
const vec3 GROUND = vec3(0.55, 0.35, 0.2);
const vec3 PROGRADE = vec3(1.0, 0.85, 0.2);
const vec3 RETROGRADE = vec3(0.5, 0.42, 0.1);
const vec3 RADIAL_OUT = vec3(0.3, 0.9, 1.0);
const vec3 RADIAL_IN = vec3(0.1, 0.4, 0.5);

void vertex() {
	// The sphere never turns: its normal is the point's place on the ball.
	direction = NORMAL;
}

// 1 within `wide` degrees of `target`, else 0.
float marker(vec3 d, vec3 target, float wide) {
	return step(cos(radians(wide)), dot(d, target));
}

void fragment() {
	// The reference direction this point shows: +x east, +y up, -z north.
	vec3 d = normalize(attitude * normalize(direction));
	float pitch = degrees(asin(clamp(d.y, -1.0, 1.0)));
	float heading = degrees(atan(d.x, -d.z));
	vec3 color = pitch >= 0.0 ? SKY : GROUND;
	float off_pitch = abs(pitch - 30.0 * round(pitch / 30.0));
	float off_heading = abs(heading - 30.0 * round(heading / 30.0)) * cos(radians(pitch));
	if (off_pitch < 0.7 || off_heading < 0.7) {
		color *= 0.6;
	}
	if (abs(pitch) < 0.8) {
		color = vec3(1.0);
	}
	color = mix(color, PROGRADE, marker(d, vec3(0.0, 0.0, -1.0), 7.0));
	color = mix(color, RETROGRADE, marker(d, vec3(0.0, 0.0, 1.0), 7.0));
	color = mix(color, RADIAL_OUT, marker(d, vec3(1.0, 0.0, 0.0), 7.0));
	color = mix(color, RADIAL_IN, marker(d, vec3(-1.0, 0.0, 0.0), 7.0));
	ALBEDO = color;
}
"""

var _material: ShaderMaterial
var _viewport: SubViewport
var _picture: TextureRect

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = Vector2i(BALL_PIXELS, BALL_PIXELS)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	ball.mesh = sphere
	var shader := Shader.new()
	shader.code = BALL_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("attitude", Basis())
	ball.material_override = _material
	_viewport.add_child(ball)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.1
	camera.position = Vector3(0.0, 0.0, 3.0)
	camera.current = true
	_viewport.add_child(camera)

	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.position = (PANEL_SIZE - Vector2(BALL_PIXELS, BALL_PIXELS)) * 0.5
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)

	# The nose: fixed wings over the ball's centre.
	var wings := Line2D.new()
	wings.name = "Wings"
	wings.width = WING_WIDTH
	wings.default_color = WING_COLOR
	var centre := PANEL_SIZE * 0.5
	for point in [Vector2(-40.0, 0.0), Vector2(-14.0, 0.0), Vector2(0.0, 10.0), Vector2(14.0, 0.0), Vector2(40.0, 0.0)]:
		wings.add_point(centre + point)
	add_child(wings)

# The viewport's picture only once it is in the tree (a ViewportTexture
# taken off-tree has no path to resolve).
func _ready() -> void:
	_picture.texture = _viewport.get_texture()

func set_attitude(matrix: Basis) -> void:
	_material.set_shader_parameter("attitude", matrix)

func attitude() -> Basis:
	return _material.get_shader_parameter("attitude")
