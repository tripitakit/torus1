extends SceneTree

# Docking help on the real scene: the brake against the pad, the precision
# thrust, the approach panel and the planned meeting point.

const ApproachGuide = preload("res://scripts/approach_guide.gd")
const DockingAssist = preload("res://scripts/docking_assist.gd")

const TICK := 1.0 / 60.0

var _failures := 0
var _scene: Node3D
var _cruiser: CharacterBody3D
var _station: Node3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_cruiser = _scene.get_node("VoidCruiser")
	_station = _scene.get_node("PlanetSystem/TorusStation")
	_cruiser.set_physics_process(false)
	_station.set_process(false)

	_failures += await _test_brake_stops_the_ship_against_the_pad()
	_failures += await _test_thrust_eases_off_near_the_dock()
	_failures += await _test_panel_shows_within_range()
	_failures += await _test_panel_says_when_docking_is_possible()
	# (more tests)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis, nose
# along `nose` (in the port's axes: x out, y along the bridge, z across),
# at rest with the pad. The world shifts on the next tick.
func _park(distance: float, nose: Vector3 = Vector3(-1.0, 0.0, 0.0)) -> void:
	var port: Node3D = _station.get_docking_port(0)
	var axes: Basis = port.global_transform.basis.orthonormalized()
	var at: Vector3 = port.global_position + axes.x * distance
	var up: Vector3 = axes.y if absf(nose.y) < 0.9 else axes.x
	_cruiser.global_transform = Transform3D(Basis.looking_at(axes * nose, up), at)
	_cruiser.velocity = _station.get_docking_port_velocity(0)
	_cruiser.brake_engaged = false
	_cruiser.cruise_locked = false
	for i in range(3):
		await physics_frame
		await process_frame

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_cruiser._unhandled_input(event)

func _fly(ticks: int) -> void:
	for i in range(ticks):
		_cruiser._physics_process(TICK)

func _test_brake_stops_the_ship_against_the_pad() -> int:
	# 5 km out, drifting 300 m/s against the pad: B brings it to the pad's
	# own velocity (it turns with the bridge) in well under a second.
	await _park(5000.0)
	_cruiser.velocity += Vector3(300.0, -120.0, 40.0)
	_press("brake")
	_fly(30)
	var off: Vector3 = _cruiser.velocity - _station.get_docking_port_velocity(0)
	if off.length() > 0.01 or not _cruiser.brake_engaged:
		print("FAIL _test_brake_stops_the_ship_against_the_pad: %.2f m/s off the pad after 0.5 s, brake %s" % [off.length(), _cruiser.brake_engaged])
		return 1
	return 0

func _test_thrust_eases_off_near_the_dock() -> int:
	var result := 0
	# 1100 m out, nose across the bridge (the distance barely changes): half
	# of 150 m/s^2 and no ramp, so about 82 m/s after a second of W.
	await _park(1100.0, Vector3(0.0, 0.0, 1.0))
	var start: Vector3 = _cruiser.velocity
	Input.action_press("move_forward")
	_fly(60)
	Input.action_release("move_forward")
	var gained: float = (_cruiser.velocity - start).length()
	if absf(gained - 150.0 * 0.55) > 3.0 or absf(_cruiser.thrust_scale - 0.55) > 0.02:
		print("FAIL _test_thrust_eases_off_near_the_dock: gained %.1f m/s in 1 s at scale %.2f, expected about 82.5 at 0.55" % [gained, _cruiser.thrust_scale])
		result = 1
	await process_frame
	if not (_cruiser.get_node("Cockpit/Hud/Panel/Lines/ThrustLabel") as Label).visible:
		print("FAIL _test_thrust_eases_off_near_the_dock: the THRUST line is hidden at 1.1 km")
		result = 1
	# 5 km out: full thrust with the ramp, and no THRUST line.
	await _park(5000.0)
	_fly(1)
	await process_frame
	if _cruiser.thrust_scale != 1.0 or (_cruiser.get_node("Cockpit/Hud/Panel/Lines/ThrustLabel") as Label).visible:
		print("FAIL _test_thrust_eases_off_near_the_dock: scale %.2f at 5 km" % _cruiser.thrust_scale)
		result = 1
	return result

func _panel() -> Control:
	return _cruiser.get_node("Cockpit/Hud/ApproachPanel")

func _panel_text(label: String) -> String:
	return (_cruiser.get_node("Cockpit/Hud/ApproachPanel/Lines/" + label) as Label).text

func _test_panel_shows_within_range() -> int:
	var result := 0
	await _park(5000.0)
	# At rest with the pad: no time of arrival, an advised speed to start at.
	if not _panel().visible or not _panel_text("DistLabel").begins_with("DIST  ") or _panel_text("EtaLabel") != "ETA  —" or _panel_text("RelSpeedLabel") != "REL SPEED  0 m/s":
		print("FAIL _test_panel_shows_within_range: at 5 km visible %s, '%s' '%s' '%s'" % [_panel().visible, _panel_text("DistLabel"), _panel_text("EtaLabel"), _panel_text("RelSpeedLabel")])
		result = 1
	await _park(25000.0)
	if _panel().visible:
		print("FAIL _test_panel_shows_within_range: shown 25 km from the nearest dock")
		result = 1
	return result

func _test_panel_says_when_docking_is_possible() -> int:
	var result := 0
	# 120 m out, inside the 150 m docking range: the panel says whether
	# docking works now.
	await _park(120.0)
	var status := _cruiser.get_node("Cockpit/Hud/ApproachPanel/Lines/StatusLabel") as Label
	if not _panel().visible or not status.visible or status.text != DockingAssist.READY_TEXT:
		print("FAIL _test_panel_says_when_docking_is_possible: at rest 120 m out, visible %s, status '%s'" % [_panel().visible, status.text])
		result = 1
	_cruiser.velocity = _station.get_docking_port_velocity(0) + Vector3(25.0, 0.0, 0.0)
	await process_frame
	if status.text != DockingAssist.TOO_FAST_TEXT:
		print("FAIL _test_panel_says_when_docking_is_possible: 25 m/s against the pad gave '%s'" % status.text)
		result = 1
	return result
