extends RefCounted

# The flight computer, all pure: the NAV panel's numbers (how far, how fast
# closing, when there, how far to stop, when to start braking), the arrival
# guidance (which acceleration brings the ship to rest on a point, along any
# axis, with no turning) and the route's legs through the gates.

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")
const DockingAssist = preload("res://scripts/docking_assist.gd")

const TARGETS := ["DOCK", "GATE TERRA", "GATE LUNA", "SELENE"]
# Targets on the moon's side of the gates.
const MOON_SIDE := ["GATE LUNA", "SELENE"]
# Arrived: this close to the point and this slow relative to it.
const ARRIVE_DISTANCE := 5.0
const ARRIVE_SPEED := 0.5
# The guidance plans its braking at this share of the brake (a margin), runs
# under the speed limit by LIMIT_SHARE, closes the last metres in about
# FINAL_TIME seconds and steers its velocity in about RESPONSE seconds.
const BRAKE_SHARE := 0.8
const LIMIT_SHARE := 0.98
const FINAL_TIME := 2.0
const RESPONSE := 0.5
# Closing slower than this gives no time of arrival.
const MIN_CLOSING := 0.5
const GOOD := Color(0.3, 1.0, 0.4)
const BAD := Color(1.0, 0.3, 0.25)

enum Auto { OFF, ARRIVING, ARRIVED }

# The next target after `current` ("" for none), round the list and back to
# none.
static func next_target(current: String) -> String:
	var index := TARGETS.find(current)
	if index == TARGETS.size() - 1:
		return ""
	return TARGETS[index + 1]

# The leg to fly now toward `target`: through the gate on the ship's side
# when the target lies on the other side.
static func leg(target: String, ship_near_moon: bool) -> String:
	var target_on_moon := target in MOON_SIDE
	if target_on_moon and not ship_near_moon:
		return "GATE TERRA"
	if ship_near_moon and not target_on_moon:
		return "GATE LUNA"
	return target

# `distance` to the point, `closing` toward it (m/s), `brake` the braking
# acceleration: {distance, closing, eta (s, -1 for none), stop (m), brake_in
# (s, -1 for none), brake_now}.
static func readout(distance: float, closing: float, brake: float) -> Dictionary:
	var stop := closing * closing / (2.0 * brake) if closing > 0.0 else 0.0
	var eta := -1.0
	var brake_in := -1.0
	if closing > MIN_CLOSING:
		eta = distance / closing
		if stop < distance:
			brake_in = (distance - stop) / closing
	return {"distance": distance, "closing": closing, "eta": eta, "stop": stop, "brake_in": brake_in, "brake_now": closing > MIN_CLOSING and stop >= distance}

# The NAV panel's lines for `target` and its current `leg`.
static func lines(target: String, leg_name: String, r: Dictionary, auto: int) -> Dictionary:
	var nav := "NAV  " + target
	if leg_name != target:
		nav += " via " + leg_name
	var auto_text := ""
	if auto == Auto.ARRIVING:
		auto_text = "AUTO  ARRIVING"
	elif auto == Auto.ARRIVED:
		auto_text = "ARRIVED"
	return {
		"nav": nav,
		"dist": "DIST  " + CockpitHudFormat.format_distance(r.distance),
		"closing": "CLOSING  " + CockpitHudFormat.format_speed(r.closing),
		"eta": "ETA  " + DockingAssist.format_time(r.eta),
		"stop": "STOP  " + CockpitHudFormat.format_distance(r.stop),
		"brake": "BRAKE NOW" if r.brake_now else "BRAKE IN  " + DockingAssist.format_time(r.brake_in),
		"auto": auto_text,
		"colors": {"brake": BAD if r.brake_now else GOOD, "auto": GOOD},
	}

# The acceleration (world) that brings the ship, `offset` short of the point
# (point minus ship) at `velocity`, to rest on it, the point moving at
# `target_velocity`: toward it at the most `limit` (relative) and at a speed
# it can still brake from, steering any other motion away; never more than
# `brake`.
static func command(offset: Vector3, velocity: Vector3, target_velocity: Vector3, limit: float, brake: float) -> Vector3:
	var distance := offset.length()
	var wanted := target_velocity
	if distance > 0.0:
		var speed := minf(limit * LIMIT_SHARE, minf(sqrt(2.0 * BRAKE_SHARE * brake * distance), distance / FINAL_TIME))
		wanted += offset / distance * speed
	var accel := (wanted - velocity) / RESPONSE
	if accel.length() > brake:
		accel = accel.normalized() * brake
	return accel

static func arrived(offset: Vector3, relative_velocity: Vector3) -> bool:
	return offset.length() < ARRIVE_DISTANCE and relative_velocity.length() < ARRIVE_SPEED
