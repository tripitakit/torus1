extends RefCounted

# Where the rover comes out of the landed ship, and when the pilot can
# board again. On a pad (a 60 m square, 2 m high, which the rover cannot
# climb) both count from the pad's centre instead of the ship.

const SIDE_OFFSET := 15.0
# Past the pad's corners (30 * sqrt 2 = 42.4 m) with room to spare.
const PAD_OFFSET := 52.0
const BOARD_DISTANCE := 30.0
const PAD_BOARD_DISTANCE := 60.0
const BOARD_SPEED := 1.0

# Where the rover may come out, first choice first: right of the ship,
# left, behind, ahead, on the level across `up`.
static func spawn_spots(ship: Transform3D, up: Vector3, on_pad: bool, pad_centre: Vector3) -> Array:
	var right := _flat(ship.basis.x, up)
	var nose := _flat(-ship.basis.z, up)
	var from := pad_centre if on_pad else ship.origin
	var reach := PAD_OFFSET if on_pad else SIDE_OFFSET
	var spots := []
	for direction in [right, -right, -nose, nose]:
		spots.append(from + direction * reach)
	return spots

static func can_board(rover: Vector3, speed: float, ship: Vector3, on_pad: bool, pad_centre: Vector3) -> bool:
	if speed >= BOARD_SPEED:
		return false
	if on_pad:
		return rover.distance_to(pad_centre) <= PAD_BOARD_DISTANCE
	return rover.distance_to(ship) <= BOARD_DISTANCE

static func _flat(direction: Vector3, up: Vector3) -> Vector3:
	return (direction - up * direction.dot(up)).normalized()
