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
		if text.contains("calcio"):
			return PackedFloat32Array([-1.0, 0.0])
		return PackedFloat32Array([0.0, 1.0]) if text.contains("diretta") else PackedFloat32Array([1.0, 0.0])
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

# Facts of Selene and of Torus1 (Ferrand knows only the first), and a
# Ferrand with three pairs and two memories, vectors already on.
func _knowledge() -> Dictionary:
	return {"world": [
		{"who": "selene", "after": "", "text": "Fatto di Selene.", "vector": PackedFloat32Array([1.0, 0.0])},
		{"who": "torus1", "after": "", "text": "Fatto di Torus1.", "vector": PackedFloat32Array([0.95, 0.05])},
	], "people": {}}

func _ferrand() -> Dictionary:
	var sheet := NpcBrain.person("ferrand")
	sheet.qa = [
		{"after": "", "q": "Cosa succede?", "a": "Silenzio radio.", "vector": PackedFloat32Array([0.6, -0.8])},
		{"after": "", "q": "Chi sei?", "a": "Ferrand.", "vector": PackedFloat32Array([0.5, -0.866])},
		{"after": "", "q": "Una domanda diretta?", "a": "Risposta scritta.", "vector": PackedFloat32Array([0.0, 1.0])},
		{"after": "segreto", "q": "Il segreto?", "a": "Nascosto.", "vector": PackedFloat32Array([0.55, -0.835])},
	]
	sheet.memories = [{"after": "", "text": "Ricordo di Ferrand.", "vector": PackedFloat32Array([0.8, 0.2])}]
	return sheet

func _make(client: FakeClient) -> Array:
	var terminal: CanvasLayer = NpcTerminal.new()
	root.add_child(terminal)
	root.add_child(client)
	var talk: Node = NpcTalk.new()
	talk.client = client
	talk.terminal = terminal
	talk.knowledge = _knowledge()
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
	var ferrand := _ferrand()
	talk.start(ferrand)
	await _ask(talk, terminal, "Chi ha vinto il campionato di calcio?")
	if client.chats != 0 or not ferrand.dunno.has(terminal.log_text().get_slice("FERRAND: ", 1)):
		print("FAIL _test_talk: off the world: %d chats, '%s'" % [client.chats, terminal.log_text()])
		return 1
	client.replies = ["Silenzio radio da ieri sera. Nessuno sa perché. E poi"]
	await _ask(talk, terminal, "Cosa succede?")
	var system: String = client.last_messages[0].content
	var asked_pairs := []
	for m in client.last_messages.slice(1, -1):
		asked_pairs.append(m.content)
	# Ferrand's facts and memory in; Torus1's fact and the pair hidden behind a
	# clue out; his pairs as earlier turns.
	if not terminal.log_text().ends_with("FERRAND: Silenzio radio da ieri sera. Nessuno sa perché.") or not system.contains("Fatto di Selene.") or system.contains("Fatto di Torus1.") \
			or not system.contains("Ricordo di Ferrand.") or not asked_pairs.has("Cosa succede?") or asked_pairs.has("Il segreto?"):
		print("FAIL _test_talk: good reply '%s' / %s / %s" % [terminal.log_text(), system, asked_pairs])
		return 1
	# With the clue, the hidden pair comes in.
	talk.clues = {"segreto": true}
	client.replies = ["Va bene."]
	await _ask(talk, terminal, "Cosa succede davvero?")
	talk.clues = {}
	var with_clue := []
	for m in client.last_messages:
		with_clue.append(m.content)
	if not with_clue.has("Il segreto?"):
		print("FAIL _test_talk: the pair behind the clue stayed hidden")
		return 1
	# A question close to one of his pairs: the written answer, no model.
	await _ask(talk, terminal, "Domanda diretta, per favore?")
	if client.chats != 2 or not terminal.log_text().ends_with("FERRAND: Risposta scritta."):
		print("FAIL _test_talk: direct answer: %d chats, '%s'" % [client.chats, terminal.log_text()])
		return 1
	client.replies = ["Sono un modello linguistico.", "Sono un'intelligenza artificiale."]
	await _ask(talk, terminal, "Chi sei davvero?")
	var last: String = terminal.log_text().get_slice("\n", terminal.log_text().get_slice_count("\n") - 1)
	if client.chats != 4 or not ferrand.dunno.has(last.get_slice("FERRAND: ", 1)):
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
	if not terminal.log_text().contains("Domanda diretta, per favore?") or not said.has("Domanda diretta, per favore?"):
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
