extends RefCounted

# Help for flying to a dock, all pure: thrust that eases off near it, the
# brake step, the advised speed and the approach panel's lines.

const DockingRules = preload("res://scripts/docking_rules.gd")
const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

# Within PRECISION_RANGE of a dock the thrust drops with the distance, from
# 1x there to PRECISION_MIN at PRECISION_FLOOR and closer, with no ramp.
const PRECISION_RANGE := 2000.0
const PRECISION_FLOOR := 200.0
const PRECISION_MIN := 0.1
# The brake pushes at up to this many times the base thrust (times the
# precision factor near a dock).
const BRAKE_MULTIPLIER := 10.0
# The advised speed stops the ship on the pad braking steadily at this rate.
const ADVISED_DECELERATION := 1.0
# Faster than advised by up to this ratio is a caution; beyond, too fast.
const CAUTION_RATIO := 1.25
# Closing slower than this gives no time of arrival.
const MIN_CLOSING := 0.5
const READY_TEXT := "DOCK READY"
const TOO_FAST_TEXT := "TOO FAST"

enum Rating { OK, CAUTION, OVER }

static func precision_factor(distance: float) -> float:
	if distance >= PRECISION_RANGE:
		return 1.0
	return clampf(lerpf(PRECISION_MIN, 1.0, (distance - PRECISION_FLOOR) / (PRECISION_RANGE - PRECISION_FLOOR)), PRECISION_MIN, 1.0)

# The thrust input to fly with: the forward ramp away from docks, the
# precision factor on every axis near one.
static func scaled_thrust(input: Vector3, ramp: float, precision: float) -> Vector3:
	if precision < 1.0:
		return input * precision
	return Vector3(input.x, input.y, input.z * ramp)

# One tick of braking toward the `target` velocity, changing it by at most
# `max_acceleration` * delta.
static func brake_velocity(velocity: Vector3, target: Vector3, max_acceleration: float, delta: float) -> Vector3:
	return velocity + (target - velocity).limit_length(max_acceleration * delta)

# The speed from which braking steadily at ADVISED_DECELERATION stops on the
# pad, `length` metres along the path.
static func advised_speed(length: float) -> float:
	return sqrt(2.0 * ADVISED_DECELERATION * maxf(length, 0.0))

static func speed_rating(speed: float, advised: float) -> int:
	if speed <= advised:
		return Rating.OK
	if speed <= advised * CAUTION_RATIO:
		return Rating.CAUTION
	return Rating.OVER

# "42 s" under a minute, "3:05" beyond; a dash for no reading (negative).
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return CockpitHudFormat.NO_READING
	var whole := roundi(seconds)
	if whole < 60:
		return "%d s" % whole
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]

# The approach panel: `length` to go along the path, `speed` and `closing`
# (toward the dock along the path) relative to the pad, `distance` to the
# pad in a straight line (for the docking rule).
static func readout(length: float, speed: float, closing: float, distance: float) -> Dictionary:
	var advised := advised_speed(length)
	var rating := speed_rating(speed, advised)
	# Too fast to dock reads as too fast.
	if distance <= DockingRules.DOCK_RANGE and speed > DockingRules.DOCK_MAX_SPEED:
		rating = Rating.OVER
	var eta := length / closing if closing >= MIN_CLOSING else -1.0
	var ready := DockingRules.can_dock(distance, speed)
	var status := ""
	if ready:
		status = READY_TEXT
	elif distance <= DockingRules.DOCK_RANGE:
		status = TOO_FAST_TEXT
	return {
		"dist": "DIST  " + CockpitHudFormat.format_distance(length),
		"speed": "REL SPEED  " + CockpitHudFormat.format_speed(speed),
		"advised": "ADVISED  " + CockpitHudFormat.format_speed(advised),
		"eta": "ETA  " + format_time(eta),
		"status": status,
		"rating": rating,
		"ready": ready,
	}
