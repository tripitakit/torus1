extends RefCounted

# Interior world layout: the docked bridge is centred on the origin with its
# axis along Z; the section "ahead" (side -1) lies toward -Z, the section
# "behind" (side +1) toward +Z. Built straight: the real ring's 0.18 degree
# bend between neighbours is ignored.

static func section_center_z(bridge_length: float, section_length: float, side: float) -> float:
	return side * (bridge_length + section_length) * 0.5

# One light at the middle of every `spacing` metres of the section.
static func sun_positions(center_z: float, section_length: float, spacing: float) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var count: int = roundi(section_length / spacing)
	var start: float = center_z - section_length * 0.5
	for k in range(count):
		positions.append(Vector3(0.0, 0.0, start + spacing * (k + 0.5)))
	return positions

static func cylinder_point(radius: float, angle: float, z: float) -> Vector3:
	return Vector3(cos(angle) * radius, sin(angle) * radius, z)

# How many lights on the axis reach a band of the cylinder wall at `radius`
# between z0 and z1. lights: x = position along the axis, y = light range.
static func count_lights_reaching_band(radius: float, z0: float, z1: float, lights: PackedVector2Array) -> int:
	var count := 0
	for light in lights:
		var dz: float = maxf(0.0, maxf(z0 - light.x, light.x - z1))
		if sqrt(radius * radius + dz * dz) < light.y:
			count += 1
	return count
