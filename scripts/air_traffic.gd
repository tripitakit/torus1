extends RefCounted

# The interior cruisers in the air, moved by the shader alone. Two kinds of
# lane a section:
# - circuits: stadiums in the unrolled section (x round at the flight
#   radius, z along), two straights along z TURN_RADIUS either side of the
#   lane's angle, half circles near the end walls; banked BANK in the turns;
# - rings: circles round the axis at a fixed z, either way round.
# Lanes keep clear of the spine's pylons (circuits 30 degrees round from it,
# rings STATION_CLEAR along from the stations), of ground over MAX_GROUND
# (a mountain chain: no lane there), and CLEARANCE over the ground under
# them; rings fly above every circuit, so lanes never cross.
#
# Every cruiser does a whole number of laps an hour: the shaders' TIME starts
# again every 3600 s and nothing shows. The shader reads each cruiser's lane
# from its instance basis (9 full-precision floats, see instance_buffer);
# the section node only moves along z, so its own translation comes through
# MODEL_MATRIX[3] untouched. pose / pose_from_data are the GDScript copies
# (tests).

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")
const RoadTraffic = preload("res://scripts/road_traffic.gd")

enum { CIRCUIT, RING }

const CIRCUITS := 6
const RINGS := 4
const CIRCUIT_CRAFT := 8
const RING_CRAFT := 12
const TURN_RADIUS := 80.0
const BANK := PI / 6.0
const CLEARANCE := 350.0
const MAX_GROUND := 600.0
const STATION_CLEAR := 300.0
const WALL_CLEAR := 1500.0
const SPINE_CLEAR := PI / 6.0
const CIRCUIT_GAP := deg_to_rad(40.0)
const RING_GAP := 1500.0
const RING_ABOVE := 150.0
const CIRCUIT_SPEEDS := Vector2(70.0, 90.0)
const RING_SPEEDS := Vector2(60.0, 80.0)
const SAMPLE_STEP := 25.0
# Per cruiser in a CPU buffer (tests): 12 of transform, 4 of colour.
const FLOATS := 16

# The section's lanes. Pure: safe on a worker thread.
static func lanes(plan) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, "air"])
	var found := []
	# Circuits: the wanted angles a sixth of a turn apart from half a step off
	# the spine, each moved to the nearest free angle (10 degree steps) whose
	# path stays over low ground and clear of the spine and the others.
	var spine := SpineTrain.spine_angle()
	var highest := 0.0
	for k in range(CIRCUITS):
		var wanted := spine + TAU * (k + 0.5) / CIRCUITS
		var z0 := WALL_CLEAR + rng.randf() * 1500.0
		var z1: float = plan.length - WALL_CLEAR - rng.randf() * 1500.0
		var lift := rng.randf() * 250.0
		for step in range(0, 18):
			var angle := wanted + deg_to_rad(10.0) * ((step + 1) / 2) * (1.0 if step % 2 == 0 else -1.0)
			if absf(angle_difference(angle, spine)) < SPINE_CLEAR - 0.001 or found.any(func(l: Dictionary) -> bool: return absf(angle_difference(l.angle, angle)) < CIRCUIT_GAP):
				continue
			var lane := {"kind": CIRCUIT, "angle": fposmod(angle, TAU), "z0": z0, "z1": z1, "r": plan.radius}
			var ground := _highest_under(lane, plan)
			if ground > MAX_GROUND:
				continue
			lane.r = plan.radius - (ground + CLEARANCE + lift)
			highest = maxf(highest, ground + CLEARANCE + lift)
			found.append(_crew(lane, CIRCUIT_CRAFT, CIRCUIT_SPEEDS, rng))
			break
	# Rings: z spread along the section, clear of the stations and of high
	# ground all round, above every circuit.
	var stations := SpineTrain.station_z(plan)
	var ring_zs := []
	for k in range(RINGS):
		var wanted: float = WALL_CLEAR + (plan.length - 2.0 * WALL_CLEAR) * (k + 0.5) / RINGS + rng.randf_range(-700.0, 700.0)
		var lift := rng.randf() * 150.0
		var sign := 1.0 if k % 2 == 0 else -1.0
		for step in range(0, 60):
			var z := wanted + 250.0 * ((step + 1) / 2) * (1.0 if step % 2 == 0 else -1.0)
			if z < WALL_CLEAR or z > plan.length - WALL_CLEAR or stations.any(func(s: float) -> bool: return absf(s - z) < STATION_CLEAR) or ring_zs.any(func(o: float) -> bool: return absf(o - z) < RING_GAP):
				continue
			var lane := {"kind": RING, "angle": rng.randf() * TAU, "z": z, "sign": sign, "r": plan.radius}
			var ground := _highest_under(lane, plan)
			if ground > MAX_GROUND:
				continue
			lane.r = plan.radius - (maxf(ground + CLEARANCE, highest + RING_ABOVE) + lift)
			ring_zs.append(z)
			found.append(_crew(lane, RING_CRAFT, RING_SPEEDS, rng))
			break
	return found

