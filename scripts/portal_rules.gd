extends RefCounted

# The portals' rules. A portal's transform: origin at the centre of its
# opening, +Z the active side's normal (a ship enters crossing from +Z to
# -Z, and leaves the other portal out of its +Z side), Y its "up".

# The opening (300 m across) and the frame round it.
const APERTURE_RADIUS := 150.0
const FRAME_WIDTH := 15.0
# Entering at this speed (relative to the portal) or faster is a crash.
const MAX_ENTRY_SPEED := 300.0
const TRANSIT_TIME := 3.0
# The earth portal: this far past the ring, this far along it from the
# start toward the moon's side.
const EARTH_OUT := 100000.0
const EARTH_ARC := 80000.0
# The moon portal: this high over Base Selene.
const MOON_HEIGHT := 20000.0
# The gate panel shows this close to a portal; the gate marker within
# MARKER_RANGE, hidden under MARKER_HIDE.
const PANEL_RANGE := 5000.0
const MARKER_RANGE := 2.0e6
const MARKER_HIDE := 300.0
const GOOD := Color(0.3, 1.0, 0.4)
const BAD := Color(1.0, 0.3, 0.25)

# A half turn about the portal's Y: in through one, out of the other.
const FLIP := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), Vector3.ZERO)

# Where along the move `from` -> `to` (0..1) it crosses `portal`'s opening
# from the active side; -1 if it does not.
static func crossing(from: Vector3, to: Vector3, portal: Transform3D) -> float:
	var normal := portal.basis.z.normalized()
	var a := (from - portal.origin).dot(normal)
	var b := (to - portal.origin).dot(normal)
	if a <= 0.0 or b > 0.0:
		return -1.0
	var t := a / (a - b)
	var point := from + (to - from) * t
	if point.distance_to(portal.origin) >= APERTURE_RADIUS:
		return -1.0
	return t

static func in_front(point: Vector3, portal: Transform3D) -> bool:
	return (point - portal.origin).dot(portal.basis.z) > 0.0

static func speed_ok(speed: float) -> bool:
	return speed < MAX_ENTRY_SPEED

# `ship` as it was against `entry`, set against `exit` turned half round:
# the same offset across the opening, heading and attitude.
static func exit_transform(ship: Transform3D, entry: Transform3D, exit: Transform3D) -> Transform3D:
	return exit.orthonormalized() * FLIP * entry.orthonormalized().affine_inverse() * ship

static func exit_velocity(velocity: Vector3, entry: Transform3D, exit: Transform3D) -> Vector3:
	return exit.basis.orthonormalized() * FLIP.basis * entry.basis.orthonormalized().inverse() * velocity

# The earth portal in the planet system's axes (planet centre at the
# origin, axis +Y, the start along +Z): EARTH_OUT past the ring, EARTH_ARC
# round it toward -X, facing the planet.
static func earth_transform(ring_radius: float) -> Transform3D:
	var radius := ring_radius + EARTH_OUT
	var turn := EARTH_ARC / radius
	var origin := Vector3(-sin(turn), 0.0, cos(turn)) * radius
	var z := -origin.normalized()
	var y := Vector3.UP
	return Transform3D(Basis(y.cross(z), y, z), origin)

# The moon portal in the moon's axes: MOON_HEIGHT over `base` (the base
# site, y its vertical, x east), facing down.
static func moon_local_transform(base: Transform3D) -> Transform3D:
	var up := base.basis.y.normalized()
	var z := -up
	var y := base.basis.x.normalized()
	return Transform3D(Basis(y.cross(z), y, z), base.origin + up * MOON_HEIGHT)

# The gate panel's lines: destination and distance, approach speed (green
# under the limit, red at or past it), and a warning from behind.
static func readout(destination: String, distance: float, speed: float, front: bool) -> Dictionary:
	var ok := speed_ok(speed)
	return {
		"gate": "GATE > %s  %s" % [destination, _distance(distance)],
		"approach": "APPROACH %d m/s  %s" % [roundi(speed), "OK" if ok else "TOO FAST!"],
		"side": "" if front else "WRONG SIDE",
		"colors": {"approach": GOOD if ok else BAD, "side": BAD},
	}

static func _distance(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d m" % roundi(metres)
