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

# The interior chain: bridges and sections in one straight row along -Z, each
# at a "slot" counted from the docked bridge (slot 0, centred on the origin
# at docking). Section slot s lies between bridge s (+Z side) and bridge
# s + 1 (-Z side): slot 0 is the section "ahead", slot -1 the one "behind".

static func chain_period(section_length: float, bridge_length: float) -> float:
	return section_length + bridge_length

static func bridge_slot_z(slot: int, period: float) -> float:
	return -slot * period

static func section_slot_z(slot: int, period: float) -> float:
	return -(slot + 0.5) * period

# Station numbers: bridge i joins section i and section i + 1; the ring closes.
static func bridge_ring_index(docked_bridge: int, slot: int, ring_sections: int) -> int:
	return posmod(docked_bridge + slot, ring_sections)

static func section_ring_index(docked_bridge: int, slot: int, ring_sections: int) -> int:
	return posmod(docked_bridge + slot + 1, ring_sections)

static func nearest_bridge_slot(z: float, period: float) -> int:
	return roundi(-z / period)

# Section slot s is centred at -(s + 0.5) * period (see section_slot_z).
static func nearest_section_slot(z: float, period: float) -> int:
	return roundi(-z / period - 0.5)

# Section slots whose centre is within `reach` of z along the axis, ascending.
static func sections_within(z: float, period: float, reach: float) -> Array:
	var slots := []
	var first: int = ceili(-(z + reach) / period - 0.5)
	var last: int = floori(-(z - reach) / period - 0.5)
	for slot in range(first, last + 1):
		slots.append(slot)
	return slots

# The bridges at both ends of the given sections, ascending, no repeats.
static func bridges_of_sections(sections: Array) -> Array:
	var bridges := []
	for slot in sections:
		for bridge in [slot, slot + 1]:
			if not bridges.has(bridge):
				bridges.append(bridge)
	bridges.sort()
	return bridges
