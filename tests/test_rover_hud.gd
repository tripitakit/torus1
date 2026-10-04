extends SceneTree

# The rover's HUD: its lines, the heading, the board prompt.

const RoverHud = preload("res://scripts/rover_hud.gd")

func _initialize():
	var failures := 0
	failures += _test_lines()
	failures += _test_heading()
	failures += await _test_board_prompt_and_panel()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_lines() -> int:
	var r: Dictionary = RoverHud.readout(15.0, 273.4, 12.2, -1240.4, true)
	var back: Dictionary = RoverHud.readout(-3.0, 0.0, 0.0, 15.0, false)
	if r.spd != "SPD  54 km/h  15.0 m/s" or r.hdg != "HDG  273°" or r.slope != "SLOPE  12°" or r.alt != "ALT  -1240 m" or r.lights != "LIGHTS ON" or back.spd != "SPD  11 km/h  3.0 m/s" or back.hdg != "HDG  000°" or back.lights != "LIGHTS OFF":
		print("FAIL _test_lines: %s / %s" % [r, back])
		return 1
	return 0

func _test_heading() -> int:
	# Pole +Y, standing on the +Z side (up +Z): north is +Y, east is +X.
	var pole := Vector3.UP
	var up := Vector3.BACK
	var north: float = RoverHud.heading(Vector3.UP, up, pole)
	var east: float = RoverHud.heading(Vector3.RIGHT, up, pole)
	var west: float = RoverHud.heading(Vector3.LEFT, up, pole)
	if absf(north) > 1e-3 or absf(east - 90.0) > 1e-3 or absf(west - 270.0) > 1e-3:
		print("FAIL _test_heading: north %.2f, east %.2f, west %.2f" % [north, east, west])
		return 1
	return 0

func _test_board_prompt_and_panel() -> int:
	var hud: CanvasLayer = RoverHud.new()
	root.add_child(hud)
	await process_frame
	hud.show_readout(RoverHud.readout(5.0, 90.0, 3.0, 10.0, true))
	hud.set_board_prompt(true)
	var board := hud.get_node("BoardLabel") as Control
	var spd := hud.get_node("Panel/Lines/SpdLabel") as Label
	var shown := board.visible
	hud.set_board_prompt(false)
	var result := 0
	if not shown or board.visible or spd.text != "SPD  18 km/h  5.0 m/s":
		print("FAIL _test_board_prompt_and_panel: prompt %s then %s, speed line '%s'" % [shown, board.visible, spd.text])
		result = 1
	hud.free()
	return result
