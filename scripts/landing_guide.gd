extends RefCounted

# The landing guide near Base Selene: the nearest pad, and square gates
# stacked level over it with a line from the ship to the top one.

const GUIDE_RANGE := 20000.0
const GATE_HEIGHTS := [50.0, 100.0, 200.0, 400.0]
const GATE_SIZE := 70.0

# Index of the pad (top-centre transforms) nearest to `ship`.
static func target_pad(ship: Vector3, pads: Array) -> int:
	var best := 0
	for i in range(1, pads.size()):
		if ship.distance_to((pads[i] as Transform3D).origin) < ship.distance_to((pads[best] as Transform3D).origin):
			best = i
	return best

# Line segments relative to `ship`: a square GATE_SIZE wide, level with the
# pad, at each of GATE_HEIGHTS over its top; then the ship to the top gate.
static func gate_segments(pad: Transform3D, ship: Vector3) -> PackedVector3Array:
	var up := pad.basis.y.normalized()
	var a := pad.basis.x.normalized() * GATE_SIZE * 0.5
	var b := pad.basis.z.normalized() * GATE_SIZE * 0.5
	var segments := PackedVector3Array()
	for height: float in GATE_HEIGHTS:
		var centre: Vector3 = pad.origin + up * height - ship
		var corners := [centre + a + b, centre + a - b, centre - a - b, centre - a + b]
		for k in range(4):
			segments.append(corners[k])
			segments.append(corners[(k + 1) % 4])
	segments.append(Vector3.ZERO)
	segments.append(pad.origin + up * GATE_HEIGHTS[-1] - ship)
	return segments
