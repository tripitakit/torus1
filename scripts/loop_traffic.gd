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
# (x0, z0, width), (height, phase, laps), (stop or -1, level, mode)); with a
# stop, phase is in seconds into the lap, else in metres. The node only
# ever moves by translation, which comes through MODEL_MATRIX[3]. pose and
# pose_from_data are the GDScript copies (tests).

enum { FLAT, CYLINDER }

const PeopleModel = preload("res://scripts/people_model.gd")
const INSTANCE_FLOATS := 20
# People: the animated model this close to the camera, the plain one beyond.
const DETAIL_TO := 80.0
# A loop with a stop: brakes into it at STOP_ACCEL, waits STOP_DWELL, pulls
# away; the lap a whole fraction of an hour.
const STOP_DWELL := 20.0
const STOP_ACCEL := 0.5

# The loops' time, seconds within the hour: the shaders read it as the
# global loop_clock (set every frame by the interior), so the CPU can tell
# where everyone is (shader TIME cannot be read from here).
static func clock() -> float:
	return fmod(Time.get_ticks_usec() / 1e6, 3600.0)

static func make_loop(mode: int, x0: float, z0: float, width: float, height: float, corner: float, speed: float, phase_share: float, level: float, id: int) -> Dictionary:
	var loop := {"mode": mode, "x0": x0, "z0": z0, "w": width, "h": height, "corner": corner, "level": level, "id": id, "laps": 1, "phase": 0.0, "stop": -1.0}
	var length := loop_length(loop)
	loop.laps = maxi(1, roundi(speed * 3600.0 / length))
	loop.phase = phase_share * length
	return loop

static func loop_length(loop: Dictionary) -> float:
	var c: float = loop.corner
	return 2.0 * (loop.w - 2.0 * c) + 2.0 * (loop.h - 2.0 * c) + TAU * c

static func pose_s(loop: Dictionary, t: float) -> float:
	var length := loop_length(loop)
	if loop.stop >= 0.0:
		var u := stop_progress(fposmod(loop.phase + t, lap_time(loop)), length, cruise_speed(loop), lap_time(loop))
		return fposmod(loop.stop + (u if loop.laps >= 0 else -u), length)
	return fposmod(loop.phase + length * loop.laps / 3600.0 * t, length)

# Gives the loop a stop `stop_s` metres round: about `speed` between stops,
# `phase_time` seconds into its lap at t = 0 (the lap starts pulling away).
static func with_stop(loop: Dictionary, stop_s: float, speed: float, phase_time: float) -> Dictionary:
	var length := loop_length(loop)
	var wanted := length / speed + speed / STOP_ACCEL + STOP_DWELL
	var laps := maxi(1, floori(3600.0 / wanted))
	loop.laps = laps if loop.laps >= 0 else -laps
	loop.stop = stop_s
	loop.phase = phase_time
	return loop

static func lap_time(loop: Dictionary) -> float:
	return 3600.0 / absi(loop.laps)

# The cruising speed that makes a lap with its stop last lap_time:
# length / v + v / a + dwell = lap (the slower root).
static func cruise_speed(loop: Dictionary) -> float:
	return _cruise(loop_length(loop), lap_time(loop))

static func _cruise(length: float, lap: float) -> float:
	var free := lap - STOP_DWELL
	return STOP_ACCEL * 0.5 * (free - sqrt(maxf(free * free - 4.0 * length / STOP_ACCEL, 0.0)))

# Metres from the stop `tau` seconds into a lap: pull away, cruise, brake
# into the stop at `length`, wait.
static func stop_progress(tau: float, length: float, v: float, lap: float) -> float:
	var ramp := v / STOP_ACCEL
	var ramp_distance := 0.5 * v * ramp
	if tau < ramp:
		return 0.5 * STOP_ACCEL * tau * tau
	var arrive := ramp + (length - 2.0 * ramp_distance) / v + ramp
	if tau < arrive - ramp:
		return ramp_distance + v * (tau - ramp)
	if tau < arrive:
		var left := arrive - tau
		return length - 0.5 * STOP_ACCEL * left * left
	return length

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
		var c2 := Vector3(loop.stop, loop.level, loop.mode)
		var paint: Color = paints[posmod(hash(loop.id), paints.size())] if not paints.is_empty() else Color.WHITE
		data.append_array([c0.x, c1.x, c2.x, 0.0, c0.y, c1.y, c2.y, 0.0, c0.z, c1.z, c2.z, 0.0,
			paint.r, paint.g, paint.b, fposmod(loop.id * 0.618034, 1.0), 0.0, 0.0, 0.0, 0.0])
	return data

# The shader's pose in GDScript: instance i of `data` at `time`.
static func pose_from_data(data: PackedFloat32Array, i: int, time: float, corner: float) -> Transform3D:
	var b := i * INSTANCE_FLOATS
	var loop := {"x0": data[b], "z0": data[b + 4], "w": data[b + 8], "h": data[b + 1], "phase": data[b + 5], "laps": roundi(data[b + 9]),
		"stop": data[b + 2], "level": data[b + 6], "mode": roundi(data[b + 10]), "corner": corner, "id": 0}
	return pose_at(loop, time)

