extends RefCounted

# Side screens hinge on the center screen's outer edge and turn toward the
# pilot by tilt_degrees. side: -1 = left, +1 = right. Eye at the origin,
# screens face +Z.
static func compute_side_screen_transform(center_width: float, side_width: float, screen_distance: float, tilt_degrees: float, side: float) -> Transform3D:
	var hinge := Vector3(side * center_width * 0.5, 0.0, -screen_distance)
	var screen_basis := Basis(Vector3.UP, deg_to_rad(-side * tilt_degrees))
	var screen_origin: Vector3 = hinge + screen_basis * Vector3(side * side_width * 0.5, 0.0, 0.0)
	return Transform3D(screen_basis, screen_origin)

# Turned by half of each image, the side image starts exactly where the front
# image ends: a continuous panorama with no blind wedge and no overlap.
static func compute_side_camera_yaw_degrees(center_hfov_degrees: float, side_hfov_degrees: float, side: float) -> float:
	return -side * (center_hfov_degrees + side_hfov_degrees) * 0.5

# The two screens share their seam edge. A point on the seam is drawn at the
# same height on both only when width / sin(hfov / 2) is equal for the two
# screens, so a narrower side screen needs a narrower side camera.
static func compute_side_camera_hfov_degrees(center_width: float, side_width: float, center_hfov_degrees: float) -> float:
	var half_center := deg_to_rad(center_hfov_degrees) * 0.5
	return rad_to_deg(2.0 * asin(sin(half_center) * side_width / center_width))
