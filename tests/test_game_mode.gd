extends SceneTree

# Runs on the real scene (2000 sections, world-origin rebase active).

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

var _failures := 0
var _scene: Node3D
var _game_mode: Node
var _station: Node3D
var _void_cruiser: CharacterBody3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_game_mode = _scene.get_node("GameMode")
	_station = _scene.get_node("PlanetSystem/TorusStation")
	_void_cruiser = _scene.get_node("VoidCruiser")
	# The tests put the ship where they want it; no input-driven flight.
	_void_cruiser.set_physics_process(false)

	_failures += await _test_dock_prompt_follows_distance_and_speed()
	_failures += await _test_dock_key_far_from_port_does_nothing()
	_failures += await _test_dock_key_near_port_enters_interior()
	_failures += await _test_undock_sign_and_key_return_outside()
	_failures += await _test_undock_key_far_from_dock_does_nothing()
	_failures += await _test_second_dock_press_during_transition_is_ignored()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _port() -> Node3D:
	return _station.get_docking_port(0)

func _park_near_port(distance: float, speed: float) -> void:
	var outward: Vector3 = _port().global_transform.basis.x.normalized()
	_void_cruiser.global_position = _port().global_position + outward * distance
	_void_cruiser.velocity = outward * speed

func _press_dock() -> void:
	var event := InputEventAction.new()
	event.action = "dock"
	event.pressed = true
	_game_mode._unhandled_input(event)

func _wait_for_transition() -> void:
	await create_timer(1.2).timeout

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _test_dock_prompt_follows_distance_and_speed() -> int:
	var label: Label = _void_cruiser.get_node("Cockpit/Hud/Panel/Lines/DockLabel")
	var result := 0
	_park_near_port(100.0, 0.0)
	await _frames(3)
	if not label.visible:
		print("FAIL _test_dock_prompt_follows_distance_and_speed: hidden at 100 m and 0 m/s")
		result = 1
	_park_near_port(300.0, 0.0)
	await _frames(3)
	if label.visible:
		print("FAIL _test_dock_prompt_follows_distance_and_speed: shown at 300 m")
		result = 1
	_park_near_port(100.0, 30.0)
	await _frames(3)
	if label.visible:
		print("FAIL _test_dock_prompt_follows_distance_and_speed: shown at 30 m/s")
		result = 1
	return result

func _test_dock_key_far_from_port_does_nothing() -> int:
	_park_near_port(300.0, 0.0)
	await _frames(2)
	_press_dock()
	await _wait_for_transition()
	if _game_mode.is_inside():
		print("FAIL _test_dock_key_far_from_port_does_nothing: docked from 300 m")
		_game_mode.exit_interior()
		return 1
	return 0

func _test_dock_key_near_port_enters_interior() -> int:
	_park_near_port(100.0, 0.0)
	await _frames(2)
	_press_dock()
	await _wait_for_transition()
	var result := 0
	if not _game_mode.is_inside() or _game_mode.docked_bridge != 0:
		print("FAIL _test_dock_key_near_port_enters_interior: not inside bridge 0 (inside=%s bridge=%d)" % [_game_mode.is_inside(), _game_mode.docked_bridge])
		return 1
	var interior := _scene.get_node_or_null("InteriorWorld")
	if interior == null:
		print("FAIL _test_dock_key_near_port_enters_interior: no InteriorWorld")
		return 1
	if _void_cruiser.is_inside_tree() or _station.is_inside_tree():
		print("FAIL _test_dock_key_near_port_enters_interior: the outside world is still in the tree")
		result = 1
	if _scene.get_node_or_null("WorldEnvironment") == null:
		print("FAIL _test_dock_key_near_port_enters_interior: WorldEnvironment was removed")
		result = 1
	if root.get_camera_3d() != interior.get_node("InternalCruiser/Camera"):
		print("FAIL _test_dock_key_near_port_enters_interior: the window renders %s" % root.get_camera_3d())
		result = 1
	if not is_zero_approx((_game_mode.get_node("Fade/Curtain") as ColorRect).color.a):
		print("FAIL _test_dock_key_near_port_enters_interior: the fade did not clear")
		result = 1
	return result

func _test_undock_sign_and_key_return_outside() -> int:
	var interior: Node3D = _scene.get_node("InteriorWorld")
	var undock_sign: Label3D = interior.get_node("Dock/Sign")
	await _frames(3)
	var result := 0
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_READY_COLOR):
		print("FAIL _test_undock_sign_and_key_return_outside: sign not lit at the spawn point")
		result = 1
	_press_dock()
	await _wait_for_transition()
	if _game_mode.is_inside() or not _void_cruiser.is_inside_tree() or _scene.get_node_or_null("InteriorWorld") != null:
		print("FAIL _test_undock_sign_and_key_return_outside: still inside after undocking")
		return 1
	var outward: Vector3 = _port().global_transform.basis.x.normalized()
	var distance: float = _void_cruiser.global_position.distance_to(_port().global_position)
	if absf(distance - 60.0) > 0.5 or not _void_cruiser.velocity.is_zero_approx():
		print("FAIL _test_undock_sign_and_key_return_outside: %.2f m from the port (expected 60), velocity %s" % [distance, _void_cruiser.velocity])
		result = 1
	if (-_void_cruiser.global_transform.basis.z).dot(outward) < 0.99:
		print("FAIL _test_undock_sign_and_key_return_outside: the bow does not point outward")
		result = 1
	if root.get_camera_3d() != _void_cruiser.get_node("Cockpit/PilotCamera"):
		print("FAIL _test_undock_sign_and_key_return_outside: the window renders %s, expected PilotCamera" % root.get_camera_3d())
		result = 1
	return result

func _test_undock_key_far_from_dock_does_nothing() -> int:
	_game_mode.enter_interior(0)
	var interior: Node3D = _scene.get_node("InteriorWorld")
	var cruiser: CharacterBody3D = interior.get_node("InternalCruiser")
	cruiser.set_physics_process(false)
	cruiser.position = Vector3(0.0, 0.0, -5000.0)
	await _frames(3)
	var result := 0
	if not (interior.get_node("Dock/Sign") as Label3D).modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
		print("FAIL _test_undock_key_far_from_dock_does_nothing: sign lit 5 km from the dock")
		result = 1
	_press_dock()
	await _wait_for_transition()
	if not _game_mode.is_inside():
		print("FAIL _test_undock_key_far_from_dock_does_nothing: undocked from 5 km away")
		return 1
	_game_mode.exit_interior()
	return result

func _test_second_dock_press_during_transition_is_ignored() -> int:
	_park_near_port(100.0, 0.0)
	await _frames(2)
	_press_dock()
	await _frames(2)
	_press_dock()
	await _wait_for_transition()
	var result := 0
	var interiors := _scene.find_children("InteriorWorld*", "Node3D", false, false)
	if not _game_mode.is_inside() or interiors.size() != 1:
		print("FAIL _test_second_dock_press_during_transition_is_ignored: inside=%s with %d interiors" % [_game_mode.is_inside(), interiors.size()])
		result = 1
	if _game_mode.is_inside():
		_game_mode.exit_interior()
	return result
