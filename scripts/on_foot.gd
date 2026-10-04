extends RefCounted

# On foot, the same on the moon and inside the sections (moon_walker.gd,
# interior_walker.gd): walking and jogging, looking round, jumping, and how
# near a vehicle the pilot must be to board it. Pure functions.

const WALK_SPEED := 1.5
const JOG_SPEED := 4.0
const EYE_HEIGHT := 1.7
# The walker's capsule.
const RADIUS := 0.3
const HEIGHT := 1.8
const LOOK_SENSITIVITY := 0.003
const PITCH_LIMIT := 1.2217305  # 70 degrees
# Straight up at the jump (m/s): a long lunar bound, an ordinary hop inside.
const JUMP_MOON := 2.0
const JUMP_INTERIOR := 3.1
# From a vehicle's collision box, to board it.
const BOARD_DISTANCE := 8.0
# On the moon the ground ahead may rise this steeply at most.
const MAX_CLIMB := 0.6108652  # 35 degrees

# The walking velocity: `input` x right, y ahead (-1..1 each, as WASD),
# along `basis`'s x (right) and -z (ahead), never faster on a diagonal.
static func walk_velocity(input: Vector2, jogging: bool, basis: Basis) -> Vector3:
	var way := basis.x * input.x - basis.z * input.y
	if way.length() > 1.0:
		way = way.normalized()
	return way * (JOG_SPEED if jogging else WALK_SPEED)

# (yaw, pitch) after a mouse move: turning freely, looking up or down within
# PITCH_LIMIT.
static func look(yaw_pitch: Vector2, mouse: Vector2) -> Vector2:
	return Vector2(yaw_pitch.x - mouse.x * LOOK_SENSITIVITY, clampf(yaw_pitch.y - mouse.y * LOOK_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT))

static func air_time(jump: float, gravity: float) -> float:
	return 2.0 * jump / gravity

# How far `point` is from a box `size` placed at `box` (0 inside it).
static func distance_to_box(point: Vector3, box: Transform3D, size: Vector3) -> float:
	var local := box.affine_inverse() * point
	var half := size * 0.5
	return (local - local.clamp(-half, half)).length()
