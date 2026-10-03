extends RefCounted

# Cars on a section's roads, moved by the shader alone (no work per frame on
# the CPU). Each run of road (a stretch of lot edges with road, one type) is
# driven on the right in two lanes. A closed ring round the section gives one
# loop per lane; any other run one loop over both lanes, with a U-turn at
# each end, so no car ever appears or vanishes at a dead end.
#
# On a loop C metres long sit N places, `spacing` = C / N apart; they all
# move at `speed`, which is set so that every car does a whole number of laps
# an hour: the shaders' TIME starts again every 3600 s and nothing shows.
# Every chunk holds, for each stretch of lane inside it, one instance per
# place that can be there: the instance starts at a place of the loop's grid
# and moves on by fract(f TIME) * spacing (f = speed / spacing), drawn only
# between its limits lo..hi (the stretch). The next chunk holds the same
# place with the complementary limits: one chunk draws each car, and it
# passes on with no jump. The car's identity n = n0 - floor(f TIME) (mod N)
# picks whether the place is taken and its colour, the same all round.
#
# Instance data (FLOATS a car): the transform is the place's real frame at
# TIME 0 in the chunk's frame, columns (left, up, forward * spacing): the
# length carries the spacing at full precision. Colour and custom data
# (16-bit in the Compatibility renderer) carry only small numbers: colour
# (curved 0/1, loop seed, places passed an hour = f * 3600 as high and low
# parts of 1024), custom (lo, hi, n0, N). The places passed an hour are a
# whole number, the same in every instance of a loop: all of them agree to
# the last bit on when a place moves on to the next (a length read back from
# a turned vector would not).

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const FLOATS := 20
const LANE_OFFSET_MAIN := 3.0
const LANE_OFFSET_STREET := 2.0
const SPACING_MAIN := 90.0
const SPACING_STREET := 160.0
# Runs touching the city: this much closer.
const CITY_DENSITY := 2.5
const SPEED_MAIN := 25.0
const SPEED_STREET := 14.0
# Small integers stay exact in 16-bit floats up to 2048.
const MAX_SMALL := 2048
# Lane limits are rounded to this (metres).
const LIMIT_STEP := 0.001
const PER_HOUR_SPLIT := 1024

static func spacing(road: int, city: bool) -> float:
	var base := SPACING_MAIN if road == SectionPlanScript.Road.MAIN else SPACING_STREET
	return base / CITY_DENSITY if city else base

static func speed(road: int) -> float:
	return SPEED_MAIN if road == SectionPlanScript.Road.MAIN else SPEED_STREET

static func lane_offset(road: int) -> float:
	return LANE_OFFSET_MAIN if road == SectionPlanScript.Road.MAIN else LANE_OFFSET_STREET

# The stretches of road: {along, line, start, count, road, closed, city}.
# Along runs lie on lot column `line`'s west edge (x = line * lot_width),
# edges `start`.. along it; around runs on row `line`'s south edge
# (z = line * lot_length), edges counted round it (they may wrap past 0).
static func runs(plan) -> Array:
	var found := []
	for column in range(SectionPlanScript.LOTS_AROUND):
		var roads := []
		for edge in range(SectionPlanScript.LOTS_ALONG):
			roads.append(plan.road_west[plan.lot_index(column, edge)])
		found.append_array(_line_runs(plan, true, column, roads, false))
	for row in range(1, SectionPlanScript.LOTS_ALONG):
		var roads := []
		for edge in range(SectionPlanScript.LOTS_AROUND):
			roads.append(plan.road_south[plan.lot_index(edge, row)])
		found.append_array(_line_runs(plan, false, row, roads, true))
	return found

