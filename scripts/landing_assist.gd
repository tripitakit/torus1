extends RefCounted

# Help for landing on the moon, all pure: below RANGE metres (the hull's
# bottom over the ground or the pad) the thrust and the turn rate ease off
# with the altitude, and an idle ship levels itself.

const RANGE := 300.0
const FLOOR := 20.0
# About 2 m/s2 of the base 150 at the floor: twice the moon's pull, enough to
# brake a descent, soft enough to hold one.
const THRUST_MIN := 0.0133
const TORQUE_MIN := 0.25
# Levelling: turn rate per radian off level, and its cap (rad/s).
const LEVEL_RATE := 1.5
const LEVEL_MAX := 1.0

static func _share(altitude: float) -> float:
	return clampf((altitude - FLOOR) / (RANGE - FLOOR), 0.0, 1.0)

static func thrust_factor(altitude: float) -> float:
	if altitude >= RANGE:
		return 1.0
	return lerpf(THRUST_MIN, 1.0, _share(altitude))

static func torque_factor(altitude: float) -> float:
	if altitude >= RANGE:
		return 1.0
	return lerpf(TORQUE_MIN, 1.0, _share(altitude))

# The nose's direction in the horizontal plane (the belly's when the nose
# points straight up or down): the heading levelling keeps.
static func heading_of(ship_basis: Basis, up: Vector3) -> Vector3:
	var hull := ship_basis.orthonormalized()
	var heading := -hull.z - up * (-hull.z).dot(up)
	if heading.length() < 1e-6:
		heading = hull.y - up * hull.y.dot(up)
	return heading.normalized()

# The angular velocity (flying_craft.gd's convention: x pitch about the local
# X, y yaw about the local Y, z roll about the local FORWARD) that turns the
# ship toward level: its up on `up`, the local vertical, its nose on
# `heading` (horizontal; fixed by the caller when levelling starts, so the
# target does not wander as the ship turns).
static func level_rate(ship_basis: Basis, up: Vector3, heading: Vector3) -> Vector3:
	var hull := ship_basis.orthonormalized()
	var target := Basis(heading.cross(up).normalized(), up, -heading)
	var turn := Quaternion(target.orthonormalized()) * Quaternion(hull).inverse()
	var angle := turn.get_angle()
	if angle > PI:
		angle -= TAU
	if absf(angle) < 1e-9:
		return Vector3.ZERO
	var local: Vector3 = hull.inverse() * (turn.get_axis() * angle)
	return (Vector3(local.x, local.y, -local.z) * LEVEL_RATE).limit_length(LEVEL_MAX)
