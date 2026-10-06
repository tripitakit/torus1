extends RefCounted

# The ship's speed limit, relative to its frame (the ring's, or the moon's
# below MoonOrbit.ATTACH_ALTITUDE). Slow zones: NEAR_LIMIT within NEAR_RANGE
# of Torus1's surface or of a gate, MOON_LOW below MOON_LOW_ALTITUDE over the
# moon. Each is announced from afar by a braking curve: the speed from which
# SAFE_BRAKE (a third of the ship's brake) still gets down to the zone's limit
# by the zone. On top: MOON_TOP in the moon's frame, OPEN_LIMIT elsewhere. The
# slowest that applies wins. At the limit the thrust adds no more speed (it
# can still turn the motion); over it the flight computer brakes the ship
# down to it.

const NEAR_LIMIT := 1000.0
const NEAR_RANGE := 20000.0
const MOON_LOW := 800.0
const MOON_LOW_ALTITUDE := 2000.0
const MOON_TOP := 15000.0
const OPEN_LIMIT := 50000.0
const SAFE_BRAKE := 500.0
# Over the limit by more than this counts as braking down to it (HUD).
const BRAKING_MARGIN := 1.0

# The limit `ring_distance` from Torus1's surface, `gate_distance` from the
# nearest gate, `moon_altitude` over the moon's ground, in the moon's frame
# or not.
static func limit(ring_distance: float, gate_distance: float, in_moon_frame: bool, moon_altitude: float = INF) -> float:
	var most := MOON_TOP if in_moon_frame else OPEN_LIMIT
	var near := minf(ring_distance, gate_distance)
	most = minf(most, _curve(NEAR_LIMIT, near - NEAR_RANGE))
	most = minf(most, _curve(MOON_LOW, moon_altitude - MOON_LOW_ALTITUDE))
	return most

# The speed `beyond` metres before a zone limited to `low`, from which
# SAFE_BRAKE still gets down to `low` by it (inside it: `low`).
static func _curve(low: float, beyond: float) -> float:
	if beyond <= 0.0:
		return low
	if is_inf(beyond):
		return INF
	return sqrt(low * low + 2.0 * SAFE_BRAKE * beyond)

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
