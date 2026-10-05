extends SceneTree

# The walker on a flat floor (Selene's interior): up is +Y; and the HUD's
# title, prompt and place lines.

const InteriorWalkerScript = preload("res://scripts/interior_walker.gd")

var _walker: CharacterBody3D

func _initialize():
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	root.add_child(floor_body)
	_walker = InteriorWalkerScript.new()
	_walker.flat = true
	root.add_child(_walker)
	await physics_frame
	var failures := 0
	failures += await _test_flat_gravity()
	failures += _test_prompt_and_place()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_flat_gravity() -> int:
	_walker.place(Vector3(0.0, 0.3, 0.0), Vector3(0.0, 0.0, -1.0))
	_walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}
	for i in range(30):
		await physics_frame
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	for i in range(120):
		await physics_frame
	var at: Vector3 = _walker.position
	if absf(at.y) > 0.05 or at.z > -2.5 or at.z < -3.5 or absf(at.x) > 0.05 or not _walker.transform.basis.y.is_equal_approx(Vector3.UP):
		print("FAIL _test_flat_gravity: at %s, up %s" % [at, _walker.transform.basis.y])
		return 1
	return 0

func _test_prompt_and_place() -> int:
	var hud: CanvasLayer = _walker.get_node("Hud")
	hud.set_title("IN BASE")
	hud.set_prompt("K EAGLE")
	hud.set_place("MAIN MISSION")
	var title := hud.get_node("Panel/Lines/TitleLabel") as Label
	var place := hud.get_node("Panel/Lines/PlaceLabel") as Label
	var prompt := hud.get_node("BoardLabel") as Control
	var result := 0
	if title.text != "IN BASE" or place.text != "MAIN MISSION" or not place.visible or not prompt.visible or (prompt.get_child(0) as Label).text != "K EAGLE":
		print("FAIL _test_prompt_and_place: '%s' '%s' %s" % [title.text, place.text, prompt.visible])
		result = 1
	hud.set_prompt("")
	if prompt.visible:
		print("FAIL _test_prompt_and_place: an empty prompt still shown")
		result = 1
	# The vehicles' prompt is still K BOARD.
	hud.set_board_prompt(true)
	if (prompt.get_child(0) as Label).text != "K BOARD" or not prompt.visible:
		print("FAIL _test_prompt_and_place: board prompt '%s'" % (prompt.get_child(0) as Label).text)
		result = 1
	return result
