extends RefCounted

# The train on the axis spine: a girder SPINE_RADIUS from the axis, at
# SPINE_ANGLE (the middle of lot column STATION_COLUMN, so a pylon never
# stands on a road), unbroken through sections and bridges, a track on each
# flank. Two stations a section, each with a pylon down to the ground and
# its lifts.
#
# Timetable: a period runs from one bridge's centre to the next (section +
# bridge). With two stops a period, both at least BRAKE_DISTANCE clear of
# the walls, crossing a period takes the same time everywhere: P / v plus
# what the stops cost. Every period holds one train each way at all times;
# all trains one way cross the bridge centres at the same moment, at
# cruising speed, and the next section's train carries on from the same
# point: to the eye it is the same train. The other way is half a period
# later.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

enum { AHEAD, BACK }

const SPEED := 100.0
const ACCEL := 2.5
const DWELL := 20.0
const SPINE_RADIUS := 120.0
const STATION_COLUMN := 36
# Lots along in which each station may stand (first half, second half), and
# where it goes when no town is there (a third and two thirds of the way).
const FIRST_LOTS := Vector2i(8, 35)
const SECOND_LOTS := Vector2i(44, 71)

static func spine_angle() -> float:
	return (STATION_COLUMN + 0.5) / SectionPlanScript.LOTS_AROUND * TAU

# The two station lots (along) under the spine: in each half the city,
# else a town, nearest a third (two thirds) of the way; else that lot.
static func station_lots(plan) -> PackedInt32Array:
	var thirds := Vector2i(SectionPlanScript.LOTS_ALONG / 3, SectionPlanScript.LOTS_ALONG * 2 / 3)
	return PackedInt32Array([_pick(plan, FIRST_LOTS, thirds.x), _pick(plan, SECOND_LOTS, thirds.y)])

static func _pick(plan, lots: Vector2i, target: int) -> int:
	for zone in [SectionPlanScript.Zone.CITY, SectionPlanScript.Zone.TOWN]:
		var best := -1
		for along in range(lots.x, lots.y + 1):
			if plan.zone_at(STATION_COLUMN, along) == zone and (best < 0 or absi(along - target) < absi(best - target)):
				best = along
		if best >= 0:
			return best
	return target

# The stations' plan z (lot centres).
static func station_z(plan) -> Array:
	var zs := []
	for along in station_lots(plan):
		zs.append((along + 0.5) * plan.lot_length)
	return zs

static func period_time(period: float) -> float:
	return period / SPEED + 2.0 * SPEED / ACCEL + 2.0 * DWELL

static func brake_distance() -> float:
	return SPEED * SPEED / (2.0 * ACCEL)

# Where the stops fall in a period, in metres along the way from its first
# bridge's centre: ahead runs toward -z (from the section's +z end), back
# toward +z.
static func stops(way: int, station_zs: Array, length: float, bridge: float) -> Array:
	var found := []
	for z: float in station_zs:
		found.append(bridge * 0.5 + (length - z if way == AHEAD else z))
	found.sort()
	return found

# Metres along the period at `tau` seconds into it: cruise, brake, wait,
# pull away, at each stop in turn.
static func progress(tau: float, stop_points: Array, period: float) -> float:
	var brake := brake_distance()
	var ramp := SPEED / ACCEL
	var at := 0.0
	var t := tau
	for s: float in stop_points:
		var cruise := (s - brake - at) / SPEED
		if t < cruise:
			return at + SPEED * t
		t -= cruise
		if t < ramp:
			return s - brake + SPEED * t - 0.5 * ACCEL * t * t
		t -= ramp
		if t < DWELL:
			return s
		t -= DWELL
		if t < ramp:
			return s + 0.5 * ACCEL * t * t
		t -= ramp
		at = s + brake
	return minf(at + SPEED * t, period)

# The train's z in its section's frame, `u` metres into the period.
static func train_node_z(way: int, u: float, length: float, bridge: float) -> float:
	var start := (length + bridge) * 0.5
	return start - u if way == AHEAD else -start + u

