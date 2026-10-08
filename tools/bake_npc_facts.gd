extends SceneTree

# The world's facts (assets/npc/facts.txt) with their embeddinggemma vectors
# into assets/npc/facts.json, for NpcBrain to pick from. Run again after
# changing facts.txt (Ollama is started if it is not up):
#   godot-double --headless --path . -s tools/bake_npc_facts.gd

const NpcBrain = preload("res://scripts/npc_brain.gd")
const OllamaClient = preload("res://scripts/ollama_client.gd")

func _initialize() -> void:
	var client: Node = OllamaClient.new()
	root.add_child(client)
	await process_frame
	if not await client.ensure_running():
		push_error("bake_npc_facts: Ollama is not running")
		quit(1)
		return
	var out := []
	for fact in NpcBrain.parse_facts(FileAccess.get_file_as_string(NpcBrain.FACTS_TEXT)):
		var vector: PackedFloat32Array = await client.embed(fact.text, false)
		if vector.is_empty():
			push_error("bake_npc_facts: no vector for '%s'" % fact.text)
			client.stop_if_started()
			quit(1)
			return
		out.append({"who": fact.who, "text": fact.text, "vector": Array(vector)})
	var file := FileAccess.open(ProjectSettings.globalize_path(NpcBrain.FACTS_JSON), FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	print("bake_npc_facts: %d facts" % out.size())
	client.stop_if_started()
	client.queue_free()
	await process_frame
	quit()
