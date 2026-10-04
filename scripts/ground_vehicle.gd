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
