extends SceneTree

# The 1970s terminal at the bottom of the screen: the header, the lines of
# the talk, the reply written as it comes, the line to type on; Enter asks,
# Esc says goodbye.

const NpcTerminal = preload("res://scripts/npc_terminal.gd")

func _initialize():
	var failures := 0
	failures += await _test_terminal()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_terminal() -> int:
	var terminal: CanvasLayer = NpcTerminal.new()
	root.add_child(terminal)
	await process_frame
	if terminal.is_open() or terminal.visible:
		print("FAIL _test_terminal: open at start")
		return 1
	var asked := []
	var closed := [0]
	terminal.asked.connect(func(text): asked.append(text))
	terminal.closed.connect(func(): closed[0] += 1)
	terminal.open("FERRAND / COMANDO SELENE", [["TU", "Ciao."], ["FERRAND", "Sei in ritardo."]])
	await process_frame
	if not terminal.is_open() or not terminal.header_text().contains("FERRAND / COMANDO SELENE") or not terminal.log_text().contains("Sei in ritardo."):
		print("FAIL _test_terminal: open: %s / %s" % [terminal.header_text(), terminal.log_text()])
		return 1
	# Enter with nothing typed asks nothing; with words it asks and clears.
	terminal.submit("   ")
	terminal.submit("Cosa succede?")
	if asked != ["Cosa succede?"] or terminal.typed_text() != "" or not terminal.log_text().contains("Cosa succede?"):
		print("FAIL _test_terminal: asked %s, typed '%s'" % [asked, terminal.typed_text()])
		return 1
	terminal.begin_reply("FERRAND")
	terminal.append("Silenzio ")
	terminal.append("radio.")
	if not terminal.log_text().contains("FERRAND: Silenzio radio."):
		print("FAIL _test_terminal: streamed '%s'" % terminal.log_text())
		return 1
	terminal.replace_reply("Non lo so.")
	if terminal.log_text().contains("Silenzio") or not terminal.log_text().ends_with("FERRAND: Non lo so."):
		print("FAIL _test_terminal: replaced '%s'" % terminal.log_text())
		return 1
	# While waiting, Enter asks nothing.
	terminal.set_waiting(true)
	terminal.submit("Ancora?")
	terminal.set_waiting(false)
	terminal.show_error("OLLAMA NON RISPONDE")
	if asked.size() != 1 or not terminal.log_text().contains("ERRORE: OLLAMA NON RISPONDE"):
		print("FAIL _test_terminal: waiting/error %s '%s'" % [asked, terminal.log_text()])
		return 1
	# Only the last lines are kept.
	for k in range(30):
		terminal.add_line("TU", "riga %d" % k)
	if terminal.log_text().contains("riga 0\n") or not terminal.log_text().contains("riga 29"):
		print("FAIL _test_terminal: lines kept '%s'" % terminal.log_text())
		return 1
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	await process_frame
	if closed[0] != 1 or terminal.is_open():
		print("FAIL _test_terminal: Esc closed %d, open %s" % [closed[0], terminal.is_open()])
		return 1
	terminal.free()
	return 0
