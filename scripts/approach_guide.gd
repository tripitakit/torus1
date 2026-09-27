extends RefCounted

# The docking approach guide: square gates along a curved path from the
# ship to the nearest dock's pad, recomputed every frame. Far gates look
# small in perspective, so the row reads as a path into the dock.
#
# The path leaves along the ship's nose (the centre of the pilot's view)
# and meets the pad square on. It is worked out in the frame of the pad's
# bridge (axis = Y, pad at y = 0), where the station near the dock is round
# about the axis: the two sections either side, from half_gap on, and the
# bridge between them. It keeps SECTION_MARGIN off the sections and
# BRIDGE_MARGIN off the bridge.

const MAX_RANGE := 10000.0
const MAX_GATES := 20
# Metres between gates: length / MAX_GATES, kept within these.
const SPACING := Vector2(50.0, 500.0)
const FIRST_GATE := 100.0
const GATE_SIZE := 30.0
const SECTION_MARGIN := 300.0
const BRIDGE_MARGIN := 100.0
# Within this angle of the pad (about half its face) the path may come down
# to the pad's height.
const PAD_WINDOW := 0.05
const PATH_SAMPLES := 128
const SHOULDER_SAMPLES := 32
# Rounding of the lifts that keep the path off the station: ramps rising
# RAMP_SLOPE metres per metre of path, then running means over
# 2 * SMOOTH_REACH + 1 samples, SMOOTH_PASSES times.
const RAMP_SLOPE := 0.5
const SMOOTH_REACH := 4
const SMOOTH_PASSES := 3
# Hermite tangents of pi/2 times the half-axes draw about a quarter ellipse.
const QUARTER := PI / 2.0

# A stretch of path in the bridge's round coordinates: distance from the
# axis, angle around it (atan2(x, z)) and height along it.
class Leg:
	var radius := PackedFloat64Array()
	var angle := PackedFloat64Array()
	var height := PackedFloat64Array()

# Distances along a path `length` long of its gates: none closer than
# FIRST_GATE, none at or past the end, at most MAX_GATES.
static func gate_distances(length: float) -> PackedFloat64Array:
	var gates := PackedFloat64Array()
	var spacing: float = clampf(length / MAX_GATES, SPACING.x, SPACING.y)
	var d := FIRST_GATE
	while d < length and gates.size() < MAX_GATES:
		gates.append(d)
		d += spacing
	return gates

# The path from `ship` to `pad` in the bridge's frame, leaving along the
# unit vector `forward` and arriving along the pad's normal.
# - One smooth curve when that clears the sections.
# - Otherwise over the rim of the nearer section (SECTION_MARGIN above it
#   and short of its end), then down into the gap on a quarter ellipse.
# Where either would still touch the station, it is lifted away from the
# axis, with the lift rounded off (see _lift).
static func approach_path(ship: Vector3, forward: Vector3, pad: Vector3, section_radius: float, half_gap: float, bridge_radius: float) -> PackedVector3Array:
	var ship_radius := Vector2(ship.x, ship.z).length()
	var ship_angle := atan2(ship.x, ship.z)
	var pad_radius := Vector2(pad.x, pad.z).length()
	var pad_angle := ship_angle + wrapf(atan2(pad.x, pad.z) - ship_angle, -PI, PI)
	var outward := Vector3(sin(ship_angle), 0.0, cos(ship_angle))
	var around := Vector3(cos(ship_angle), 0.0, -sin(ship_angle))
	var start := Vector3(ship_radius, ship_angle, ship.y)
	var shelf := section_radius + SECTION_MARGIN
	var gap := half_gap - SECTION_MARGIN
	var reach := maxf(ship.distance_to(pad), (ship_radius + pad_radius) * 0.5 * absf(pad_angle - ship_angle))
	var start_rate := Vector3(forward.dot(outward), forward.dot(around) / maxf(ship_radius, 1.0), forward.y) * reach
	var leg := _leg(start, start_rate, Vector3(pad_radius, pad_angle, pad.y), Vector3(-reach, 0.0, 0.0), PATH_SAMPLES)
	var over_sections := false
	for i in range(leg.radius.size()):
		if absf(leg.height[i]) > gap and leg.radius[i] < shelf:
			over_sections = true
	if over_sections:
		var side := signf(ship.y) if ship.y != 0.0 else 1.0
		var rim := Vector3(shelf, pad_angle, side * gap)
		var rim_reach := maxf(Vector2(ship_radius - shelf, ship.y - rim.z).length(), (ship_radius + shelf) * 0.5 * absf(pad_angle - ship_angle))
		leg = _leg(start, start_rate, rim, Vector3(0.0, 0.0, -side * rim_reach), PATH_SAMPLES)
		var shoulder := _leg(rim, Vector3(0.0, 0.0, -side * gap * QUARTER), Vector3(pad_radius, pad_angle, pad.y), Vector3(-(shelf - pad_radius) * QUARTER, 0.0, 0.0), SHOULDER_SAMPLES)
		for i in range(1, shoulder.radius.size()):
			leg.radius.append(shoulder.radius[i])
			leg.angle.append(shoulder.angle[i])
			leg.height.append(shoulder.height[i])
	_lift(leg, pad_angle, pad_radius, shelf, gap, bridge_radius + BRIDGE_MARGIN)
	var path := PackedVector3Array()
	for i in range(leg.radius.size()):
		path.append(Vector3(sin(leg.angle[i]) * leg.radius[i], leg.height[i], cos(leg.angle[i]) * leg.radius[i]))
	path[0] = ship
	path[path.size() - 1] = pad
	return path