static func _crew(lane: Dictionary, craft: int, speeds: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	lane.craft = craft
	lane.laps = maxi(1, roundi(rng.randf_range(speeds.x, speeds.y) * 3600.0 / lane_length(lane)))
	lane.phase = rng.randf() * lane_length(lane)
	return lane

static func cruiser_count(all: Array) -> int:
	var count := 0
	for lane: Dictionary in all:
		count += lane.craft
	return count

static func leg_length(lane: Dictionary) -> float:
	return lane.z1 - lane.z0

static func lane_length(lane: Dictionary) -> float:
	if lane.kind == RING:
		return TAU * lane.r
	return 2.0 * leg_length(lane) + TAU * TURN_RADIUS

static func speed(lane: Dictionary) -> float:
	return lane_length(lane) * lane.laps / 3600.0

# The highest ground under a lane (its angles at the flight radius drawn
# down to the ground), every SAMPLE_STEP along it.
static func _highest_under(lane: Dictionary, plan) -> float:
	var highest := 0.0
	var s := 0.0
	var length := lane_length(lane)
	while s < length:
		var p := _unrolled(lane, s)
		highest = maxf(highest, plan.height_at(p.x / lane.r * plan.radius, p.y))
		s += SAMPLE_STEP * lane.r / plan.radius
	return highest

# Where `s` metres along a lane lies in the unrolled section at the flight
# radius: (x, z), the heading (dx, dz), and for a turn the way to its
# centre (cx, cz) with turning 1, else 0.
static func _unrolled_full(lane: Dictionary, s: float) -> Array:
	if lane.kind == RING:
		var x: float = lane.angle * lane.r + lane.sign * s
		return [Vector2(x, lane.z), Vector2(lane.sign, 0.0), Vector2.ZERO, 0.0]
	var xc: float = lane.angle * lane.r
	var w := TURN_RADIUS
	var leg := leg_length(lane)
	var turn := PI * w
	if s < leg:
		return [Vector2(xc + w, lane.z0 + s), Vector2(0.0, 1.0), Vector2.ZERO, 0.0]
	s -= leg
	if s < turn:
		var phi := s / w
		return [Vector2(xc + w * cos(phi), lane.z1 + w * sin(phi)), Vector2(-sin(phi), cos(phi)), Vector2(-cos(phi), -sin(phi)), 1.0]
	s -= turn
	if s < leg:
		return [Vector2(xc - w, lane.z1 - s), Vector2(0.0, -1.0), Vector2.ZERO, 0.0]
	s -= leg
	var phi2 := PI + s / w
	return [Vector2(xc + w * cos(phi2), lane.z0 + w * sin(phi2)), Vector2(-sin(phi2), cos(phi2)), Vector2(-cos(phi2), -sin(phi2)), 1.0]

static func _unrolled(lane: Dictionary, s: float) -> Vector2:
	return _unrolled_full(lane, fposmod(s, lane_length(lane)))[0]

# The cruiser's frame `s` metres along its lane, in the section's frame:
# x left, y up (toward the axis, banked in turns), z forward.
static func pose(lane: Dictionary, s: float, plan) -> Transform3D:
	var at := _unrolled_full(lane, fposmod(s, lane_length(lane)))
	return _frame(lane.r, at[0], at[1], at[2], at[3], -plan.length * 0.5)

static func _frame(r: float, p: Vector2, heading: Vector2, centre: Vector2, turning: float, z_shift: float) -> Transform3D:
	var a := p.x / r
	var tangent := Vector3(-sin(a), cos(a), 0.0)
	var along := Vector3(0.0, 0.0, 1.0)
	var forward := (tangent * heading.x + along * heading.y).normalized()
	var up := Vector3(-cos(a), -sin(a), 0.0)
	if turning > 0.5:
		var inward := (tangent * centre.x + along * centre.y).normalized()
		up = up * cos(BANK) + inward * sin(BANK)
	return Transform3D(Basis(up.cross(forward), up, forward), Vector3(cos(a) * r, sin(a) * r, p.y + z_shift))

static func _craft_s(lane: Dictionary, k: int, t: float) -> float:
	var length := lane_length(lane)
	return fposmod(lane.phase + k * length / lane.craft + speed(lane) * t, length)

# Every cruiser's frame and colour at time t (tests; the game uses
# instance_buffer and the shader).
static func buffer(all: Array, plan, t: float) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for lane: Dictionary in all:
		for k in range(lane.craft):
			var f := pose(lane, _craft_s(lane, k, t), plan)
			var b := f.basis
			var o := f.origin
			data.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, 1.0, 1.0, 1.0, 1.0])
	return data