static func _line_runs(plan, along: bool, line: int, roads: Array, wraps: bool) -> Array:
	var count := roads.size()
	var found := []
	if wraps and not roads.has(SectionPlanScript.Road.NONE) and _single_type(roads):
		found.append(_run(plan, along, line, 0, count, roads[0], true))
		return found
	# Start just after a gap, so a run wrapping past 0 is found whole.
	var first := 0
	if wraps:
		first = roads.find(SectionPlanScript.Road.NONE) + 1
	var k := 0
	while k < count:
		var edge := first + k
		var road: int = roads[edge % count] if wraps else roads[edge]
		if road == SectionPlanScript.Road.NONE:
			k += 1
			continue
		var length := 1
		while k + length < count and (roads[(edge + length) % count] if wraps else roads[edge + length]) == road:
			length += 1
		found.append(_run(plan, along, line, edge % count if wraps else edge, length, road, false))
		k += length
	return found

static func _single_type(roads: Array) -> bool:
	for road in roads:
		if road != roads[0]:
			return false
	return true

static func _run(plan, along: bool, line: int, start: int, count: int, road: int, closed: bool) -> Dictionary:
	var city := false
	for k in range(count):
		var edge := start + k
		var lots: Array = [Vector2i(line - 1, edge), Vector2i(line, edge)] if along else [Vector2i(edge, line - 1), Vector2i(edge, line)]
		for lot: Vector2i in lots:
			city = city or plan.zone_at(lot.x, lot.y) == SectionPlanScript.Zone.CITY
	return {"along": along, "line": line, "start": start, "count": count, "road": road, "closed": closed, "city": city}

# One loop per lane of a closed run, one over both lanes of any other:
# {pieces, length, cars, spacing, speed, road, city, seed}. A piece is a
# straight run of lane in the unrolled section (x round, z along):
# {axis (0 = x, 1 = z), x0, z0, sign, length, loop_start}.
static func loops(plan) -> Array:
	var found := []
	for run: Dictionary in runs(plan):
		var offset := lane_offset(run.road)
		if run.along:
			var x: float = run.line * plan.lot_width
			var z0: float = run.start * plan.lot_length
			var length: float = run.count * plan.lot_length
			found.append(_loop(run, [_piece(1, x - offset, z0, 1.0, length), _piece(1, x + offset, z0 + length, -1.0, length)], found.size()))
		else:
			var z: float = run.line * plan.lot_length
			var x0: float = run.start * plan.lot_width
			var length: float = run.count * plan.lot_width
			if run.closed:
				found.append(_loop(run, [_piece(0, x0, z + offset, 1.0, length)], found.size()))
				found.append(_loop(run, [_piece(0, x0 + length, z - offset, -1.0, length)], found.size()))
			else:
				found.append(_loop(run, [_piece(0, x0, z + offset, 1.0, length), _piece(0, x0 + length, z - offset, -1.0, length)], found.size()))
	return found

static func _piece(axis: int, x0: float, z0: float, sign: float, length: float) -> Dictionary:
	return {"axis": axis, "x0": x0, "z0": z0, "sign": sign, "length": length, "loop_start": 0.0}

static func _loop(run: Dictionary, pieces: Array, index: int) -> Dictionary:
	var length := 0.0
	for piece: Dictionary in pieces:
		piece.loop_start = length
		length += piece.length
	var cars := maxi(1, roundi(length / spacing(run.road, run.city)))
	var laps := maxi(1, roundi(speed(run.road) * 3600.0 / length))
	return {"pieces": pieces, "length": length, "cars": cars, "spacing": length / cars, "speed": length * laps / 3600.0,
		"road": run.road, "city": run.city, "seed": index % MAX_SMALL}

# The chunk's frame in the section's (as InteriorWorld places it): turned
# about Z to its first column, shifted to its first row.
static func chunk_transform(plan, key: Vector2i) -> Transform3D:
	var chunk_width: float = SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width
	var chunk_length: float = SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length
	return Transform3D(Basis(Vector3(0.0, 0.0, 1.0), key.x * chunk_width / plan.radius), Vector3(0.0, 0.0, -plan.length * 0.5 + key.y * chunk_length))

