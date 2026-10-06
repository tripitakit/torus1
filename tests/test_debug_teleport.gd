extends SceneTree

# The debug teleport (keys 1-9) on the real scene: each key puts the pilot
# where it says, from wherever they are (a section, on foot, Selene, an
# outpost), and the legend is on screen.

const SpeedLimit = preload("res://scripts/speed_limit.gd")

var _scene: Node3D
var _game_mode: Node
var _ship: CharacterBody3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_game_mode = _scene.get_node("GameMode")
	_ship = _scene.get_node("VoidCruiser")
	var failures := 0
	failures += _test_legend()
	failures += await _test_1_dock()
	failures += await _test_2_section()
	failures += await _test_3_town_pad()
	failures += await _test_4_selene_pad()
	failures += await _test_5_hangar()
	failures += await _test_6_telescope_pad()
	failures += await _test_7_area2_pad()
	failures += await _test_8_area2_airlock()
	failures += await _test_9_low_orbit_from_an_outpost()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_game_mode._unhandled_input(event)

func _wait_for_transition() -> void:
	await create_timer(0.1).timeout
	for i in range(300):
		if not _game_mode.is_transitioning():
			break
		await create_timer(0.05).timeout
	for i in range(3):
		await physics_frame

func _teleport(number: int) -> void:
	_press("teleport_%d" % number)
	await _wait_for_transition()

func _moon() -> Node3D:
	return _scene.get_node_or_null("PlanetSystem/Moon")

func _test_legend() -> int:
	var legend := _game_mode.get_node_or_null("DebugLegend/Label") as Label
	if legend == null or not legend.text.contains("1 DOCK") or not legend.text.contains("9 ORBITA"):
		print("FAIL _test_legend: %s" % (legend.text if legend != null else "none"))
		return 1
	return 0

func _test_1_dock() -> int:
	await _teleport(1)
	var station: Node3D = _scene.get_node("PlanetSystem/TorusStation")
	var port: Node3D = station.get_docking_port(0)
	var gap: float = _ship.global_position.distance_to(port.global_position)
	if _game_mode.mode != _game_mode.Mode.VOID or _ship.is_landed or _ship.in_moon_frame or gap > 200.0 or _ship.velocity.length() > 0.1:
		print("FAIL _test_1_dock: mode %d, landed %s, moon frame %s, %.0f m from the port" % [_game_mode.mode, _ship.is_landed, _ship.in_moon_frame, gap])
		return 1
	return 0

func _test_2_section() -> int:
	await _teleport(2)
	if _game_mode.mode != _game_mode.Mode.INTERIOR or _scene.get_node_or_null("InteriorWorld/InternalCruiser") == null:
		print("FAIL _test_2_section: mode %d" % _game_mode.mode)
		return 1
	return 0

func _test_3_town_pad() -> int:
	await _teleport(3)
	var walker := _scene.get_node_or_null("InteriorWorld/InteriorWalker") as Node3D
	var interior := _scene.get_node_or_null("InteriorWorld") as Node3D
	if _game_mode.mode != _game_mode.Mode.ON_FOOT_INSIDE or walker == null:
		print("FAIL _test_3_town_pad: mode %d" % _game_mode.mode)
		return 1
	var pad: Dictionary = interior.nearest_pad(walker.position)
	if pad.is_empty() or (pad.transform as Transform3D).origin.distance_to(walker.position) > 30.0:
		print("FAIL _test_3_town_pad: walker %s far from a pad" % walker.position)
		return 1
	return 0

func _on_pad(number: int) -> bool:
	var pad: Dictionary = _game_mode._ship_pad()
	return _game_mode.mode == _game_mode.Mode.VOID and _ship.is_landed and _ship.in_moon_frame and not pad.is_empty() and pad.number == number and not _ship.parked

func _test_4_selene_pad() -> int:
	await _teleport(4)
	if not _on_pad(1) or _scene.get_node_or_null("InteriorWorld") != null:
		print("FAIL _test_4_selene_pad: mode %d, pad %s" % [_game_mode.mode, _game_mode._ship_pad()])
		return 1
	return 0

func _test_5_hangar() -> int:
	await _teleport(5)
	var base := _scene.get_node_or_null("SeleneInterior") as Node3D
	if _game_mode.mode != _game_mode.Mode.IN_BASE or base == null or not base.near_lift((base.get_node("BaseWalker") as Node3D).position):
		print("FAIL _test_5_hangar: mode %d" % _game_mode.mode)
		return 1
	return 0

func _test_6_telescope_pad() -> int:
	await _teleport(6)
	if not _on_pad(7) or _scene.get_node_or_null("SeleneInterior") != null:
		print("FAIL _test_6_telescope_pad: mode %d, pad %s" % [_game_mode.mode, _game_mode._ship_pad()])
		return 1
	return 0

func _test_7_area2_pad() -> int:
	await _teleport(7)
	if not _on_pad(8):
		print("FAIL _test_7_area2_pad: mode %d, pad %s" % [_game_mode.mode, _game_mode._ship_pad()])
		return 1
	return 0

func _test_8_area2_airlock() -> int:
	await _teleport(8)
	if _game_mode.mode != _game_mode.Mode.ON_FOOT or _game_mode._near_hatch() != "area2":
		print("FAIL _test_8_area2_airlock: mode %d, by the hatch '%s'" % [_game_mode.mode, _game_mode._near_hatch()])
		return 1
	return 0

# In through the depot's hatch, then 9: out, aboard, 5 km over Selene, free.
func _test_9_low_orbit_from_an_outpost() -> int:
	_press("board")
	await _wait_for_transition()
	var inside: int = _game_mode.mode
	await _teleport(9)
	var height: float = _moon().altitude(_ship.global_position)
	var over_selene: float = _ship.global_position.distance_to(_moon().base_transform().origin)
	if inside != _game_mode.Mode.IN_OUTPOST or _game_mode.mode != _game_mode.Mode.VOID or _ship.is_landed or not _ship.in_moon_frame or absf(height - 5000.0) > 100.0 or over_selene > 5200.0 or _scene.get_node_or_null("OutpostInterior") != null:
		print("FAIL _test_9_low_orbit_from_an_outpost: inside mode %d, then mode %d, landed %s, %.0f m up, %.0f m from Selene" % [inside, _game_mode.mode, _ship.is_landed, height, over_selene])
		return 1
	return 0