# The GPU data, 20 floats a cruiser (transform, colour, custom unused). The
# basis columns hold the lane: (kind, r, angle), (z0 or z, z1 or sign,
# phase), (laps an hour, id, 0), z in the section's frame; the translation
# is 0. Colour: paint, id fraction (blinking).
static func instance_buffer(all: Array, plan) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	var id := 0
	for lane: Dictionary in all:
		for k in range(lane.craft):
			var c0 := Vector3(lane.kind, lane.r, lane.angle)
			var c1: Vector3
			var phase := fposmod(lane.phase + k * lane_length(lane) / lane.craft, lane_length(lane))
			if lane.kind == RING:
				c1 = Vector3(lane.z - plan.length * 0.5, lane.sign, phase)
			else:
				c1 = Vector3(lane.z0 - plan.length * 0.5, lane.z1 - plan.length * 0.5, phase)
			var c2 := Vector3(lane.laps, id, 0.0)
			var paint: Color = PAINTS[hash([plan.section_index, id]) % PAINTS.size()]
			data.append_array([c0.x, c1.x, c2.x, 0.0, c0.y, c1.y, c2.y, 0.0, c0.z, c1.z, c2.z, 0.0,
				paint.r, paint.g, paint.b, fposmod(id * 0.618034, 1.0), 0.0, 0.0, 0.0, 0.0])
			id += 1
	return data

const INSTANCE_FLOATS := 20
const PAINTS := [Color(0.88, 0.9, 0.92), Color(0.3, 0.32, 0.35), Color(0.62, 0.64, 0.68), Color(0.32, 0.42, 0.55), Color(0.45, 0.07, 0.08), Color(0.1, 0.11, 0.13)]

# The shader's pose, in GDScript (tests): cruiser `i` of instance_buffer's
# data at `time`, in the section's frame.
static func pose_from_data(data: PackedFloat32Array, i: int, time: float) -> Transform3D:
	var b := i * INSTANCE_FLOATS
	var c0 := Vector3(data[b], data[b + 4], data[b + 8])
	var c1 := Vector3(data[b + 1], data[b + 5], data[b + 9])
	var c2 := Vector3(data[b + 2], data[b + 6], data[b + 10])
	var lane := {"kind": roundi(c0.x), "r": c0.y, "angle": c0.z, "laps": c2.x, "phase": c1.z, "craft": 1}
	if lane.kind == RING:
		lane.z = c1.x
		lane.sign = c1.y
	else:
		lane.z0 = c1.x
		lane.z1 = c1.y
	var s := fposmod(lane.phase + speed(lane) * time, lane_length(lane))
	var at := _unrolled_full(lane, s)
	return _frame(lane.r, at[0], at[1], at[2], at[3], 0.0)

# --- Drawing -----------------------------------------------------------------

