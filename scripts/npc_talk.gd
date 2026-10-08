extends Node

# One talk with someone, from the question typed on the terminal to the
# reply written on it: the question's vector (embeddinggemma); off the
# world, one of their "don't know" lines without asking the model; close to
# one of their pairs, its answer as written; else their pairs whose
# question is most like it, their nearest memories and
# the nearest facts they know, their sheet and the talk so far to
# gemma3:1b, the reply shown as it streams; a reply from the model as
# itself asked once more, then replaced by "don't know". The named people
# remember the talk for the session, the others forget it on goodbye.

signal replied
signal ended

const NpcBrain = preload("res://scripts/npc_brain.gd")
const NO_SERVER := "OLLAMA NON RISPONDE"
const TRIES := 2

# OllamaClient (or anything with its methods and signals).
var client: Node
var terminal: CanvasLayer
# NpcBrain.load_knowledge() unless set before _ready.
var knowledge: Dictionary = {}
# The clues the player has (clue -> true): lines tagged [dopo:<clue>] show.
var clues: Dictionary = {}
var _person: Dictionary = {}
var _history: Array = []
# Talks kept: person id -> history.
var _memory := {}
var _streaming := false
# Bumped on every goodbye: a reply still coming is dropped.
var _session := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if knowledge.is_empty():
		knowledge = NpcBrain.load_knowledge()
	client.piece.connect(_on_piece)
	terminal.asked.connect(_on_asked)
	terminal.closed.connect(end)

func talking() -> bool:
	return not _person.is_empty()

func person() -> Dictionary:
	return _person

func start(sheet: Dictionary) -> void:
	_person = NpcBrain.with_vectors(sheet, knowledge)
	_history = (_memory.get(sheet.id, []) as Array).duplicate() if sheet.remembers else []
	var lines := []
	for m in _history:
		lines.append([NpcBrain.PLAYER if m.role == "user" else _who(), m.content])
	terminal.open(sheet.label, lines)

# Goodbye: what the named ones heard kept, a reply on its way dropped.
func end() -> void:
	if _person.is_empty():
		return
	if _person.remembers:
		_memory[_person.id] = _history
	_person = {}
	_history = []
	_session += 1
	_streaming = false
	client.cancel()
	if terminal.is_open():
		terminal.close()
	ended.emit()

func _who() -> String:
	return (_person.label as String).get_slice(" /", 0)

func _on_piece(text: String) -> void:
	if _streaming:
		terminal.append(text)

func _on_asked(question: String) -> void:
	if _person.is_empty():
		return
	var session := _session
	terminal.set_waiting(true)
	var reply := await _answer(question, session)
	if session != _session:
		return
	terminal.set_waiting(false)
	if reply != "":
		_history.append({"role": "user", "content": question})
		_history.append({"role": "assistant", "content": reply})
	replied.emit()

# The reply to `question`, shown on the terminal; "" on an error (shown).
func _answer(question: String, session: int) -> String:
	if not await client.ensure_running():
		terminal.show_error(NO_SERVER)
		return ""
	var vector: PackedFloat32Array = await client.embed(question)
	if session != _session:
		return ""
	if vector.is_empty():
		terminal.show_error(NO_SERVER)
		return ""
	terminal.begin_reply(_who())
	var world: Array = knowledge.get("world", [])
	var pairs := NpcBrain.visible(_person.qa, clues)
	var memories := NpcBrain.visible(_person.memories, clues)
	if not NpcBrain.on_topic(pairs, [world, memories], vector):
		var line := NpcBrain.dunno(_person, _rng)
		terminal.replace_reply(line)
		return line
	var written: Dictionary = NpcBrain.direct(pairs, vector)
	if not written.is_empty():
		terminal.replace_reply(written.a)
		return written.a
	var facts := NpcBrain.visible(NpcBrain.known_facts(world, _person), clues)
	var messages := NpcBrain.messages(_person, _texts(NpcBrain.pick(memories, vector, NpcBrain.MEMORIES)),
		_texts(NpcBrain.pick(facts, vector, NpcBrain.FACTS)), NpcBrain.pick(pairs, vector, NpcBrain.PAIRS), _history, question)
	for attempt in range(TRIES):
		terminal.replace_reply("")
		_streaming = true
		client.chat(messages)
		var result: Array = await client.finished
		_streaming = false
		if session != _session:
			return ""
		if result[1] != "":
			terminal.replace_reply("")
			terminal.show_error(NO_SERVER)
			return ""
		var text := NpcBrain.trim(result[0])
		if not NpcBrain.rejected(text):
			terminal.replace_reply(text)
			return text
	var fallback := NpcBrain.dunno(_person, _rng)
	terminal.replace_reply(fallback)
	return fallback

static func _texts(entries: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(e.text)
	return out
