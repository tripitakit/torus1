extends RefCounted

# The docking approach guide: square gates on the straight line from the
# ship to the nearest dock's port, recomputed every frame. Far gates look
# small in perspective, so the row reads as a path into the dock.

const MAX_RANGE := 10000.0
const MAX_GATES := 20
# Metres between gates: distance / MAX_GATES, kept within these.
const SPACING := Vector2(50.0, 500.0)
const FIRST_GATE := 100.0
const GATE_SIZE := 30.0

# Distances from the ship of the gates toward a dock `distance` away: none
# past MAX_RANGE, none closer than FIRST_GATE, none at or past the dock.
static func gate_distances(distance: float) -> PackedFloat64Array:
	var gates := PackedFloat64Array()
	if distance > MAX_RANGE:
		return gates
	var spacing: float = clampf(distance / MAX_GATES, SPACING.x, SPACING.y)
	var d := FIRST_GATE
	while d < distance and gates.size() < MAX_GATES:
		gates.append(d)
		d += spacing
	return gates

# The gates' outlines as line segments (pairs of points, relative to the
# ship): GATE_SIZE squares facing along the line, their "up" from up_hint
# (the ship's own up) unless that runs along the line.
static func gate_segments(ship: Vector3, port: Vector3, up_hint: Vector3) -> PackedVector3Array:
	var segments := PackedVector3Array()
	var to_port := port - ship
	var distance := to_port.length()
	if distance <= 0.0:
		return segments
	var along := to_port / distance
	var right := along.cross(up_hint)
	if right.length() < 1e-6:
		right = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.BACK)
	right = right.normalized() * GATE_SIZE * 0.5
	var up := right.cross(along).normalized() * GATE_SIZE * 0.5
	for d in gate_distances(distance):
		var centre := along * d
		var corners := [centre - right - up, centre + right - up, centre + right + up, centre - right + up]
		for k in range(4):
			segments.append(corners[k])
			segments.append(corners[(k + 1) % 4])
	return segments