# The lane and pose as above, in GLSL; `node` is the section node's
# translation (MODEL_MATRIX[3]).
const POSE_GLSL := """
#include "res://shaders/interior_hour.gdshaderinc"

const float TURN_RADIUS = 80.0;
const float BANK = 0.5235988;

void air_pose(mat4 model, float time, out vec3 pos, out vec3 left, out vec3 up, out vec3 forward) {
	vec3 c0 = model[0].xyz;
	vec3 c1 = model[1].xyz;
	vec3 c2 = model[2].xyz;
	vec3 node = model[3].xyz;
	float r = c0.y;
	float w = TURN_RADIUS;
	bool ring = c0.x > 0.5;
	float len = ring ? TAU * r : 2.0 * (c1.y - c1.x) + TAU * w;
	float s = mod(c1.z + len * c2.x / 3600.0 * time, len);
	vec2 p; vec2 heading; vec2 centre = vec2(0.0); float turning = 0.0;
	if (ring) {
		p = vec2(c0.z * r + c1.y * s, c1.x);
		heading = vec2(c1.y, 0.0);
	} else {
		float xc = c0.z * r;
		float leg = c1.y - c1.x;
		float turn = 3.14159265 * w;
		if (s < leg) {
			p = vec2(xc + w, c1.x + s); heading = vec2(0.0, 1.0);
		} else if (s < leg + turn) {
			float phi = (s - leg) / w;
			p = vec2(xc + w * cos(phi), c1.y + w * sin(phi)); heading = vec2(-sin(phi), cos(phi)); centre = -vec2(cos(phi), sin(phi)); turning = 1.0;
		} else if (s < 2.0 * leg + turn) {
			p = vec2(xc - w, c1.y - (s - leg - turn)); heading = vec2(0.0, -1.0);
		} else {
			float phi = 3.14159265 + (s - 2.0 * leg - turn) / w;
			p = vec2(xc + w * cos(phi), c1.x + w * sin(phi)); heading = vec2(-sin(phi), cos(phi)); centre = -vec2(cos(phi), sin(phi)); turning = 1.0;
		}
	}
	float a = p.x / r;
	vec3 tangent = vec3(-sin(a), cos(a), 0.0);
	forward = normalize(tangent * heading.x + vec3(0.0, 0.0, heading.y));
	up = vec3(-cos(a), -sin(a), 0.0);
	if (turning > 0.5) {
		vec3 inward = normalize(tangent * centre.x + vec3(0.0, 0.0, centre.y));
		up = up * cos(BANK) + inward * sin(BANK);
	}
	left = cross(up, forward);
	pos = vec3(cos(a) * r, sin(a) * r, p.y) + node;
}
"""

const CRUISER_SHADER := """
shader_type spatial;
render_mode unshaded, skip_vertex_transform;
%s
// The buildings' accents: warm white, cool white, cyan, amber, magenta.
const vec3 ACCENTS[5] = vec3[5](vec3(1.0, 0.82, 0.55), vec3(0.8, 0.9, 1.0), vec3(0.3, 0.9, 1.0), vec3(1.0, 0.6, 0.2), vec3(1.0, 0.3, 0.8));

varying float part;
varying float shade;
varying float night;
varying vec3 paint;
varying vec3 accent;

void vertex() {
	vec3 pos; vec3 left; vec3 up; vec3 forward;
	air_pose(MODEL_MATRIX, TIME, pos, left, up, forward);
	vec3 world = pos + left * VERTEX.x + up * VERTEX.y + forward * VERTEX.z;
	vec3 normal = normalize(left * NORMAL.x + up * NORMAL.y + forward * NORMAL.z);
	night = interior_night(interior_hour(world.z));
	vec3 toward_axis = -normalize(vec3(world.xy, 0.0));
	shade = mix(1.0, 0.3, night) * (0.6 + 0.4 * max(dot(normal, toward_axis), 0.0));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = mat3(VIEW_MATRIX) * normal;
	part = UV.x;
	paint = COLOR.rgb;
	accent = ACCENTS[int(fract(COLOR.a * 7.31) * 4.99)];
}

void fragment() {
	// UV.x: 0 hull, 1 glass, 2 engine glow, 3 port light (red), 4 starboard (green).
	if (part < 0.5) {
		ALBEDO = paint * shade;
	} else if (part < 1.5) {
		ALBEDO = (vec3(0.06, 0.08, 0.1) + accent * 0.1) * shade;
	} else if (part < 2.5) {
		ALBEDO = accent * mix(1.0, 1.8, night);
	} else if (part < 3.5) {
		ALBEDO = vec3(1.0, 0.1, 0.05) * mix(0.8, 1.6, night);
	} else {
		ALBEDO = vec3(0.1, 1.0, 0.3) * mix(0.8, 1.6, night);
	}
}
"""

