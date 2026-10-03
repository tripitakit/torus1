extends RefCounted

# Things going round a rounded rectangle, moved by the shader alone: boats on
# the lakes, people, carts and drones on the docks. A loop is a rectangle
# (x0, z0, width, height) with corners of radius `corner` (one per
# material), gone round `laps` times an hour (a whole number, so the
# shaders' TIME starting again every 3600 s never shows; below 0 the other
# way round). Two ways to place it:
# - FLAT: on a plane at height `level` (x, level, z), up +Y;
# - CYLINDER: on the inside of a cylinder of radius `level` round the Z
#   axis, x being the arc there (a lake on the section's ground).
# The GPU reads each loop from its instance basis (9 full-precision floats:
# (x0, z0, width), (height, phase, laps), (id, level, mode)); the node only
# ever moves by translation, which comes through MODEL_MATRIX[3]. pose and
# pose_from_data are the GDScript copies (tests).

enum { FLAT, CYLINDER }

const INSTANCE_FLOATS := 20

static func make_loop(mode: int, x0: float, z0: float, width: float, height: float, corner: float, speed: float, phase_share: float, level: float, id: int) -> Dictionary:
	var loop := {"mode": mode, "x0": x0, "z0": z0, "w": width, "h": height, "corner": corner, "level": level, "id": id, "laps": 1, "phase": 0.0}
	var length := loop_length(loop)
	loop.laps = maxi(1, roundi(speed * 3600.0 / length))
	loop.phase = phase_share * length
	return loop

static func loop_length(loop: Dictionary) -> float:
	var c: float = loop.corner
	return 2.0 * (loop.w - 2.0 * c) + 2.0 * (loop.h - 2.0 * c) + TAU * c

static func pose_s(loop: Dictionary, t: float) -> float:
	var length := loop_length(loop)
	return fposmod(loop.phase + length * loop.laps / 3600.0 * t, length)

static func pose_at(loop: Dictionary, t: float) -> Transform3D:
	return pose(loop, pose_s(loop, t))

# The frame `s` metres round the loop (x left, y up, z the way it goes).
static func pose(loop: Dictionary, s: float) -> Transform3D:
	var at := _unrolled(loop.x0, loop.z0, loop.w, loop.h, loop.corner, fposmod(s, loop_length(loop)))
	return _frame(loop.mode, loop.level, at[0], at[1] * (1.0 if loop.laps >= 0 else -1.0), Vector3.ZERO)

# (point, heading) in the loop's plane, starting at the bottom edge's
# beginning and going round with x first.
static func _unrolled(x0: float, z0: float, w: float, h: float, c: float, s: float) -> Array:
	var a := w - 2.0 * c
	var b := h - 2.0 * c
	var quarter := PI * 0.5 * c
	var straights := [[Vector2(x0 + c, z0), Vector2(1.0, 0.0), a], [Vector2(x0 + w, z0 + c), Vector2(0.0, 1.0), b],
		[Vector2(x0 + w - c, z0 + h), Vector2(-1.0, 0.0), a], [Vector2(x0, z0 + h - c), Vector2(0.0, -1.0), b]]
	var centres := [Vector2(x0 + w - c, z0 + c), Vector2(x0 + w - c, z0 + h - c), Vector2(x0 + c, z0 + h - c), Vector2(x0 + c, z0 + c)]
	for k in range(4):
		var straight: Array = straights[k]
		if s < straight[2]:
			return [straight[0] + straight[1] * s, straight[1]]
		s -= straight[2]
		if s < quarter or k == 3:
			var theta := -PI * 0.5 + k * PI * 0.5 + s / c
			return [centres[k] + Vector2(cos(theta), sin(theta)) * c, Vector2(-sin(theta), cos(theta))]
		s -= quarter
	return [Vector2(x0 + c, z0), Vector2(1.0, 0.0)]