# A point of the unrolled section on the ground, in the section's frame.
static func _ground(plan, x: float, z: float) -> Vector3:
	var angle: float = x / plan.radius
	return Vector3(cos(angle) * plan.radius, sin(angle) * plan.radius, z - plan.length * 0.5)

# Every chunk's car instances: Vector2i(around, along) -> PackedFloat32Array.
# Pure: safe on a worker thread.
static func chunk_instances(plan, all_loops: Array) -> Dictionary:
	var chunk_width: float = SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width
	var chunk_length: float = SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length
	var chunks_around: int = SectionPlanScript.LOTS_AROUND / SectionPlanScript.CHUNK_LOTS_AROUND
	var chunks_along: int = SectionPlanScript.LOTS_ALONG / SectionPlanScript.CHUNK_LOTS_ALONG
	var by_chunk := {}
	var frames := {}
	for loop: Dictionary in all_loops:
		var d: float = loop.spacing
		var per_hour: int = roundi(loop.speed / d * 3600.0)
		for piece: Dictionary in loop.pieces:
			var start: float = piece.x0 if piece.axis == 0 else piece.z0
			var step: float = chunk_width if piece.axis == 0 else chunk_length
			# Where the piece crosses chunk borders, in metres along it.
			var cuts := [0.0]
			var border: float = (floorf(start / step) + (1.0 if piece.sign > 0.0 else 0.0)) * step
			while true:
				var u: float = (border - start) * piece.sign
				if u >= piece.length - 0.0001:
					break
				if u > 0.0001:
					cuts.append(u)
				border += step * piece.sign
			cuts.append(piece.length)
			for c in range(cuts.size() - 1):
				var u0: float = cuts[c]
				var u1: float = cuts[c + 1]
				var mid := _piece_point(piece, (u0 + u1) * 0.5)
				var key := Vector2i(posmod(floori(mid.x / chunk_width), chunks_around), clampi(floori(mid.y / chunk_length), 0, chunks_along - 1))
				if not frames.has(key):
					frames[key] = chunk_transform(plan, key).affine_inverse()
					by_chunk[key] = PackedFloat32Array()
				var to_chunk: Transform3D = frames[key]
				var a: float = piece.loop_start + u0
				var b: float = piece.loop_start + u1
				# One place more each side than the division says: a border on a
				# place must not fall between two chunks' rounding.
				for k in range(floori(a / d) - 1, ceili(b / d) + 1):
					var s: float = k * d
					# Limits rounded alike on both sides of a border: complementary.
					var lo := snappedf(a - s, LIMIT_STEP)
					var hi := snappedf(b - s, LIMIT_STEP)
					if hi <= 0.0 or lo >= d:
						continue
					var frame := _piece_frame(plan, piece, s - piece.loop_start)
					var local: Transform3D = to_chunk * frame
					var data: PackedFloat32Array = by_chunk[key]
					data.append_array(_instance(local, per_hour, d, piece.axis == 0, loop.seed, maxf(lo, -1.0), minf(hi, d + 1.0), posmod(k, loop.cars), loop.cars))
					by_chunk[key] = data
	return by_chunk

# The unrolled point (x, z) `u` metres along a piece.
static func _piece_point(piece: Dictionary, u: float) -> Vector2:
	if piece.axis == 0:
		return Vector2(piece.x0 + piece.sign * u, piece.z0)
	return Vector2(piece.x0, piece.z0 + piece.sign * u)

# The place's frame in the section's: columns (left, up, forward), origin on
# the ground. Past either end of the piece it carries on along its line.
static func _piece_frame(plan, piece: Dictionary, u: float) -> Transform3D:
	var point := _piece_point(piece, u)
	var angle: float = point.x / plan.radius
	var up := Vector3(-cos(angle), -sin(angle), 0.0)
	var forward: Vector3 = Vector3(0.0, 0.0, piece.sign) if piece.axis == 1 else Vector3(-sin(angle), cos(angle), 0.0) * piece.sign
	return Transform3D(Basis(up.cross(forward), up, forward), _ground(plan, point.x, point.y))

