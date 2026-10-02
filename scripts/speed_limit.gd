extends RefCounted

# The ship's speed limit, by zone, relative to its frame (the ring's, or the
# moon's below MoonOrbit.ATTACH_ALTITUDE): NEAR_LIMIT within NEAR_RANGE of
# Torus1's surface or of a gate, MOON_LIMIT in the moon's frame, OPEN_LIMIT
# elsewhere; the slowest that applies wins. At the limit the thrust adds no
# more speed (it can still turn the motion); over it (coming into a slower
# zone) the flight computer brakes the ship down to it.

const NEAR_LIMIT := 500.0
const MOON_LIMIT := 800.0
const OPEN_LIMIT := 3000.0
const NEAR_RANGE := 20000.0
# Over the limit by more than this counts as braking down to it (HUD).
const BRAKING_MARGIN := 1.0

# The limit `ring_distance` from Torus1's surface, `gate_distance` from the
# nearest gate, in the moon's frame or not.
static func limit(ring_distance: float, gate_distance: float, in_moon_frame: bool) -> float:
	if ring_distance < NEAR_RANGE or gate_distance < NEAR_RANGE:
		return NEAR_LIMIT
	if in_moon_frame:
		return MOON_LIMIT
	return OPEN_LIMIT

# Distance from the ring's surface: the tube of `section_radius` round the
# circle of `ring_radius` about `axis` (through the origin of `offset`, the
# point's offset from the planet's centre).
static func ring_distance(offset: Vector3, axis: Vector3, ring_radius: float, section_radius: float) -> float:
	var along := offset.dot(axis)
	var across := (offset - axis * along).length()
	return Vector2(across - ring_radius, along).length() - section_radius

# The velocity after a tick, `velocity` (with the tick's thrust and pulls),
# the speed before it `speed_before`: held to `limit`; over it, brought down
# by up to `brake` m/s2, never below the limit.
static func cap(velocity: Vector3, speed_before: float, limit: float, brake: float, delta: float) -> Vector3:
	var speed := velocity.length()
	var most := limit
	if speed_before > limit:
		most = maxf(limit, speed_before - brake * delta)
	if speed <= most:
		return velocity
	return velocity * (most / speed)

static func braking(speed: float, limit: float) -> bool:
	return speed > limit + BRAKING_MARGIN
