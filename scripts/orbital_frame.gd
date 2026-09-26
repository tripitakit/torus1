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