static func _frame(mode: int, level: float, p: Vector2, heading: Vector2, shift: Vector3) -> Transform3D:
	var up := Vector3.UP
	var forward := Vector3(heading.x, 0.0, heading.y)
	var origin := Vector3(p.x, level, p.y)
	if mode == CYLINDER:
		var a := p.x / level
		var tangent := Vector3(-sin(a), cos(a), 0.0)
		up = Vector3(-cos(a), -sin(a), 0.0)
		forward = (tangent * heading.x + Vector3(0.0, 0.0, heading.y)).normalized()
		origin = Vector3(cos(a) * level, sin(a) * level, p.y)
	return Transform3D(Basis(up.cross(forward), up, forward), origin + shift)

# The GPU data for `loops`, one instance each; colour (paint) from `paints`
# by id when given, white otherwise; colour alpha: id fraction.
static func instance_buffer(loops: Array, paints: Array = []) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for loop: Dictionary in loops:
		var c0 := Vector3(loop.x0, loop.z0, loop.w)
		var c1 := Vector3(loop.h, loop.phase, loop.laps)
		var c2 := Vector3(loop.id, loop.level, loop.mode)
		var paint: Color = paints[posmod(hash(loop.id), paints.size())] if not paints.is_empty() else Color.WHITE
		data.append_array([c0.x, c1.x, c2.x, 0.0, c0.y, c1.y, c2.y, 0.0, c0.z, c1.z, c2.z, 0.0,
			paint.r, paint.g, paint.b, fposmod(loop.id * 0.618034, 1.0), 0.0, 0.0, 0.0, 0.0])
	return data

# The shader's pose in GDScript: instance i of `data` at `time`.
static func pose_from_data(data: PackedFloat32Array, i: int, time: float, corner: float) -> Transform3D:
	var b := i * INSTANCE_FLOATS
	var loop := {"x0": data[b], "z0": data[b + 4], "w": data[b + 8], "h": data[b + 1], "phase": data[b + 5], "laps": roundi(data[b + 9]),
		"id": roundi(data[b + 2]), "level": data[b + 6], "mode": roundi(data[b + 10]), "corner": corner}
	return pose_at(loop, time)

# The loop and pose above in GLSL (keep the two in step).
const LOOP_GLSL := """
#include "res://shaders/interior_hour.gdshaderinc"

uniform float corner = 4.0;

void loop_pose(mat4 model, float time, out vec3 pos, out vec3 left, out vec3 up, out vec3 forward) {
	vec3 c0 = model[0].xyz;
	vec3 c1 = model[1].xyz;
	vec3 c2 = model[2].xyz;
	float x0 = c0.x; float z0 = c0.y; float w = c0.z; float h = c1.x;
	float c = corner;
	float a = w - 2.0 * c;
	float b = h - 2.0 * c;
	float quarter = 1.5707963 * c;
	float len = 2.0 * a + 2.0 * b + TAU * c;
	float s = mod(c1.y + len * c1.z / 3600.0 * time, len);
	vec2 p = vec2(x0 + c, z0);
	vec2 heading = vec2(1.0, 0.0);
	vec2 starts[4] = vec2[4](vec2(x0 + c, z0), vec2(x0 + w, z0 + c), vec2(x0 + w - c, z0 + h), vec2(x0, z0 + h - c));
	vec2 ways[4] = vec2[4](vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(0.0, -1.0));
	vec2 centres[4] = vec2[4](vec2(x0 + w - c, z0 + c), vec2(x0 + w - c, z0 + h - c), vec2(x0 + c, z0 + h - c), vec2(x0 + c, z0 + c));
	float lengths[4] = float[4](a, b, a, b);
	for (int k = 0; k < 4; k++) {
		if (s < lengths[k]) {
			p = starts[k] + ways[k] * s; heading = ways[k];
			break;
		}
		s -= lengths[k];
		if (s < quarter || k == 3) {
			float theta = -1.5707963 + float(k) * 1.5707963 + s / c;
			p = centres[k] + vec2(cos(theta), sin(theta)) * c; heading = vec2(-sin(theta), cos(theta));
			break;
		}
		s -= quarter;
	}
	heading *= c1.z >= 0.0 ? 1.0 : -1.0;
	up = vec3(0.0, 1.0, 0.0);
	forward = vec3(heading.x, 0.0, heading.y);
	pos = vec3(p.x, c2.y, p.y);
	if (c2.z > 0.5) {
		float angle = p.x / c2.y;
		vec3 tangent = vec3(-sin(angle), cos(angle), 0.0);
		up = vec3(-cos(angle), -sin(angle), 0.0);
		forward = normalize(tangent * heading.x + vec3(0.0, 0.0, heading.y));
		pos = vec3(cos(angle) * c2.y, sin(angle) * c2.y, p.y);
	}
	left = cross(up, forward);
	pos += model[3].xyz;
}
"""

