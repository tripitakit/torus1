extends RefCounted

# The moon: a tidally locked body on a circular orbit about the planet, in
# the planet's orbital plane (axis = the planet's Y). Seen from the ring's
# turning frame it is a rigid body turning about the planet's axis at
# relative_rate(); its own frame turns at moon_rate().

const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

const ORBIT_RADIUS := 2.0e7
const RADIUS := 250000.0
# 0.1 g at the surface: 0.0995 * 9.80665 * RADIUS^2.
const GM := 6.1e10
# The ship flies in the moon's frame below ATTACH_ALTITUDE and leaves it
# above DETACH_ALTITUDE (no flicker across the boundary).
const ATTACH_ALTITUDE := 30000.0
const DETACH_ALTITUDE := 32000.0
# At the start: Base Selene in daylight (the scene's sun shines toward -Z)
# and the moon nearly full, about 30 degrees left of the ship's nose, clear
# of the planet's disc.
const START_ANGLE := 13.0 * PI / 18.0  # 130 degrees
# Base Selene in Plato, as Moonbase Alpha: latitude and longitude in degrees
# (longitude 0 under the planet, the moon's local -X; east +Z; north +Y).
const BASE_LATITUDE := 51.6
const BASE_LONGITUDE := -9.4
# Base Selene's HUD marker shows only this close to the moon's centre: the
# moon about 6 degrees wide, Torus1 (about 13,000 km off) well outside.
const MARKER_RANGE := 5.0e6

# Whether a ship at `offset_from_moon` (from the moon's centre) sees Base
# Selene's HUD marker.
static func marker_in_range(offset_from_moon: Vector3) -> bool:
	return offset_from_moon.length() < MARKER_RANGE

# The moon-local direction of (latitude, longitude) degrees.
static func direction_of(latitude: float, longitude: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var lon := deg_to_rad(longitude)
	return Vector3(-cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))

static func base_direction() -> Vector3:
	return direction_of(BASE_LATITUDE, BASE_LONGITUDE)

static func moon_rate(planet_gm: float) -> float:
	return OrbitalFrame.orbit_angular_velocity(planet_gm, ORBIT_RADIUS)

static func relative_rate(planet_gm: float, ring_radius: float) -> float:
	return moon_rate(planet_gm) - OrbitalFrame.orbit_angular_velocity(planet_gm, ring_radius)

# The moon's orientation at orbit angle `angle`: its local -X faces the
# planet.
static func moon_basis(angle: float) -> Basis:
	return Basis(Vector3.UP, angle)

# The moon's centre from the planet's centre, in the planet's frame.
static func centre_offset(angle: float) -> Vector3:
	return moon_basis(angle) * Vector3(ORBIT_RADIUS, 0.0, 0.0)

# A turn by `angle` about `axis` through `pivot`.
static func spin(axis: Vector3, angle: float, pivot: Vector3) -> Transform3D:
	var turn := Basis(axis.normalized(), angle)
	return Transform3D(turn, pivot - turn * pivot)

# Velocities of the same motion in the moon's frame and the ring's: the two
# frames turn about the planet's axis `rel_rate` apart.
static func to_ring_velocity(moon_velocity: Vector3, offset_from_planet: Vector3, axis: Vector3, rel_rate: float) -> Vector3:
	return moon_velocity + (axis.normalized() * rel_rate).cross(offset_from_planet)

static func to_moon_velocity(ring_velocity: Vector3, offset_from_planet: Vector3, axis: Vector3, rel_rate: float) -> Vector3:
	return ring_velocity - (axis.normalized() * rel_rate).cross(offset_from_planet)

# The moon's pull; inside it, a uniform sphere's (falling to zero at the
# centre).
static func gravity(offset_from_moon: Vector3) -> Vector3:
	var reach := maxf(offset_from_moon.length(), RADIUS)
	return -offset_from_moon * (GM / (reach * reach * reach))