# The loop and pose above in GLSL (keep the two in step).
const LOOP_GLSL := """
#include "res://shaders/interior_hour.gdshaderinc"

global uniform float loop_clock;

uniform float corner = 4.0;
uniform float stop_dwell = 20.0;
uniform float stop_accel = 0.5;

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
	if (c2.x >= 0.0) {
		// With a stop: pull away, cruise, brake, wait (LoopTraffic.stop_progress).
		float lap = 3600.0 / abs(c1.z);
		float free = lap - stop_dwell;
		float v = stop_accel * 0.5 * (free - sqrt(max(free * free - 4.0 * len / stop_accel, 0.0)));
		float ramp = v / stop_accel;
		float ramp_distance = 0.5 * v * ramp;
		float tau = mod(c1.y + time, lap);
		float arrive = 2.0 * ramp + (len - 2.0 * ramp_distance) / v;
		float u = len;
		if (tau < ramp) {
			u = 0.5 * stop_accel * tau * tau;
		} else if (tau < arrive - ramp) {
			u = ramp_distance + v * (tau - ramp);
		} else if (tau < arrive) {
			u = len - 0.5 * stop_accel * (arrive - tau) * (arrive - tau);
		}
		s = mod(c2.x + (c1.z >= 0.0 ? u : -u), len);
	}
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
// This share of them (by id) is gone by night.
uniform float night_hide = 0.0;
// Drawn only between these distances from the camera (people: the animated
// model near, the plain one far).
uniform float detail_from = 0.0;
uniform float detail_to = 1e9;
#ifdef ANIMATED
// PeopleModel's walk: every vertex's point and normal in every frame,
// texel vertex + frame * vertices, 1024 to a row; one cycle every stride m.
uniform sampler2D walk_points : filter_nearest;
uniform sampler2D walk_normals : filter_nearest;
uniform int walk_vertices = 1;
uniform int walk_frames = 1;
uniform float stride = 1.4;

vec3 walk_texel(sampler2D frames, int index) {
	return texelFetch(frames, ivec2(index %% 1024, index / 1024), 0).xyz;
}
#endif

varying float part;
varying float shade;
varying float night;
varying vec3 paint;
varying float blink;

void vertex() {
	vec3 pos; vec3 left; vec3 up; vec3 forward;
	loop_pose(MODEL_MATRIX, loop_clock, pos, left, up, forward);
	float lift = bob * abs(sin(TIME * bob_rate + COLOR.a * 40.0));
	vec3 point = VERTEX;
	vec3 facing = NORMAL;
#ifdef ANIMATED
	// The walk cycle from the distance covered (no stops for people), so
	// the feet keep to the ground; each walker at its own step.
	vec3 c0 = MODEL_MATRIX[0].xyz;
	float sides = 2.0 * (c0.z - 2.0 * corner) + 2.0 * (MODEL_MATRIX[1].x - 2.0 * corner) + TAU * corner;
	float speed = abs(sides * MODEL_MATRIX[1].z / 3600.0);
	float cycle = fract(speed * loop_clock / stride + COLOR.a * 7.0) * float(walk_frames);
	int f0 = int(cycle) %% walk_frames;
	int f1 = (f0 + 1) %% walk_frames;
	float between = fract(cycle);
	int index = int(UV.y + 0.5);
	point = mix(walk_texel(walk_points, index + f0 * walk_vertices), walk_texel(walk_points, index + f1 * walk_vertices), between);
	facing = mix(walk_texel(walk_normals, index + f0 * walk_vertices), walk_texel(walk_normals, index + f1 * walk_vertices), between);
#endif
	vec3 world = pos + left * point.x + up * (point.y + lift) + forward * point.z;
	vec3 normal = normalize(left * facing.x + up * facing.y + forward * facing.z);
	night = interior_night(interior_hour(world.z));
	shade = mix(1.0, 0.3, night) * (0.6 + 0.4 * max(dot(normal, up), 0.0));
	float seen = distance(pos, INV_VIEW_MATRIX[3].xyz);
	// INSTANCE_CUSTOM.x: hidden (someone standing in for them, TownFolk).
	bool hidden = fract(COLOR.a * 13.7) < night * night_hide || seen < detail_from || seen >= detail_to || INSTANCE_CUSTOM.x > 0.5;
	VERTEX = hidden ? vec3(0.0) : (VIEW_MATRIX * vec4(world, 1.0)).xyz;
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

# `walk`: PeopleModel.bake() for the animated people (no bob then: the walk
# does it).
static func material(corner_radius: float, accent: Color, bob: float = 0.0, bob_rate: float = 2.0, night_hide: float = 0.0, walk: Dictionary = {}) -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	var code: String = LOOP_SHADER % LOOP_GLSL
	if not walk.is_empty():
		code = code.replace("render_mode unshaded, skip_vertex_transform;", "render_mode unshaded, skip_vertex_transform;\n#define ANIMATED")
		bob = 0.0
	shader_material.shader.code = code
	if not walk.is_empty():
		shader_material.set_shader_parameter("walk_points", walk.positions)
		shader_material.set_shader_parameter("walk_normals", walk.normals)
		shader_material.set_shader_parameter("walk_vertices", walk.vertices)
		shader_material.set_shader_parameter("walk_frames", walk.frames)
		shader_material.set_shader_parameter("stride", PeopleModel.STRIDE)
		shader_material.set_shader_parameter("detail_to", DETAIL_TO)
	shader_material.set_shader_parameter("corner", corner_radius)
	shader_material.set_shader_parameter("accent", accent)
	shader_material.set_shader_parameter("bob", bob)
	shader_material.set_shader_parameter("bob_rate", bob_rate)
	shader_material.set_shader_parameter("night_hide", night_hide)
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
