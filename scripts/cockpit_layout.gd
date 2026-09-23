extends RefCounted

# Side screens hinge on the center screen's outer edge and turn toward the
# pilot by tilt_degrees. side: -1 = left, +1 = right. Eye at the origin,
# screens face +Z.
static func compute_side_screen_transform(center_width: float, side_width: float, screen_distance: float, tilt_degrees: float, side: float) -> Transform3D:
	var hinge := Vector3(side * center_width * 0.5, 0.0, -screen_distance)
	var screen_basis := Basis(Vector3.UP, deg_to_rad(-side * tilt_degrees))
	var screen_origin: Vector3 = hinge + screen_basis * Vector3(side * side_width * 0.5, 0.0, 0.0)
	return Transform3D(screen_basis, screen_origin)

# A side camera turned by one full horizontal FOV starts exactly where the
# front camera's image ends: a continuous panorama with no blind wedge.
static func compute_side_camera_yaw_degrees(horizontal_fov_degrees: float, side: float) -> float:
	return -side * horizontal_fov_degrees