static func _instance(frame: Transform3D, per_hour: int, d: float, curved: bool, seed: int, lo: float, hi: float, n0: int, cars: int) -> PackedFloat32Array:
	var bx := frame.basis.x.normalized()
	var by := frame.basis.y.normalized()
	var bz := frame.basis.z.normalized() * d
	var o := frame.origin
	return PackedFloat32Array([bx.x, by.x, bz.x, o.x, bx.y, by.y, bz.y, o.y, bx.z, by.z, bz.z, o.z,
		1.0 if curved else 0.0, seed, per_hour / PER_HOUR_SPLIT, per_hour % PER_HOUR_SPLIT, lo, hi, n0, cars])

# All of a section's instances in the section's frame (the far MultiMesh).
static func section_buffer(plan, by_chunk: Dictionary) -> PackedFloat32Array:
	var all := PackedFloat32Array()
	for key: Vector2i in by_chunk:
		var xform := chunk_transform(plan, key)
		var data: PackedFloat32Array = by_chunk[key]
		for i in range(data.size() / FLOATS):
			var b := i * FLOATS
			var frame := Transform3D(Basis(Vector3(data[b], data[b + 4], data[b + 8]), Vector3(data[b + 1], data[b + 5], data[b + 9]), Vector3(data[b + 2], data[b + 6], data[b + 10])), Vector3(data[b + 3], data[b + 7], data[b + 11]))
			var moved := xform * frame
			var bx := moved.basis.x
			var by := moved.basis.y
			var bz := moved.basis.z
			var o := moved.origin
			all.append_array(PackedFloat32Array([bx.x, by.x, bz.x, o.x, bx.y, by.y, bz.y, o.y, bx.z, by.z, bz.z, o.z]))
			all.append_array(data.slice(b + 12, b + FLOATS))
	return all

# The shaders' car, in GDScript (for tests): instance `i` of `data` at
# `time`, in the instance data's frame. {visible, position, forward, up,
# car, seed}. Visible ignores whether the place is taken (a hash in the
# shader).
static func car_at(data: PackedFloat32Array, i: int, time: float, radius: float) -> Dictionary:
	var b := i * FLOATS
	var left := Vector3(data[b], data[b + 4], data[b + 8])
	var up := Vector3(data[b + 1], data[b + 5], data[b + 9]).normalized()
	var forward_scaled := Vector3(data[b + 2], data[b + 6], data[b + 10])
	var origin := Vector3(data[b + 3], data[b + 7], data[b + 11])
	var f := (data[b + 14] * PER_HOUR_SPLIT + data[b + 15]) / 3600.0
	var d := forward_scaled.length()
	var forward := forward_scaled / d
	var cycles := f * time
	var off := (cycles - floorf(cycles)) * d
	var position := origin + forward * off
	if data[b + 12] > 0.5:
		var theta := off / radius
		position = origin + (forward * sin(theta) + up * (1.0 - cos(theta))) * radius
		var turned_forward := forward * cos(theta) + up * sin(theta)
		up = up * cos(theta) - forward * sin(theta)
		forward = turned_forward
	return {"visible": off >= data[b + 16] and off < data[b + 17], "position": position, "forward": forward, "up": up, "left": left,
		"car": posmod(int(data[b + 18]) - floori(cycles), int(data[b + 19])), "seed": int(data[b + 13])}

# Near cars (chunk MultiMeshes, up to NEAR_END from the camera) and far dots
# (one MultiMesh a section, DOT_NEAR to DOT_FAR): the dots begin well inside
# NEAR_END, so a car in a chunk whose centre is past NEAR_END is a dot.
const NEAR_END := 2000.0
const DOT_NEAR := 1200.0
# By night a car's light bars go under a pixel well before DOT_NEAR: its dot
# takes over from here.
const DOT_NEAR_NIGHT := 250.0
const DOT_FAR := 12000.0
const DAY_SHARE := 0.85
const NIGHT_SHARE := 0.5

