extends RefCounted

# The void-cruiser flies in the frame of the orbiting ring: the ring stays
# still in the scene and the space around it turns. A craft in this frame
# feels the planet's gravity, a centrifugal push away from the ring's axis
# and a Coriolis pull across its motion. Physically this is the ring
# orbiting at ~840 m/s, seen from the ring.

const MOON_GM := 4.9048e12

# Angular velocity of a circular orbit of radius `orbit_radius`.
static func orbit_angular_velocity(gm: float, orbit_radius: float) -> float:
	return sqrt(gm / pow(orbit_radius, 3.0))

# `offset`: position minus the planet centre. `velocity`: relative to the
# turning frame. `omega`: the frame's rotation (axis times angular speed).
# `body_radius`: the planet's radius. The planet has no collision, so a ship
# can fly through it: inside, the pull is a uniform sphere's, falling to
# zero at the centre, instead of 1/r^2 blowing up there.
static func frame_acceleration(offset: Vector3, velocity: Vector3, gm: float, omega: Vector3, body_radius := 0.0) -> Vector3:
	var reach := maxf(offset.length(), body_radius)
	var gravity := Vector3.ZERO if reach <= 0.0 else -offset * (gm / (reach * reach * reach))
	var centrifugal := -omega.cross(omega.cross(offset))
	var coriolis := -2.0 * omega.cross(velocity)
	return gravity + centrifugal + coriolis

# Velocity relative to the stars.
static func inertial_velocity(offset: Vector3, velocity: Vector3, omega: Vector3) -> Vector3:
	return velocity + omega.cross(offset)

# Kepler orbit from position and velocity relative to the stars. Distances
# are from the planet centre; apoapsis is INF for an open orbit.
static func orbit_of(offset: Vector3, inertial: Vector3, gm: float) -> Dictionary:
	var r := offset.length()
	if r <= 0.0:
		# Right at the centre (inside the planet): no orbit to speak of.
		return {"periapsis": 0.0, "apoapsis": 0.0, "escape": false, "eccentricity": Vector3.ZERO, "semi_latus": 0.0, "normal": Vector3.UP}
	var h := offset.cross(inertial)
	var e_vec := inertial.cross(h) / gm - offset / r
	var e := e_vec.length()
	# Semi-latus rectum: works for every conic, including a straight fall (0).
	var p := h.length_squared() / gm
	var normal := h.normalized() if h.length() > 0.0 else _any_perpendicular(offset)
	return {
		"periapsis": p / (1.0 + e),
		"apoapsis": INF if e >= 1.0 else p / (1.0 - e),
		"escape": e >= 1.0,
		"eccentricity": e_vec,
		"semi_latus": p,
		"normal": normal,
	}

# `count` points along the orbit around the planet centre, by true anomaly.
# A closed orbit goes all the way round (first point = last point); an open
# one stops where its radius reaches `max_radius`.
static func orbit_points(orbit: Dictionary, count: int, max_radius: float) -> PackedVector3Array:
	var e_vec: Vector3 = orbit.eccentricity
	var e := e_vec.length()
	var p: float = orbit.semi_latus
	var normal: Vector3 = orbit.normal
	var toward_periapsis: Vector3 = e_vec / e if e > 1e-9 else _any_perpendicular(normal)
	var along_motion := normal.cross(toward_periapsis)
	var limit := PI
	if e >= 1.0:
		# Where the radius reaches max_radius. A straight fall (p = 0, e = 1)
		# would reach nu = PI, where r = 0 / 0: stop just short of it.
		limit = minf(acos(clampf((p / max_radius - 1.0) / e, -1.0, 1.0)), PI - 1e-6)
	var points := PackedVector3Array()
	for k in range(count):
		var nu: float = -limit + 2.0 * limit * k / (count - 1)
		var r: float = p / (1.0 + e * cos(nu))
		points.append((toward_periapsis * cos(nu) + along_motion * sin(nu)) * r)
	return points

static func _any_perpendicular(v: Vector3) -> Vector3:
	var side := v.cross(Vector3.UP)
	if side.length() < 1e-9:
		side = v.cross(Vector3.RIGHT)
	if side.length() < 1e-9:
		return Vector3.RIGHT
	return side.normalized()