# Seconds into the current period at game time t.
static func train_tau(t: float, way: int, total: float) -> float:
	return fposmod(t + (0.0 if way == AHEAD else total * 0.5), total)

# --- Shapes -----------------------------------------------------------------
#
# Every shape is low-poly with flat normals (RoadTraffic's helpers) and its
# parts told apart by UV.x for STRUCTURE_SHADER: 0 hull, 1 dark glass, 2
# accent glow, 3 windows, 4 white light, 5 red light.

const RoadTraffic = preload("res://scripts/road_traffic.gd")

# The girder: half width SPINE_HALF_WIDTH, SPINE_HALF_HEIGHT each way of its
# centre line; in its frame x across, y toward the axis, z along.
const SPINE_HALF_WIDTH := 9.0
const SPINE_HALF_HEIGHT := 4.0
# The shelves the trains ride on, each flank, and the trains' centre lines.
const SHELF := Vector2(9.0, 17.0)
const TRACK_OFFSET := 13.0
const TRAIN_HALF_HEIGHT := 2.3
const TRAIN_CARS := 6
const CAR_LENGTH := 24.0
const CAR_GAP := 1.2
const TRAIN_SIZE := Vector3(4.8, 4.6, TRAIN_CARS * (CAR_LENGTH + CAR_GAP))
const PLATFORM_SIZE := Vector3(50.0, 3.0, 200.0)
const PYLON_RADIUS := 8.0
const HALL_RADIUS := 25.0
const HALL_HEIGHT := 12.0
const LIFT_SIZE := Vector3(6.0, 8.0, 6.0)
const LIFT_SPEED := 40.0
const LIFT_ACCEL := 4.0
const LIFT_WAIT := 10.0

# The platform's underside, where the pylon ends (radius from the axis).
static func platform_radius() -> float:
	return SPINE_RADIUS + SPINE_HALF_HEIGHT + 0.5 + PLATFORM_SIZE.y

# A piece of spine one metre long (scale its node's z to the length).
static func spine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := SPINE_HALF_WIDTH
	var h := SPINE_HALF_HEIGHT
	# Hexagonal girder; RoadTraffic._ring puts y "up" from bottom to top.
	RoadTraffic._loft(st, [[-0.5, w, -h, h], [0.5, w, -h, h]], 0.0)
	for side: float in [-1.0, 1.0]:
		var inner := SHELF.x * side
		var outer := SHELF.y * side
		RoadTraffic._box(st, Vector3(minf(inner, outer), -TRAIN_HALF_HEIGHT - 0.7, -0.5), Vector3(maxf(inner, outer), -TRAIN_HALF_HEIGHT, 0.5), 0.0)
		# Guide light along the shelf's edge and along the girder's top.
		RoadTraffic._box(st, Vector3(outer - 0.2, -TRAIN_HALF_HEIGHT - 0.6, -0.5), Vector3(outer + 0.2, -TRAIN_HALF_HEIGHT - 0.1, 0.5), 2.0)
		RoadTraffic._box(st, Vector3(side * 5.0 - 0.25, h - 0.1, -0.5), Vector3(side * 5.0 + 0.25, h + 0.25, 0.5), 2.0)
	st.index()
	return st.commit()