# The car's place as RoadTraffic.car_at computes it, in view space: sets
# `pos`, `left`, `up`, `forward`, `night` and returns whether a car is there.
const PLACE_GLSL := """
#include "res://shaders/interior_hour.gdshaderinc"

uniform float ground_radius = 2000.0;
uniform float day_share = 0.85;
uniform float night_share = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

bool place(mat4 modelview, mat4 inv_view, vec4 data, vec4 limits, float time, out vec3 pos, out vec3 left, out vec3 up, out vec3 forward, out float night, out float car) {
	vec3 origin = (modelview * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	left = normalize((modelview * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	up = normalize((modelview * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 forward_scaled = (modelview * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
	float spacing = length(forward_scaled);
	forward = forward_scaled / spacing;
	float cycles = (data.b * 1024.0 + data.a) / 3600.0 * time;
	float off = fract(cycles) * spacing;
	pos = origin + forward * off;
	if (data.r > 0.5) {
		float theta = off / ground_radius;
		pos = origin + (forward * sin(theta) + up * (1.0 - cos(theta))) * ground_radius;
		vec3 turned = forward * cos(theta) + up * sin(theta);
		up = up * cos(theta) - forward * sin(theta);
		forward = turned;
	}
	night = interior_night(interior_hour((inv_view * vec4(pos, 1.0)).z));
	car = mod(limits.z - floor(cycles), limits.w);
	return off >= limits.x && off < limits.y && hash(vec2(car, data.g)) < mix(day_share, night_share, night);
}
"""

# Unshaded, lit in the shader from the hour: the Compatibility renderer
# draws a lit object once more for every light that reaches it, and up to 8
# suns reach a chunk. Light from the axis (the car's up) plus a share of
# ambient, scaled by the daylight where the car is.
const CAR_SHADER := """
shader_type spatial;
render_mode unshaded, skip_vertex_transform;
%s
// Body colours: pearl white, gunmetal, graphite, steel blue, silver, deep red.
const vec3 PAINTS[6] = vec3[6](vec3(0.88, 0.9, 0.92), vec3(0.3, 0.32, 0.35), vec3(0.1, 0.11, 0.13), vec3(0.32, 0.42, 0.55), vec3(0.62, 0.64, 0.68), vec3(0.45, 0.07, 0.08));
// The buildings' accents (TerrainDressing): warm white, cool white, cyan, amber, magenta.
const vec3 ACCENTS[5] = vec3[5](vec3(1.0, 0.82, 0.55), vec3(0.8, 0.9, 1.0), vec3(0.3, 0.9, 1.0), vec3(1.0, 0.6, 0.2), vec3(1.0, 0.3, 0.8));

varying float part;
varying vec3 paint;
varying vec3 accent;
varying float dark;
varying float shade;

void vertex() {
	vec3 pos; vec3 left; vec3 up; vec3 forward; float night; float car;
	bool shown = place(MODELVIEW_MATRIX, INV_VIEW_MATRIX, COLOR, INSTANCE_CUSTOM, TIME, pos, left, up, forward, night, car);
	// A slow bob on the hover field, each car its own.
	float bob = 0.06 * sin(TIME * 2.1 + car * 1.7 + COLOR.g);
	VERTEX = shown ? pos + left * VERTEX.x + up * (VERTEX.y + bob) + forward * VERTEX.z : vec3(0.0);
	NORMAL = left * NORMAL.x + up * NORMAL.y + forward * NORMAL.z;
	part = UV.x;
	paint = PAINTS[int(hash(vec2(COLOR.g + 0.5, car * 1.3)) * 5.99)];
	accent = ACCENTS[int(hash(vec2(car * 0.7, COLOR.g + 2.5)) * 4.99)];
	dark = night;
	shade = mix(1.0, 0.3, night) * (0.45 + 0.55 * max(dot(NORMAL, up), 0.0));
}

void fragment() {
	// UV.x: 0 body, 1 glass, 2 headlight, 3 tail light, 4 under-glow.
	if (part < 0.5) {
		ALBEDO = paint * shade;
	} else if (part < 1.5) {
		// Dark glass with a hint of the accent.
		ALBEDO = (vec3(0.06, 0.08, 0.1) + accent * 0.08) * shade + accent * 0.1 * dark;
	} else if (part < 2.5) {
		ALBEDO = vec3(1.0, 0.95, 0.85) * mix(1.0, 2.0, dark);
	} else if (part < 3.5) {
		ALBEDO = vec3(1.0, 0.05, 0.02) * mix(0.6, 1.5, dark);
	} else {
		ALBEDO = accent * mix(0.8, 1.8, dark);
	}
}
"""

