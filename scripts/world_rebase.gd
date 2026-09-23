extends RefCounted

static func should_rebase(tracked_position: Vector3, threshold: float) -> bool:
	return tracked_position.length() > threshold

static func compute_rebase_offset(tracked_position: Vector3) -> Vector3:
	return tracked_position
