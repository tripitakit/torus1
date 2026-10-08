extends SceneTree

# What the people can draw on, with its embeddinggemma vectors, into
# assets/npc/knowledge.json for NpcBrain: the world's facts (facts.txt) and
# every person's memories as texts, their pairs' questions as questions (the
# player's question is compared with them). Run again after changing
# anything in assets/npc/ (Ollama is started if it is not up):
#   godot-double --headless --path . -s tools/bake_npc_knowledge.gd

const NpcBrain = preload("res://scripts/npc_brain.gd")
const OllamaClient = preload("res://scripts/ollama_client.gd")
const BATCH := 32

var _client: Node

func _initialize() -> void:
	_client = OllamaClient.new()
	root.add_child(_client)
	await process_frame
	if not await _client.ensure_running():
		_fail("Ollama is not running")
		return
	var world := NpcBrain.parse_facts(FileAccess.get_file_as_string(NpcBrain.FACTS_TEXT))
	var vectors: Array = await _embed(world.map(func(f): return f.text), false)
	if vectors.size() != world.size():
		_fail("no vectors for the world's facts")
		return
	var out := {"world": [], "people": {}}
	for i in range(world.size()):
		out.world.append({"who": world[i].who, "after": world[i].after, "text": world[i].text, "vector": NpcBrain.baked_vector(vectors[i])})
	var count := world.size()
	for id in DirAccess.get_directories_at(NpcBrain.PEOPLE_DIR):
		var sheet := NpcBrain.person(id)
		if sheet.is_empty():
			continue
		var qa: Array = await _embed(sheet.qa.map(func(p): return p.q), true)
		var memories: Array = await _embed(sheet.memories.map(func(m): return m.text), false)
		if qa.size() != sheet.qa.size() or memories.size() != sheet.memories.size():
			_fail("no vectors for %s" % id)
			return
		out.people[id] = {"qa": qa.map(func(v): return {"vector": NpcBrain.baked_vector(v)}), "memories": memories.map(func(v): return {"vector": NpcBrain.baked_vector(v)})}
		count += qa.size() + memories.size()
	var file := FileAccess.open(ProjectSettings.globalize_path(NpcBrain.KNOWLEDGE_JSON), FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	print("bake_npc_knowledge: %d vectors, %d people" % [count, out.people.size()])
	_client.stop_if_started()
	_client.queue_free()
	await process_frame
	quit()

func _embed(texts: Array, as_query: bool) -> Array:
	var out := []
	for start in range(0, texts.size(), BATCH):
		var part: Array = await _client.embed_many(PackedStringArray(texts.slice(start, start + BATCH)), as_query)
		if part.is_empty():
			return []
		out.append_array(part)
	return out

func _fail(why: String) -> void:
	push_error("bake_npc_knowledge: " + why)
	_client.stop_if_started()
	quit(1)
