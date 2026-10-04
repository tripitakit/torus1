extends RefCounted

# Arcade driving for a vehicle on the ground (the moon rover; later the car
# inside the station). Pure functions, no nodes: the vehicle's state goes in,
# the new state comes out. The ground is asked through any object with
#   ground_altitude(point: Vector3) -> float  (how far `point` is over it)
#   up_at(point: Vector3) -> Vector3          (the local up there)
# The vehicle's origin is where its wheels touch the ground; -Z is its nose.

const MAX_SPEED := 20.0
const MAX_REVERSE := 5.0
const ACCELERATION := 3.0
const BRAKING := 6.0
const HANDBRAKE := 8.0
# Off the throttle the vehicle slows down by itself.
const ROLLING_DRAG := 0.6
# The tightest turn: 6 m standing, 40 m at top speed, straight in between.
const RADIUS_STANDING := 6.0
const RADIUS_AT_TOP := 40.0
const WHEELBASE := 2.5
# The wheel turns full over in 0.3 s and comes back straight in 0.2 s.
const STEER_IN_TIME := 0.3
const STEER_OUT_TIME := 0.2
# Uphill the engine weakens from 25 degrees and has nothing left at 35;
# steeper than 35 degrees the vehicle slides down.
const SLOPE_SOFT := 0.4363323  # 25 degrees
const SLOPE_STOP := 0.6108652  # 35 degrees
# Further than this over the ground the vehicle is in the air.
const AIR_GAP := 0.15
# Off a crest it goes up at most this fast (m/s): a hop, not a flight.
const MAX_LAUNCH := 2.0
# In the air it falls this many times faster than the ground's gravity:
# at the moon's 1.62 m/s² a rover off a rim at speed would fly for seconds,
# with no steering and no brake.
const AIR_GRAVITY := 3.0
# How fast the body leans onto the ground under its wheels.
const SETTLE_TIME := 0.1
# The wheels: half the track, half the wheelbase.
const HALF_TRACK := 0.9
const HALF_BASE := 1.25

static func turn_radius(speed: float) -> float:
	return lerpf(RADIUS_STANDING, RADIUS_AT_TOP, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))

# Turning rate (rad/s, + to the left about the vehicle's up) at `speed` with
# the wheel at `steer` (-1 full left .. +1 full right). Backing up, the nose
# swings the other way, as in a car.
static func yaw_rate(speed: float, steer: float) -> float:
	return -speed / turn_radius(speed) * steer

# The front wheels' angle (rad, + to the left) for the model.
static func wheel_angle(speed: float, steer: float) -> float:
	return -atan(WHEELBASE / turn_radius(speed)) * steer

static func next_steer(steer: float, wanted: float, delta: float) -> float:
	var time := STEER_IN_TIME if wanted != 0.0 else STEER_OUT_TIME
	return move_toward(steer, wanted, delta / time)

# How much of the engine is left climbing `slope` (rad, + uphill).
static func climb_factor(slope: float) -> float:
	return clampf((SLOPE_STOP - slope) / (SLOPE_STOP - SLOPE_SOFT), 0.0, 1.0)

# The speed along the nose after a tick on the ground. `throttle` -1..1 (W
# +1, S -1): the way the vehicle goes (or off from standstill) it drives,
# against it it brakes. `slope` (rad) is + with the nose uphill.
static func next_speed(speed: float, throttle: float, handbrake: bool, slope: float, gravity: float, delta: float) -> float:
	var new_speed := speed
	if handbrake:
		new_speed = move_toward(speed, 0.0, HANDBRAKE * delta)
	elif throttle != 0.0 and (speed == 0.0 or signf(throttle) == signf(speed)):
		new_speed = speed + ACCELERATION * throttle * climb_factor(slope * signf(throttle)) * delta
	elif throttle != 0.0:
		new_speed = move_toward(speed, 0.0, BRAKING * absf(throttle) * delta)
	else:
		new_speed = move_toward(speed, 0.0, ROLLING_DRAG * delta)
	if absf(slope) > SLOPE_STOP:
		new_speed -= gravity * sin(slope) * delta
	return clampf(new_speed, -MAX_REVERSE, MAX_SPEED)

# Standing still at `at`, on the ground.
static func new_body(at: Transform3D) -> Dictionary:
	return {"transform": at, "speed": 0.0, "vertical": 0.0, "steer": 0.0, "airborne": false, "motion": Vector3.ZERO}