# Far cars: a dot at least min_pixels wide (sized in view space, as the
# station's lamps are), pulled a little toward the camera so the ground does
# not cut it; white coming toward the camera, red going away; dark grey by
# day, lit by night, and by night from DOT_NEAR_NIGHT on.
const DOT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;
%s
uniform float dot_size = 0.8;
uniform float min_pixels = 2.0;
uniform float near_hide = 1200.0;
uniform float near_hide_night = 250.0;
uniform float far_end = 12000.0;

varying vec3 tint;

void vertex() {
	vec3 pos; vec3 left; vec3 up; vec3 forward; float night; float car;
	bool shown = place(MODELVIEW_MATRIX, INV_VIEW_MATRIX, COLOR, INSTANCE_CUSTOM, TIME, pos, left, up, forward, night, car);
	vec3 centre = pos + up;
	float depth = max(-centre.z, 0.001);
	float lit = smoothstep(0.2, 0.8, night);
	shown = shown && depth > mix(near_hide, near_hide_night, lit) && depth < far_end;
	float pixel = 2.0 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);
	float size = max(dot_size, min_pixels * pixel * depth);
	float pull = clamp((depth - max(size, 0.01 * depth)) / depth, 0.1, 1.0);
	VERTEX = shown ? (centre + vec3(VERTEX.xy * size, 0.0)) * pull : vec3(0.0);
	vec3 light = dot(forward, -centre) > 0.0 ? vec3(1.0, 0.95, 0.85) : vec3(1.0, 0.1, 0.05);
	tint = mix(vec3(0.12), light, lit);
}