# Unshaded, lit from the hour like the interior's other movers. UV.x: 0 hull
# (instance paint), 1 dark glass, 2 accent glow, 3 white light, 4 amber
# beacon (blinking), 5 foam (white, half see-through look by being pale).
# `bob` lifts and drops the model a little (walking, hovering).
const LOOP_SHADER := """
shader_type spatial;
render_mode unshaded, skip_vertex_transform;
%s
uniform vec3 accent : source_color = vec3(0.3, 0.9, 1.0);
uniform float bob = 0.0;
uniform float bob_rate = 2.0;

varying float part;
varying float shade;
varying float night;
varying vec3 paint;
varying float blink;

void vertex() {
	vec3 pos; vec3 left; vec3 up; vec3 forward;
	loop_pose(MODEL_MATRIX, TIME, pos, left, up, forward);
	float lift = bob * abs(sin(TIME * bob_rate + COLOR.a * 40.0));
	vec3 world = pos + left * VERTEX.x + up * (VERTEX.y + lift) + forward * VERTEX.z;
	vec3 normal = normalize(left * NORMAL.x + up * NORMAL.y + forward * NORMAL.z);
	night = interior_night(interior_hour(world.z));
	shade = mix(1.0, 0.3, night) * (0.6 + 0.4 * max(dot(normal, up), 0.0));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = mat3(VIEW_MATRIX) * normal;
	part = UV.x;
	paint = COLOR.rgb;
	blink = step(fract(TIME * 0.8 + COLOR.a), 0.3);
}

void fragment() {
	if (part < 0.5) {
		ALBEDO = paint * shade;
	} else if (part < 1.5) {
		ALBEDO = (vec3(0.06, 0.08, 0.1) + accent * 0.08) * shade;
	} else if (part < 2.5) {
		ALBEDO = accent * mix(0.9, 1.7, night);
	} else if (part < 3.5) {
		ALBEDO = vec3(1.0, 0.95, 0.85) * mix(1.0, 1.8, night);
	} else if (part < 4.5) {
		ALBEDO = mix(vec3(0.3, 0.15, 0.0), vec3(1.0, 0.55, 0.1) * 1.5, blink);
	} else {
		ALBEDO = vec3(0.85, 0.92, 0.95) * mix(1.0, 0.45, night);
	}
}
"""

static func material(corner_radius: float, accent: Color, bob: float = 0.0, bob_rate: float = 2.0) -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = LOOP_SHADER % LOOP_GLSL
	shader_material.set_shader_parameter("corner", corner_radius)
	shader_material.set_shader_parameter("accent", accent)
	shader_material.set_shader_parameter("bob", bob)
	shader_material.set_shader_parameter("bob_rate", bob_rate)
	return shader_material

static func multimesh_instance(node_name: String, data: PackedFloat32Array, mesh: Mesh, shader_material: Material, bounds: AABB) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = data.size() / INSTANCE_FLOATS
	multimesh.buffer = data
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material_override = shader_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = bounds
	return node
