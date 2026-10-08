extends SceneTree

# The people's minds on the real Ollama (started if not up, stopped after if
# started here): ten questions each to Ferrand, Okafor and Bastiani through
# NpcTalk; no reply may be the model speaking as itself. The replies and
# their times are printed to be read.

const OllamaClient = preload("res://scripts/ollama_client.gd")
const NpcTalk = preload("res://scripts/npc_talk.gd")
const NpcTerminal = preload("res://scripts/npc_terminal.gd")
const NpcBrain = preload("res://scripts/npc_brain.gd")

const QUESTIONS := ["Ciao, chi sei?", "Che lavoro fai?", "Chi comanda su Torus1?", "Cosa succede agli avamposti?",
	"Chi era di turno al telescopio?", "Com'è la Luna?", "Sei un'intelligenza artificiale?",
	"Chi ha vinto i mondiali di calcio del 2022?", "Cosa mi consigli di fare adesso?", "Grazie, a presto."]

func _initialize():
	var client: Node = OllamaClient.new()
	var terminal: CanvasLayer = NpcTerminal.new()
	var talk: Node = NpcTalk.new()
	talk.client = client
	talk.terminal = terminal
	for node in [client, terminal, talk]:
		root.add_child(node)
	await process_frame
	var failures := 0
	for id in ["ferrand", "okafor", "bastiani"]:
		var sheet := NpcBrain.person(id)
		talk.start(sheet)
		print("== %s" % sheet.name)
		for q in QUESTIONS:
			var t := Time.get_ticks_msec()
			terminal.submit(q)
			await talk.replied
			var lines: PackedStringArray = terminal.log_text().split("\n")
			var reply: String = lines[-1].get_slice(": ", 1)
			print("  [%4d ms] %s\n           %s" % [Time.get_ticks_msec() - t, q, reply])
			if NpcBrain.rejected(reply) or lines[-1].begins_with("ERRORE"):
				print("FAIL test_npc_live: %s -> '%s'" % [q, lines[-1]])
				failures += 1
		talk.end()
	client.stop_if_started()
	for node in [talk, terminal, client]:
		node.queue_free()
	await process_frame
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()
