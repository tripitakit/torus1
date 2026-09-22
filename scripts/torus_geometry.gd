extends RefCounted

static func compute_section_transforms(planet_radius: float, orbit_altitude: float, num_sections: int) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if num_sections < 1:
		return transforms
	var torus_radius := planet_radius + orbit_altitude
	var step := TAU / num_sections
	for i in range(num_sections):
		transforms.append(_section_transform_at(torus_radius, i * step))
	return transforms

static func compute_bridge_length(planet_radius: float, orbit_altitude: float, num_sections: int, section_length: float) -> float:
	if num_sections < 1:
		return 0.0
	var torus_radius := planet_radius + orbit_altitude
	var circumference := TAU * torus_radius
	var step_arc_length := circumference / num_sections
	return step_arc_length - section_length

static func compute_bridge_transforms(planet_radius: float, orbit_altitude: float, num_sections: int, section_length: float) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if num_sections < 1:
		return transforms
	var torus_radius := planet_radius + orbit_altitude
	var step := TAU / num_sections
	for i in range(num_sections):
		var theta_mid := i * step + step * 0.5
		transforms.append(_section_transform_at(torus_radius, theta_mid))
	return transforms

static func _section_transform_at(torus_radius: float, theta: float) -> Transform3D:
	var position := Vector3(cos(theta), 0.0, sin(theta)) * torus_radius
	var tangent := Vector3(-sin(theta), 0.0, cos(theta))
	var x_axis := Vector3.UP
	var y_axis := tangent
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	return Transform3D(basis, position)
