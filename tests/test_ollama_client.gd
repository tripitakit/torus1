extends SceneTree

# Talking to Ollama: the streamed lines read piece by piece (a line or a
# letter cut between two pieces), then live: the server up (started if it
# was not, stopped again if we started it), an embedding, a streamed chat.

const OllamaClient = preload("res://scripts/ollama_client.gd")

func _initialize():
	var failures := 0
	failures += _test_parse_lines()
	failures += await _test_live()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_parse_lines() -> int:
	var whole := ('{"message":{"content":"Ciao"},"done":false}\n{"message":{"content":" perché"},"done":false}\n{"message":{"content":""},"done":true}\n').to_utf8_buffer()
	# Cut inside the "é" (two bytes) and inside the second line.
	var cut := whole.find(0xA9)
	var first := whole.slice(0, cut)
	var second := whole.slice(cut)
	var a := OllamaClient.parse_lines(first)
	var b := OllamaClient.parse_lines((a[1] as PackedByteArray) + second)
	var pieces: Array = a[0] + b[0]
	if pieces.size() != 3 or pieces[0].message.content != "Ciao" or pieces[1].message.content != " perché" or not pieces[2].done or not (b[1] as PackedByteArray).is_empty():
		print("FAIL _test_parse_lines: %s / rest %s" % [pieces, b[1]])
		return 1
	return 0

func _test_live() -> int:
	var client: Node = OllamaClient.new()
	root.add_child(client)
	await process_frame
	var up: bool = await client.ensure_running()
	if not up:
		print("FAIL _test_live: Ollama did not start")
		client.free()
		return 1
	var vector: PackedFloat32Array = await client.embed("Chi comanda Selene?")
	var many: Array = await client.embed_many(PackedStringArray(["Uno.", "Due."]), false)
	var pieces := []
	client.piece.connect(func(text): pieces.append(text))
	client.chat([{"role": "user", "content": "Rispondi solo: ciao."}])
	var reply: Array = await client.finished
	var started: bool = client.started_server()
	client.stop_if_started()
	client.queue_free()
	await process_frame
	var length := 0.0
	for x in vector:
		length += x * x
	if many.size() != 2 or (many[1] as PackedFloat32Array).size() != 768 or vector.size() != 768 or absf(length - 1.0) > 0.01 or pieces.is_empty() or "".join(pieces) != reply[0] or reply[1] != "":
		print("FAIL _test_live: vector %d (%.3f), pieces %s, reply %s" % [vector.size(), length, pieces, reply])
		return 1
	print("live ok (server %s by the test)" % ("started" if started else "already up, not started"))
	return 0
