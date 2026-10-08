extends SceneTree

# A talk, with a stand-in for Ollama: a question off the world gets a "don't
# know" without the model; a good reply is shown and remembered; a reply
# from the model as itself is asked again, then replaced; the named people
# remember, the passers-by forget; a dead server shows an error.

const NpcTalk = preload("res://scripts/npc_talk.gd")
const NpcBrain = preload("res://scripts/npc_brain.gd")
const NpcTerminal = preload("res://scripts/npc_terminal.gd")

class FakeClient extends Node:
	signal piece(text: String)
	signal finished(text: String, error: String)
	var up := true
	var replies: Array = []
	var chats := 0
	var last_messages: Array = []
	func ensure_running() -> bool:
		await get_tree().process_frame
		return up
	func embed(text: String, _as_query: bool = true) -> PackedFloat32Array:
		await get_tree().process_frame
		return PackedFloat32Array([-1.0, 0.0]) if text.contains("calcio") else PackedFloat32Array([1.0, 0.0])
	func chat(messages: Array) -> void:
		chats += 1
		last_messages = messages
		_reply.call_deferred(replies.pop_front() if not replies.is_empty() else "")
	func _reply(text: String) -> void:
		for word in text.split(" "):
			piece.emit(word + " ")
		finished.emit(text, "")
	func cancel() -> void:
		pass

func _initialize():
	var failures := 0
	failures += await _test_talk()
	failures += await _test_dead_server()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _facts() -> Array:
	return [
		{"who": "tutti", "text": "Fatto del mondo.", "vector": PackedFloat32Array([1.0, 0.0])},
		{"who": "ferrand", "text": "Fatto di Ferrand.", "vector": PackedFloat32Array([0.9, 0.1])},
		{"who": "okafor", "text": "Fatto di Okafor.", "vector": PackedFloat32Array([0.95, 0.05])},
	]

func _make(client: FakeClient) -> Array:
	var terminal: CanvasLayer = NpcTerminal.new()
	root.add_child(terminal)
	root.add_child(client)
	var talk: Node = NpcTalk.new()
	talk.client = client
	talk.terminal = terminal
	talk.facts = _facts()
	root.add_child(talk)
	await process_frame
	return [talk, terminal]

func _ask(talk: Node, terminal: CanvasLayer, question: String) -> void:
	terminal.submit(question)
	await talk.replied

func _test_talk() -> int:
	var client := FakeClient.new()
	var made: Array = await _make(client)
	var talk: Node = made[0]
	var terminal: CanvasLayer = made[1]
	var ferrand := NpcBrain.person("ferrand")
	talk.start(ferrand)
	await _ask(talk, terminal, "Chi ha vinto il campionato di calcio?")
	if client.chats != 0 or not ferrand.dunno.has(terminal.log_text().get_slice("FERRAND: ", 1)):
		print("FAIL _test_talk: off the world: %d chats, '%s'" % [client.chats, terminal.log_text()])
		return 1
	client.replies = ["Silenzio radio da ieri sera. Nessuno sa perché. E poi"]
	await _ask(talk, terminal, "Cosa succede?")
	var system: String = client.last_messages[0].content
	if not terminal.log_text().ends_with("FERRAND: Silenzio radio da ieri sera. Nessuno sa perché.") or not system.contains("Fatto di Ferrand.") or system.contains("Fatto di Okafor."):
		print("FAIL _test_talk: good reply '%s' / %s" % [terminal.log_text(), system])
		return 1
	client.replies = ["Sono un modello linguistico.", "Sono un'intelligenza artificiale."]
	await _ask(talk, terminal, "Chi sei davvero?")
	var last: String = terminal.log_text().get_slice("\n", terminal.log_text().get_slice_count("\n") - 1)
	if client.chats != 3 or not ferrand.dunno.has(last.get_slice("FERRAND: ", 1)):
		print("FAIL _test_talk: rejected twice: %d chats, '%s'" % [client.chats, last])
		return 1
	talk.end()
	# Ferrand remembers: back to him, the talk is there and goes to the model.
	talk.start(ferrand)
	client.replies = ["Di nuovo tu."]
	await _ask(talk, terminal, "Eccomi.")
	var said := []
	for m in client.last_messages:
		said.append(m.content)
	if not terminal.log_text().contains("Cosa succede?") or not said.has("Cosa succede?"):
		print("FAIL _test_talk: Ferrand forgot: '%s'" % terminal.log_text())
		return 1
	talk.end()
	# A passer-by forgets.
	var someone := NpcBrain.fill(NpcBrain.person("townsfolk"), {"name": "Lia Conti", "age": 30, "job": "fornaia", "place": "sezione 1"})
	talk.start(someone)
	client.replies = ["Buongiorno."]
	await _ask(talk, terminal, "Ciao.")
	talk.end()
	talk.start(someone)
	if terminal.log_text() != "" or not talk.talking():
		print("FAIL _test_talk: the passer-by remembers '%s'" % terminal.log_text())
		return 1
	talk.end()
	if talk.talking() or terminal.is_open():
		print("FAIL _test_talk: still talking after end")
		return 1
	for node in [talk, terminal, client]:
		node.queue_free()
	await process_frame
	return 0

func _test_dead_server() -> int:
	var client := FakeClient.new()
	client.up = false
	var made: Array = await _make(client)
	var talk: Node = made[0]
	var terminal: CanvasLayer = made[1]
	talk.start(NpcBrain.person("okafor"))
	await _ask(talk, terminal, "Ciao.")
	if not terminal.log_text().contains("ERRORE: OLLAMA NON RISPONDE"):
		print("FAIL _test_dead_server: '%s'" % terminal.log_text())
		return 1
	for node in [talk, terminal, client]:
		node.queue_free()
	await process_frame
	return 0
