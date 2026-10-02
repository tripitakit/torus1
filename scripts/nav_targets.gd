extends RefCounted

# Where each flight computer target is, for a ship: its arrival point
# (world) and that point's velocity in the frame the ship flies in.
#  DOCK        the nearest bridge's dock: DOCK_STANDOFF out from its pad
#  GATE TERRA  the earth portal: GATE_STANDOFF out of its active side
#  GATE LUNA   the moon portal, the same
#  SELENE      the nearest of Base Selene's pads: PAD_HEIGHT over it

const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const LandingGuide = preload("res://scripts/landing_guide.gd")

const DOCK_STANDOFF := 1000.0
const GATE_STANDOFF := 500.0
const PAD_HEIGHT := 500.0

# {point, velocity, name}, or empty when the target is not in the scene.
static func point(target: String, ship: Node3D) -> Dictionary:
	var moon: Node3D = ship.moon_node()
	match target:
		"DOCK":
			var station := ship.get_node_or_null(ship.station_path) as Node3D
			if station == null or not station.is_inside_tree():
				return {}
			var port: Node3D = station.get_docking_port(station.nearest_bridge_index(ship.global_position))
			var at: Vector3 = port.global_position + port.global_transform.basis.x.normalized() * DOCK_STANDOFF
			return _on_ring(target, at, ship, moon)
		"GATE TERRA", "GATE LUNA":
			var gate := _portal(ship, "LUNA" if target == "GATE TERRA" else "TERRA")
			if gate == null:
				return {}
			var frame: Transform3D = gate.active_transform()
			var at: Vector3 = frame.origin + frame.basis.z.normalized() * GATE_STANDOFF
			if target == "GATE LUNA":
				return _on_moon(target, at, ship, moon)
			return _on_ring(target, at, ship, moon)
		"SELENE":
			if moon == null:
				return {}
			var pads := []
			for number in range(1, 7):
				pads.append(moon.pad_transform(number))
			var pad: Transform3D = pads[LandingGuide.target_pad(ship.global_position, pads)]
			return _on_moon(target, pad.origin + pad.basis.y.normalized() * PAD_HEIGHT, ship, moon)
	return {}

# Whether the ship is near the moon (the route's legs turn on this).
static func near_moon(ship: Node3D) -> bool:
	var moon: Node3D = ship.moon_node()
	return moon != null and ship.global_position.distance_to(moon.centre()) < MoonOrbit.MARKER_RANGE

static func _portal(ship: Node3D, destination: String) -> Node3D:
	for portal in ship.portals():
		if portal.destination == destination:
			return portal
	return null

# A point fixed on the ring's frame: still there; seen from the moon's frame
# it turns the other way.
static func _on_ring(target: String, at: Vector3, ship: Node3D, moon: Node3D) -> Dictionary:
	var velocity := Vector3.ZERO
	if ship.in_moon_frame and moon != null:
		velocity = MoonOrbit.to_moon_velocity(Vector3.ZERO, at - moon.planet_centre(), moon.axis(), moon.relative_rate())
	return {"name": target, "point": at, "velocity": velocity}

# A point fixed on the moon: still in its frame; from the ring's it moves
# with the moon.
static func _on_moon(target: String, at: Vector3, ship: Node3D, moon: Node3D) -> Dictionary:
	var velocity := Vector3.ZERO
	if not ship.in_moon_frame and moon != null:
		velocity = MoonOrbit.to_ring_velocity(Vector3.ZERO, at - moon.planet_centre(), moon.axis(), moon.relative_rate())
	return {"name": target, "point": at, "velocity": velocity}
