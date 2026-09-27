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