# A six-car train, +Z forward, y toward the axis, centred on its frame.
static func train_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := TRAIN_SIZE.x * 0.5
	var h := TRAIN_HALF_HEIGHT
	var start := -TRAIN_SIZE.z * 0.5
	for k in range(TRAIN_CARS):
		var z0 := start + k * (CAR_LENGTH + CAR_GAP) + CAR_GAP * 0.5
		var z1 := z0 + CAR_LENGTH
		var rings := [[z0, w, -h, h], [z1, w, -h, h]]
		if k == 0:
			rings = [[z0, 0.9, -h * 0.6, 0.2], [z0 + 5.0, w, -h, h], [z1, w, -h, h]]
		elif k == TRAIN_CARS - 1:
			rings = [[z0, w, -h, h], [z1 - 6.0, w, -h, h], [z1, 0.8, -h * 0.5, 0.0]]
		RoadTraffic._loft(st, rings, 0.0)
		var wz0 := z0 + (5.5 if k == 0 else 1.5)
		var wz1 := z1 - (6.5 if k == TRAIN_CARS - 1 else 1.5)
		for side: float in [-1.0, 1.0]:
			RoadTraffic._box(st, Vector3(minf(side * 2.12, side * 2.32), 0.3, wz0), Vector3(maxf(side * 2.12, side * 2.32), 1.2, wz1), 3.0)
			RoadTraffic._box(st, Vector3(minf(side * 2.02, side * 2.22), -1.65, z0 + 1.0), Vector3(maxf(side * 2.02, side * 2.22), -1.4, z1 - 1.0), 2.0)
	var nose := start + TRAIN_SIZE.z - CAR_GAP * 0.5
	RoadTraffic._box(st, Vector3(-0.6, -0.9, nose - 0.2), Vector3(0.6, -0.4, nose + 0.15), 4.0)
	RoadTraffic._box(st, Vector3(-0.7, -1.0, start + CAR_GAP * 0.5 - 0.15), Vector3(0.7, -0.4, start + CAR_GAP * 0.5 + 0.2), 5.0)
	st.index()
	return st.commit()

# A hexagonal prism standing on y = 0, `height` tall (scale its node's y).
static func prism_mesh(radius: float, height: float, part: float, glow_band: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(st, radius, 0.0, height, part)
	if glow_band:
		_prism(st, radius + 0.2, height * 0.8, height * 0.85, 2.0)
	st.index()
	return st.commit()

static func _prism(st: SurfaceTool, radius: float, y0: float, y1: float, part: float) -> void:
	var low := []
	var high := []
	for i in range(6):
		var a := TAU * (i + 0.5) / 6.0
		low.append(Vector3(cos(a) * radius, y0, sin(a) * radius))
		high.append(Vector3(cos(a) * radius, y1, sin(a) * radius))
	var centre := Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	for i in range(6):
		var j := (i + 1) % 6
		RoadTraffic._face(st, [low[i], low[j], high[j], high[i]], centre, part)
	RoadTraffic._face(st, low, centre, part)
	RoadTraffic._face(st, high, centre, part)

# A lift cabin: a box with a glass front, centred on its frame.
static func lift_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LIFT_SIZE * 0.5
	RoadTraffic._box(st, -half, half, 0.0)
	RoadTraffic._box(st, Vector3(-half.x * 0.7, -half.y * 0.6, half.z), Vector3(half.x * 0.7, half.y * 0.7, half.z + 0.1), 3.0)
	RoadTraffic._box(st, Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y + 0.3, half.z), 2.0)
	st.index()
	return st.commit()

# Unshaded, lit from the hour where the vertex is (interior_hour.gdshaderinc)
# as the cars are: a 20 km girder would meet 20 suns (8 at most, one pass
# each). Faces toward the axis (where the suns are) are lighter.
const STRUCTURE_SHADER := """
shader_type spatial;
render_mode unshaded;

#include "res://shaders/interior_hour.gdshaderinc"

uniform vec3 hull_color : source_color = vec3(0.75, 0.77, 0.8);
uniform vec3 accent : source_color = vec3(0.3, 0.9, 1.0);

varying float part;
varying float shade;
varying float night;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float hour = interior_hour(world.z);
	night = interior_night(hour);
	vec3 toward_axis = -normalize(vec3(world.xy, 0.0) + vec3(0.0001, 0.0, 0.0));
	shade = mix(1.0, 0.3, night) * (0.6 + 0.4 * max(dot(normal, toward_axis), 0.0));
	part = UV.x;
}

void fragment() {
	if (part < 0.5) {
		ALBEDO = hull_color * shade;
	} else if (part < 1.5) {
		ALBEDO = vec3(0.06, 0.08, 0.1) * shade;
	} else if (part < 2.5) {
		ALBEDO = accent * mix(0.8, 1.6, night);
	} else if (part < 3.5) {
		ALBEDO = mix(vec3(0.08, 0.1, 0.12) * shade, vec3(1.0, 0.85, 0.6) * 1.4, smoothstep(0.1, 0.6, night));
	} else if (part < 4.5) {
		ALBEDO = vec3(1.0, 0.95, 0.85) * mix(1.0, 2.0, night);
	} else {
		ALBEDO = vec3(1.0, 0.05, 0.02) * mix(0.6, 1.5, night);
	}
}
"""