void fragment() {
	ALBEDO = tint;
}
"""

static func car_material(radius: float) -> ShaderMaterial:
	return _material(CAR_SHADER % PLACE_GLSL, radius)

static func dot_material(radius: float) -> ShaderMaterial:
	var material := _material(DOT_SHADER % PLACE_GLSL, radius)
	material.set_shader_parameter("near_hide", DOT_NEAR)
	material.set_shader_parameter("near_hide_night", DOT_NEAR_NIGHT)
	material.set_shader_parameter("far_end", DOT_FAR)
	return material

static func _material(code: String, radius: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = code
	material.set_shader_parameter("ground_radius", radius)
	material.set_shader_parameter("day_share", DAY_SHARE)
	material.set_shader_parameter("night_share", NIGHT_SHARE)
	return material

# A low-poly sci-fi hover car, +Z forward, +X left, floating over the road
# (y = 0): a faceted wedge of a body, a glass canopy, a rear wing, a light
# bar across the nose and one across the tail, and a glow strip under the
# belly. Flat normals, as the buildings. UV.x tells the parts apart for the
# shader: 0 body, 1 glass, 2 headlight, 3 tail light, 4 under-glow.
const BODY_RINGS := [[-2.3, 0.8, 0.5, 1.05], [-1.7, 0.95, 0.42, 1.15], [1.0, 0.92, 0.42, 1.05], [2.35, 0.45, 0.55, 0.75]]
const CANOPY_RINGS := [[-1.3, 0.6, 1.0, 1.2], [-0.4, 0.66, 1.0, 1.55], [0.5, 0.6, 1.0, 1.45], [1.05, 0.38, 0.98, 1.08]]

static func car_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_loft(st, BODY_RINGS, 0.0)
	_loft(st, CANOPY_RINGS, 1.0)
	# Rear wing on two struts.
	_box(st, Vector3(-1.0, 1.25, -2.3), Vector3(1.0, 1.32, -1.85), 0.0)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(side * 0.7 - 0.05, 1.0, -2.2), Vector3(side * 0.7 + 0.05, 1.25, -1.95), 0.0)
	_box(st, Vector3(-0.46, 0.56, 2.3), Vector3(0.46, 0.72, 2.38), 2.0)
	_box(st, Vector3(-0.8, 0.78, -2.35), Vector3(0.8, 0.96, -2.28), 3.0)
	_box(st, Vector3(-0.55, 0.38, -1.5), Vector3(0.55, 0.42, 1.0), 4.0)
	st.index()
	return st.commit()

# Six corners round a cross-section at `z`: half width w, from `bottom` to
# `top`, widest a little under half way up.
static func _ring(z: float, w: float, bottom: float, top: float) -> Array:
	var mid := bottom + 0.45 * (top - bottom)
	return [Vector3(w, mid, z), Vector3(0.75 * w, top, z), Vector3(-0.75 * w, top, z), Vector3(-w, mid, z), Vector3(-0.8 * w, bottom, z), Vector3(0.8 * w, bottom, z)]

# Rings [z, half width, bottom, top] joined by flat quads, both ends capped.
static func _loft(st: SurfaceTool, rings: Array, part: float) -> void:
	var points := []
	var centre := Vector3.ZERO
	for r in rings:
		var ring := _ring(r[0], r[1], r[2], r[3])
		points.append(ring)
		for p in ring:
			centre += p
	centre /= rings.size() * 6.0
	for k in range(rings.size() - 1):
		for i in range(6):
			var j := (i + 1) % 6
			_face(st, [points[k][i], points[k][j], points[k + 1][j], points[k + 1][i]], centre, part)
	_face(st, points[0], centre, part)
	_face(st, points[-1], centre, part)

# A flat convex face (a fan), front side away from `centre`.
static func _face(st: SurfaceTool, corners: Array, centre: Vector3, part: float) -> void:
	var middle := Vector3.ZERO
	for c in corners:
		middle += c
	middle /= corners.size()
	for i in range(1, corners.size() - 1):
		var a: Vector3 = corners[0]
		var b: Vector3 = corners[i]
		var c: Vector3 = corners[i + 1]
		var normal := (b - a).cross(c - a)
		if normal.length() < 0.000001:
			continue
		# Godot's front faces wind clockwise seen from outside, so their
		# (b - a) x (c - a) points in.
		var outward := normal.dot(middle - centre) < 0.0
		normal = normal.normalized() * (-1.0 if outward else 1.0)
		for p in ([a, b, c] if outward else [a, c, b]):
			st.set_normal(normal)
			st.set_uv(Vector2(part, 0.0))
			st.add_vertex(p)

static func _box(st: SurfaceTool, low: Vector3, high: Vector3, part: float) -> void:
	var size := high - low
	for axis in range(3):
		for side in [0.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = 1.0 if side > 0.5 else -1.0
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = size[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = size[(axis + 2) % 3]
			var corner := low
			corner[axis] = high[axis] if side > 0.5 else low[axis]
			var quad := [corner, corner + u, corner + u + v, corner + v]
			# Clockwise seen from outside (Godot's front faces).
			var order := [0, 2, 1, 0, 3, 2] if side > 0.5 else [0, 1, 2, 0, 2, 3]
			for k in order:
				st.set_normal(normal)
				st.set_uv(Vector2(part, 0.0))
				st.add_vertex(quad[k])

static func dot_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	return quad

static func multimesh_instance(node_name: String, data: PackedFloat32Array, mesh: Mesh, material: Material, bounds: AABB) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = data.size() / FLOATS
	multimesh.buffer = data
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = bounds
	return node
