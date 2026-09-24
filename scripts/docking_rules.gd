extends RefCounted

# One rule to dock at a station port from outside and to undock from the
# interior platform: close enough and slow enough.
const DOCK_RANGE := 150.0
const DOCK_MAX_SPEED := 20.0

static func can_dock(distance: float, speed: float) -> bool:
	return distance <= DOCK_RANGE and speed <= DOCK_MAX_SPEED
