extends RefCounted

# What the HUD shows, all pure: the one context panel at the top centre
# (landing, gate or docking: the most pressing), and the sensor lines worth
# a row (something within SENSOR_RANGE).

enum Context { NONE, DOCK, GATE, LANDING }

# The landing panel comes first under this height over the moon's ground.
const LANDING_FIRST := 5000.0
const SENSOR_RANGE := 2000.0

# `moon` (LandingReadout), `gate` (PortalRules) and `dock` (DockingAssist)
# readouts, empty where they do not apply; `altitude` over the moon's ground.
static func context(moon: Dictionary, altitude: float, gate: Dictionary, dock: Dictionary) -> int:
	if not moon.is_empty() and altitude < LANDING_FIRST:
		return Context.LANDING
	if not gate.is_empty():
		return Context.GATE
	if not dock.is_empty():
		return Context.DOCK
	if not moon.is_empty():
		return Context.LANDING
	return Context.NONE

# The sensor readings with something within SENSOR_RANGE (no reading: -1).
static func near_sensors(distances: Dictionary) -> Dictionary:
	var near := {}
	for key in distances:
		var distance: float = distances[key]
		if distance >= 0.0 and distance < SENSOR_RANGE:
			near[key] = distance
	return near