# A white strobe on every cruiser, at least min_pixels wide: the far ones
# show, by night above all.
const STROBE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;
%s
uniform float strobe_size = 2.5;
uniform float min_pixels = 2.0;
uniform float period = 1.4;
uniform float on_time = 0.2;

varying float bright;

void vertex() {
	vec3 pos; vec3 left; vec3 up; vec3 forward;
	air_pose(MODEL_MATRIX, TIME, pos, left, up, forward);
	vec3 centre = (VIEW_MATRIX * vec4(pos + up * 1.2, 1.0)).xyz;
	float depth = max(-centre.z, 0.001);
	float pixel = 2.0 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);
	float size = max(strobe_size, min_pixels * pixel * depth);
	float pull = clamp((depth - max(size, 0.01 * depth)) / depth, 0.1, 1.0);
	bool on = mod(TIME + COLOR.a * period, period) < on_time;
	VERTEX = on ? (centre + vec3(VERTEX.xy * size, 0.0)) * pull : vec3(0.0);
	bright = mix(0.8, 1.0, interior_night(interior_hour(pos.z)));
}

void fragment() {
	ALBEDO = vec3(1.0) * bright;
}
"""

static func cruiser_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = CRUISER_SHADER % POSE_GLSL
	return material

static func strobe_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = STROBE_SHADER % POSE_GLSL
	return material

# A low-poly sci-fi cruiser about 9 m long, +Z forward, +X left, y up:
# faceted dart of a hull, glass canopy, swept wings, two engine pods with
# glowing exhausts, a red light on the left wing tip, green on the right.
static func cruiser_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadTraffic._loft(st, [[-4.5, 0.9, -0.5, 0.5], [-2.0, 1.3, -0.6, 0.8], [2.0, 1.0, -0.5, 0.7], [4.6, 0.25, -0.12, 0.12]], 0.0)
	RoadTraffic._loft(st, [[-1.2, 0.55, 0.45, 0.85], [0.4, 0.65, 0.5, 1.25], [2.3, 0.35, 0.45, 0.72]], 1.0)
	for side: float in [-1.0, 1.0]:
		# Swept wing: root along the hull, tip further back.
		var root_a := Vector3(side * 1.1, -0.15, 0.6)
		var root_b := Vector3(side * 1.1, -0.15, -3.0)
		var tip_a := Vector3(side * 4.8, -0.05, -2.2)
		var tip_b := Vector3(side * 4.8, -0.05, -3.4)
		var up := Vector3(0.0, 0.18, 0.0)
		var p := [root_a, tip_a, tip_b, root_b, root_a + up, tip_a + up, tip_b + up, root_b + up]
		var centre := (root_a + tip_b) * 0.5 + up * 0.5
		for quad in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
			RoadTraffic._face(st, [p[quad[0]], p[quad[1]], p[quad[2]], p[quad[3]]], centre, 0.0)
		RoadTraffic._box(st, Vector3(side * 1.8 - 0.45, -0.75, -4.4), Vector3(side * 1.8 + 0.45, 0.15, -0.6), 0.0)
		RoadTraffic._box(st, Vector3(side * 1.8 - 0.35, -0.65, -4.55), Vector3(side * 1.8 + 0.35, 0.05, -4.4), 2.0)
		RoadTraffic._box(st, Vector3(side * 4.8 - 0.15, -0.1, -3.0), Vector3(side * 4.8 + 0.15, 0.25, -2.6), 3.0 if side > 0.0 else 4.0)
	st.index()
	return st.commit()

static func strobe_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	return quad

static func multimesh_instance(node_name: String, data: PackedFloat32Array, mesh: Mesh, material: Material, bounds: AABB) -> MultiMeshInstance3D:
	return RoadTraffic.multimesh_instance(node_name, data, mesh, material, bounds)
