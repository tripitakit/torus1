extends RefCounted

# The navball's frame and the ship's attitude in it. The reference is the
# ring's plane: up = the ring's axis, east = away from the planet within
# that plane, north = up x east, the way the ring turns there (prograde).

# Columns (east, up, -north).
static func ring_reference(where: Vector3, planet_center: Vector3, axis: Vector3) -> Basis:
	var up := axis.normalized()
	var out := where - planet_center
	var east := out - up * out.dot(up)
	if east.length() < 1e-6:
		# On the axis east is undefined: any direction square to it will do.
		east = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.BACK)
	east = east.normalized()
	var north := up.cross(east)
	return Basis(east, up, -north)

# Maps a point of the navball as its camera sees it (+z toward the camera,
# +x right, +y up) to the reference direction it shows (+x east, +y up,
# -z north): the centre is where the nose points, right is the ship's right,
# up its dorsal side.
static func navball_matrix(ship_basis: Basis, reference: Basis) -> Basis:
	return reference.inverse() * ship_basis * Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, -1.0))