static func _hermite(t: float, p0: float, m0: float, p1: float, m1: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1

# `samples` + 1 points from `start` to `end` (radius, angle, height), with
# the given rates of change at either end.
static func _leg(start: Vector3, start_rate: Vector3, end: Vector3, end_rate: Vector3, samples: int) -> Leg:
	var leg := Leg.new()
	for i in range(samples + 1):
		var t := float(i) / samples
		leg.radius.append(_hermite(t, start.x, start_rate.x, end.x, end_rate.x))
		leg.angle.append(_hermite(t, start.y, start_rate.y, end.y, end_rate.y))
		leg.height.append(_hermite(t, start.z, start_rate.z, end.z, end_rate.z))
	return leg

# Raises the samples that come closer to the axis than the station allows:
# `shelf` past `gap` either side (the sections), the pad's own radius over
# the pad, `bridge_floor` elsewhere. The lift slopes off either side and is
# averaged, so the path rounds what it clears; near the ship and the pad it
# grows from nothing, so the ends stay put.
static func _lift(leg: Leg, pad_angle: float, pad_radius: float, shelf: float, gap: float, bridge_floor: float) -> void:
	var n := leg.radius.size() - 1
	var need := PackedFloat64Array()
	need.resize(n + 1)
	var length := 0.0
	for i in range(1, n + 1):
		length += Vector2(leg.radius[i] - leg.radius[i - 1], leg.height[i] - leg.height[i - 1]).length() + absf(leg.angle[i] - leg.angle[i - 1]) * leg.radius[i]
		var floor_radius := bridge_floor
		if absf(leg.height[i]) > gap:
			floor_radius = shelf
		elif absf(leg.angle[i] - pad_angle) < PAD_WINDOW:
			floor_radius = pad_radius
		if i < n:
			need[i] = maxf(0.0, floor_radius - leg.radius[i])
	var step := RAMP_SLOPE * length / n
	var lift := need.duplicate()
	for i in range(1, n + 1):
		lift[i] = maxf(lift[i], lift[i - 1] - step)
	for i in range(n - 1, -1, -1):
		lift[i] = maxf(lift[i], lift[i + 1] - step)
	lift[0] = 0.0
	lift[n] = 0.0
	for p in range(SMOOTH_PASSES):
		var next := lift.duplicate()
		var total := 0.0
		for k in range(0, mini(n, SMOOTH_REACH) + 1):
			total += lift[k]
		for i in range(1, n):
			if i + SMOOTH_REACH <= n:
				total += lift[i + SMOOTH_REACH]
			if i - SMOOTH_REACH - 1 >= 0:
				total -= lift[i - SMOOTH_REACH - 1]
			var count := mini(n, i + SMOOTH_REACH) - maxi(0, i - SMOOTH_REACH) + 1
			next[i] = maxf(need[i], minf(total / count, mini(i, n - i) * step))
		lift = next
	for i in range(n + 1):
		leg.radius[i] += lift[i]

# The gates' outlines along `path` as line segments (pairs of points, in the
# path's frame): GATE_SIZE squares facing along the path where they sit,
# their "up" from up_hint (the ship's own up) unless that runs along it.
static func gates_along(path: PackedVector3Array, up_hint: Vector3) -> PackedVector3Array:
	var segments := PackedVector3Array()
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var i := 1
	var start := 0.0
	for d in gate_distances(length):
		while i < path.size() - 1 and start + path[i - 1].distance_to(path[i]) < d:
			start += path[i - 1].distance_to(path[i])
			i += 1
		var leg := path[i] - path[i - 1]
		if leg.length() <= 0.0:
			continue
		var along := leg.normalized()
		_append_square(segments, path[i - 1] + along * (d - start), along, up_hint)
	return segments

static func _append_square(segments: PackedVector3Array, centre: Vector3, along: Vector3, up_hint: Vector3) -> void:
	var right := along.cross(up_hint)
	if right.length() < 1e-6:
		right = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.BACK)
	right = right.normalized() * GATE_SIZE * 0.5
	var up := right.cross(along).normalized() * GATE_SIZE * 0.5
	var corners := [centre - right - up, centre + right - up, centre + right + up, centre - right + up]
	for k in range(4):
		segments.append(corners[k])
		segments.append(corners[(k + 1) % 4])