# One tick of driving. `controls`: {throttle, steer, handbrake}. On the
# ground the vehicle speeds up or brakes along its nose and turns about its
# own up; in the air it only falls, keeping its speed. The new body's
# `motion` (world) is this tick's move: make it (with walls or not), then
# settle().
static func drive(body: Dictionary, controls: Dictionary, ground: Object, gravity: float, delta: float) -> Dictionary:
	var out := body.duplicate()
	var basis: Basis = (body.transform as Transform3D).basis.orthonormalized()
	var origin: Vector3 = (body.transform as Transform3D).origin
	var up: Vector3 = ground.up_at(origin)
	if body.airborne:
		out.vertical = body.vertical - gravity * AIR_GRAVITY * delta
		out.motion = (_flat_nose(basis, up) * body.speed + up * out.vertical) * delta
		return out
	out.steer = next_steer(body.steer, controls.steer, delta)
	var nose := -basis.z
	var slope := asin(clampf(nose.dot(up), -1.0, 1.0))
	out.speed = next_speed(body.speed, controls.throttle, controls.handbrake, slope, gravity, delta)
	var turned := basis.rotated(basis.y, yaw_rate(out.speed, out.steer) * delta)
	out.transform = Transform3D(turned, origin)
	out.vertical = 0.0
	out.motion = -turned.z * out.speed * delta
	return out

# After the move. On the ground: put on it and leaned toward the plane under
# its four wheels; if the ground fell away more than AIR_GAP, off into the
# air with the speed it had (its climb becomes the vertical speed, at most
# MAX_LAUNCH). In the
# air: levels out slowly, back on the ground once it reaches it.
static func settle(body: Dictionary, ground: Object, delta: float) -> Dictionary:
	var out := body.duplicate()
	var basis: Basis = (body.transform as Transform3D).basis.orthonormalized()
	var origin: Vector3 = (body.transform as Transform3D).origin
	var up: Vector3 = ground.up_at(origin)
	var height: float = ground.ground_altitude(origin)
	if not body.airborne and height > AIR_GAP:
		var rise: float = -basis.z.dot(up)
		out.airborne = true
		out.vertical = minf(body.speed * rise, MAX_LAUNCH)
		out.speed = body.speed * sqrt(maxf(0.0, 1.0 - rise * rise))
	elif body.airborne and height <= 0.0:
		out.airborne = false
		out.vertical = 0.0
	if out.airborne:
		out.transform = Transform3D(_ease(basis, heading_basis(-basis.z, up), delta), origin)
		return out
	var on_ground := origin - up * height
	var lean := heading_basis(-basis.z, contact_normal(Transform3D(basis, on_ground), ground))
	out.transform = Transform3D(_ease(basis, lean, delta), on_ground)
	return out

# A basis with `up` as its y and `nose` (laid on the plane across `up`) as
# its -z.
static func heading_basis(nose: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var z := -(nose - y * nose.dot(y)).normalized()
	return Basis(y.cross(z), y, z)

# The ground's points under the four wheels of a vehicle at `at`: front
# left, front right, rear left, rear right.
static func contacts(at: Transform3D, ground: Object) -> Array:
	var points := []
	for corner in [Vector3(-HALF_TRACK, 0.0, -HALF_BASE), Vector3(HALF_TRACK, 0.0, -HALF_BASE), Vector3(-HALF_TRACK, 0.0, HALF_BASE), Vector3(HALF_TRACK, 0.0, HALF_BASE)]:
		var point: Vector3 = at * corner
		points.append(point - ground.up_at(point) * ground.ground_altitude(point))
	return points

# The ground's plane under the four wheels: the cross of its diagonals,
# turned up.
static func contact_normal(at: Transform3D, ground: Object) -> Vector3:
	var p := contacts(at, ground)
	var normal: Vector3 = ((p[1] as Vector3) - p[2]).cross((p[0] as Vector3) - p[3]).normalized()
	return normal if normal.dot(ground.up_at(at.origin)) >= 0.0 else -normal

static func _flat_nose(basis: Basis, up: Vector3) -> Vector3:
	var nose := -basis.z
	var flat := nose - up * nose.dot(up)
	return flat.normalized() if flat.length() > 1e-6 else nose

# Part of the way from `from` to `to`: all of it in SETTLE_TIME.
static func _ease(from: Basis, to: Basis, delta: float) -> Basis:
	return from.slerp(to.orthonormalized(), clampf(delta / SETTLE_TIME, 0.0, 1.0))