static func structure_material(hull: Color, accent: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = STRUCTURE_SHADER
	material.set_shader_parameter("hull_color", hull)
	material.set_shader_parameter("accent", accent)
	return material

# Where a lift cabin is, metres up from the ground end of a `length` run, at
# time t: up, wait, down, wait, smooth starts and stops. `phase` 0 or 0.5.
static func lift_height(t: float, length: float, phase: float) -> float:
	var ramp := LIFT_SPEED / LIFT_ACCEL
	var ride := length / LIFT_SPEED + ramp
	var cycle := 2.0 * (ride + LIFT_WAIT)
	var tau := fposmod(t + phase * cycle, cycle)
	if tau < ride:
		return _ride(tau, length)
	tau -= ride
	if tau < LIFT_WAIT:
		return length
	tau -= LIFT_WAIT
	if tau < ride:
		return length - _ride(tau, length)
	return 0.0

# Metres covered `t` seconds into a ride of `length`: ramp up, cruise, ramp down.
static func _ride(t: float, length: float) -> float:
	var ramp := LIFT_SPEED / LIFT_ACCEL
	var ramp_distance := 0.5 * LIFT_SPEED * ramp
	var ride := length / LIFT_SPEED + ramp
	if t < ramp:
		return 0.5 * LIFT_ACCEL * t * t
	if t > ride - ramp:
		var left := ride - t
		return length - 0.5 * LIFT_ACCEL * left * left
	return ramp_distance + LIFT_SPEED * (t - ramp)

# A station platform, centred on its frame (the spine's axes).
static func platform_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PLATFORM_SIZE * 0.5
	RoadTraffic._box(st, -half, half, 0.0)
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * half.x - 0.3, half.y - 0.6, -half.z), Vector3(side * half.x + 0.3, half.y, half.z), 2.0)
	st.index()
	return st.commit()

# The frame of something on the spine's line at `angle`, `radius` from the
# axis: x round, y toward the axis, z along.
static func spine_frame(angle: float, radius: float, z: float) -> Transform3D:
	var outward := Vector3(cos(angle), sin(angle), 0.0)
	var up := -outward
	var forward := Vector3(0.0, 0.0, 1.0)
	return Transform3D(Basis(up.cross(forward), up, forward), outward * radius + Vector3(0.0, 0.0, z))

# The train going `way` with its centre `z` along its section's frame: on
# its own flank of the spine, facing the way it goes.
static func train_transform(way: int, z: float) -> Transform3D:
	var frame := spine_frame(spine_angle(), SPINE_RADIUS, z)
	var side: float = 1.0 if way == AHEAD else -1.0
	var forward := Vector3(0.0, 0.0, -1.0 if way == AHEAD else 1.0)
	var up := frame.basis.y
	return Transform3D(Basis(up.cross(forward), up, forward), frame.origin + frame.basis.x * TRACK_OFFSET * side)

# Drops the buildings standing in the station lots from `groups` (chunk ->
# building indices, as SectionPlan.group_buildings_by_chunk gives them).
static func drop_station_buildings(plan, groups: Dictionary) -> void:
	var lots := []
	for along in station_lots(plan):
		lots.append(plan.lot_index(STATION_COLUMN, along))
	for key in groups.keys():
		groups[key] = (groups[key] as Array).filter(func(b: int) -> bool: return not lots.has(plan.building_lot[b]))
		if (groups[key] as Array).is_empty():
			groups.erase(key)
