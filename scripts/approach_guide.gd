extends RefCounted

# The docking approach guide: square gates along a path from the ship to the
# nearest dock's port, recomputed every frame. Far gates look small in
# perspective, so the row reads as a path into the dock.
#
# The path keeps clear of the two sections either side of the bridge: it
# ends with a straight leg along the pad's normal, from ENTRY_MARGIN past
# the sections' radius down to the pad, and curves around the bridge's axis
# before that.

const MAX_RANGE := 10000.0
const MAX_GATES := 20
# Metres between gates: length / MAX_GATES, kept within these.
const SPACING := Vector2(50.0, 500.0)
const FIRST_GATE := 100.0
const GATE_SIZE := 30.0
# How far past the sections' radius the last, straight leg begins.
const ENTRY_MARGIN := 300.0
const CURVE_SAMPLES := 64

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

# The path from `ship` to `pad`, both in the bridge's frame (axis = Y, pad
# at y = 0). The sections begin `half_gap` either side of the pad and have
# `section_radius`.
# - Inside the gap and the entry radius: a straight line to the pad.
# - Elsewhere: a curve to the entry point (on the pad's normal, ENTRY_MARGIN
#   past the sections), then straight to the pad. Along the curve the
#   distance from the axis goes steadily from the ship's to the entry's, so
#   it never dips under the smaller of the two; the angle around the axis
#   and the height along it settle first, so the curve meets the last leg
#   without a kink.
static func approach_path(ship: Vector3, pad: Vector3, section_radius: float, half_gap: float) -> PackedVector3Array:
	var entry_radius := section_radius + ENTRY_MARGIN
	var ship_radius := Vector2(ship.x, ship.z).length()
	if absf(ship.y) < half_gap and ship_radius < entry_radius:
		return PackedVector3Array([ship, pad])
	var path := PackedVector3Array()
	var ship_angle := atan2(ship.x, ship.z)
	var pad_angle := atan2(pad.x, pad.z)
	var turn := wrapf(pad_angle - ship_angle, -PI, PI)
	for i in range(CURVE_SAMPLES + 1):
		var t := float(i) / CURVE_SAMPLES
		var settle := 1.0 - pow(1.0 - t, 3.0)
		var radius := lerpf(ship_radius, entry_radius, t)
		var angle := ship_angle + turn * settle
		path.append(Vector3(sin(angle) * radius, lerpf(ship.y, pad.y, settle), cos(angle) * radius))
	path[0] = ship
	path.append(pad)
	return path

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
