extends SceneTree

# The flight computer on the real scene: T walks the targets, G flies to the
# leg's arrival point and stops there, a movement key takes over.

const FlightComputer = preload("res://scripts/flight_computer.gd")
const NavTargets = preload("res://scripts/nav_targets.gd")

var _failures := 0
var _scene: Node3D
var _ship: CharacterBody3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	_ship = _scene.get_node("VoidCruiser")
	for tick in range(10):
		await physics_frame

	_failures += _test_t_walks_the_targets()
	_failures += _test_points_of_the_targets()
	_failures += await _test_g_flies_to_the_gate_and_stops()
	_failures += await _test_a_movement_key_takes_over()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_ship._unhandled_input(event)

func _test_t_walks_the_targets() -> int:
	var seen := []
	for i in range(7):
		_press("nav_target")
		seen.append(_ship.nav_target)
	if seen != ["DOCK", "GATE TERRA", "GATE LUNA", "SELENE", "TELESCOPE", "AREA 2", ""]:
		print("FAIL _test_t_walks_the_targets: %s" % [seen])
		return 1
	return 0

func _test_points_of_the_targets() -> int:
	# From the start (near Torus1): the dock 1 km off its pad, the gates 500 m
	# out of their active sides, Selene 500 m over a pad; the readout names
	# the leg through the earth gate for Selene.
	var result := 0
	var earth: Node3D = _scene.get_node("PlanetSystem/EarthPortal")
	var at: Transform3D = earth.active_transform()
	var gate := NavTargets.point("GATE TERRA", _ship)
	if gate.is_empty() or (gate.point as Vector3).distance_to(at.origin + at.basis.z.normalized() * 500.0) > 0.01 or not (gate.velocity as Vector3).is_zero_approx():
		print("FAIL _test_points_of_the_targets: gate %s" % gate)
		result = 1
	var dock := NavTargets.point("DOCK", _ship)
	var station: Node3D = _scene.get_node("PlanetSystem/TorusStation")
	var port: Node3D = station.get_docking_port(station.nearest_bridge_index(_ship.global_position))
	if dock.is_empty() or absf((dock.point as Vector3).distance_to(port.global_position) - 1000.0) > 0.01:
		print("FAIL _test_points_of_the_targets: dock %s" % dock)
		result = 1
	var selene := NavTargets.point("SELENE", _ship)
	var moon: Node3D = _scene.get_node("PlanetSystem/Moon")
	if selene.is_empty() or absf(moon.altitude(selene.point) - 500.0) > 5.0 or (selene.velocity as Vector3).length() < 100.0:
		print("FAIL _test_points_of_the_targets: Selene %s (moving with the moon as seen from the ring)" % selene)
		result = 1
	# The outposts: 500 m over their pads (7, 8).
	for target in [["TELESCOPE", 7], ["AREA 2", 8]]:
		var outpost := NavTargets.point(target[0], _ship)
		var pad: Transform3D = moon.pad_transform(target[1])
		if outpost.is_empty() or (outpost.point as Vector3).distance_to(pad.origin + pad.basis.y.normalized() * 500.0) > 0.01:
			print("FAIL _test_points_of_the_targets: %s %s" % [target[0], outpost])
			result = 1
	_ship.nav_target = "SELENE"
	var readout: Dictionary = _ship.nav_readout()
	if readout.is_empty() or readout.lines.nav != "NAV  SELENE via GATE TERRA":
		print("FAIL _test_points_of_the_targets: readout %s" % readout)
		result = 1
	_ship.nav_target = ""
	return result

func _test_g_flies_to_the_gate_and_stops() -> int:
	# 4 km short of the earth gate's arrival point, at rest: G, and within
	# 40 s the ship sits on the point, the brake on, ARRIVED shown.
	var gate := NavTargets.point("GATE TERRA", _ship)
	var side := (gate.point as Vector3).cross(Vector3.UP).normalized()
	_ship.global_position = gate.point + side * 4000.0
	_ship.velocity = Vector3.ZERO
	_ship.brake_engaged = false
	_ship.nav_target = "GATE TERRA"
	_press("autopilot")
	if _ship.autopilot != FlightComputer.Auto.ARRIVING:
		print("FAIL _test_g_flies_to_the_gate_and_stops: G did not engage")
		return 1
	for tick in range(2400):
		await physics_frame
		if _ship.autopilot != FlightComputer.Auto.ARRIVING:
			break
	var point: Vector3 = NavTargets.point("GATE TERRA", _ship).point
	var off := _ship.global_position.distance_to(point)
	if _ship.autopilot != FlightComputer.Auto.ARRIVED or off > FlightComputer.ARRIVE_DISTANCE + 0.5 or not _ship.brake_engaged or _ship.nav_readout().lines.auto != "ARRIVED":
		print("FAIL _test_g_flies_to_the_gate_and_stops: auto %s, %.1f m off, brake %s" % [_ship.autopilot, off, _ship.brake_engaged])
		return 1
	return 0

func _test_a_movement_key_takes_over() -> int:
	_ship.brake_engaged = false
	_ship.nav_target = "DOCK"
	_press("autopilot")
	await physics_frame
	_press("move_left")
	if _ship.autopilot != FlightComputer.Auto.OFF:
		print("FAIL _test_a_movement_key_takes_over: still %s" % _ship.autopilot)
		return 1
	return 0
