extends SceneTree

# The people's minds without Ollama: their folders (sheet, question and
# answer pairs, memories), the lines hidden until a clue is found, what is
# picked for a question, the prompt's messages, the filters on a reply.

const NpcBrain = preload("res://scripts/npc_brain.gd")

const NAMED := ["ferrand", "okafor", "bastiani"]
const GENERIC := ["selene_crew", "townsfolk"]

func _init():
	var failures := 0
	failures += _test_sheets()
	failures += _test_content()
	failures += _test_fill()
	failures += _test_parse()
	failures += _test_visible()
	failures += _test_pick_and_best()
	failures += _test_on_topic_and_direct()
	failures += _test_messages()
	failures += _test_with_vectors()
	failures += _test_rejected()
	failures += _test_trim()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_sheets() -> int:
	for id in NAMED + GENERIC:
		var p := NpcBrain.person(id)
		if p.is_empty() or p.core == "" or p.label == "" or p.dunno.size() < 2 or p.knows.is_empty() or p.qa.is_empty() or p.memories.is_empty():
			print("FAIL _test_sheets: %s %s" % [id, p.keys()])
			return 1
	var ferrand := NpcBrain.person("ferrand")
	if ferrand.name != "Tomas Ferrand" or not ferrand.remembers or NpcBrain.person("townsfolk").remembers or not ("selene" in ferrand.knows):
		print("FAIL _test_sheets: ferrand %s" % ferrand.name)
		return 1
	return 0

# 100 pairs for the named people, 40 for the generic ones; 30-50 memories;
# answers of two sentences at most.
func _test_content() -> int:
	var sentence := RegEx.create_from_string("[.!?…]+(\\s|$)")
	for id in NAMED + GENERIC:
		var p := NpcBrain.person(id)
		var wanted := 100 if id in NAMED else 40
		var memories_wanted := 30 if id in NAMED else 12
		if p.qa.size() < wanted or p.memories.size() < memories_wanted:
			print("FAIL _test_content: %s has %d pairs, %d memories" % [id, p.qa.size(), p.memories.size()])
			return 1
		var questions := {}
		for pair in p.qa:
			if pair.q == "" or pair.a == "" or sentence.search_all(pair.a).size() > 2:
				print("FAIL _test_content: %s '%s' -> '%s'" % [id, pair.q, pair.a])
				return 1
			if questions.has(pair.q.to_lower()):
				print("FAIL _test_content: %s asks '%s' twice" % [id, pair.q])
				return 1
			questions[pair.q.to_lower()] = true
	return 0

func _test_fill() -> int:
	var p := NpcBrain.fill(NpcBrain.person("townsfolk"), {"name": "Lia Conti", "age": 34, "job": "la fornaia", "place": "sezione 1"})
	var text: String = p.core + p.label
	for pair in p.qa:
		text += pair.q + pair.a
	for m in p.memories:
		text += m.text
	if not p.core.contains("Lia Conti") or text.contains("{") or not p.label.contains("CONTI"):
		print("FAIL _test_fill: %s" % text.substr(0, 300))
		return 1
	return 0

func _test_parse() -> int:
	var lines := NpcBrain.parse_lines("# commento\n\nUno.\n[dopo:diario] Due.  \n")
	if lines != [{"after": "", "text": "Uno."}, {"after": "diario", "text": "Due."}]:
		print("FAIL _test_parse: lines %s" % [lines])
		return 1
	var qa := NpcBrain.parse_qa("Chi sei? | Tomas.\n[dopo:lista] Le casse? | Mancano tre.\nsenza barra\n")
	if qa != [{"after": "", "q": "Chi sei?", "a": "Tomas."}, {"after": "lista", "q": "Le casse?", "a": "Mancano tre."}]:
		print("FAIL _test_parse: qa %s" % [qa])
		return 1
	var facts := NpcBrain.parse_facts("tutti | Uno.\n[dopo:x] selene|Due.\n")
	if facts != [{"after": "", "who": "tutti", "text": "Uno."}, {"after": "x", "who": "selene", "text": "Due."}]:
		print("FAIL _test_parse: facts %s" % [facts])
		return 1
	var world := NpcBrain.parse_facts(FileAccess.get_file_as_string(NpcBrain.FACTS_TEXT))
	var kinds := {}
	for f in world:
		kinds[f.who] = true
	if kinds.keys().size() != 3 or not (kinds.has("tutti") and kinds.has("selene") and kinds.has("torus1")):
		print("FAIL _test_parse: world facts by %s" % [kinds.keys()])
		return 1
	return 0

func _test_visible() -> int:
	var entries := [{"after": "", "text": "A"}, {"after": "diario", "text": "B"}]
	if NpcBrain.visible(entries, {}).size() != 1 or NpcBrain.visible(entries, {"diario": true}).size() != 2:
		print("FAIL _test_visible")
		return 1
	return 0

func _v(x: float, y: float) -> PackedFloat32Array:
	return PackedFloat32Array([x, y])

func _test_pick_and_best() -> int:
	var entries := [
		{"text": "A", "vector": _v(1.0, 0.0)},
		{"text": "B", "vector": _v(0.8, 0.6)},
		{"text": "C", "vector": _v(0.6, 0.8)},
		{"text": "D"},
	]
	var picked := NpcBrain.pick(entries, _v(0.0, 1.0), 2)
	if picked.size() != 2 or picked[0].text != "C" or picked[1].text != "B":
		print("FAIL _test_pick_and_best: picked %s" % [picked])
		return 1
	var other := [{"text": "E", "vector": _v(0.0, 1.0)}]
	if not is_equal_approx(NpcBrain.best([entries, other], _v(0.0, 1.0)), 1.0) or not is_equal_approx(NpcBrain.best([entries], _v(1.0, 0.0)), 1.0) or NpcBrain.best([entries, other], _v(-0.7071, -0.7071)) > NpcBrain.ON_TOPIC:
		print("FAIL _test_pick_and_best: best")
		return 1
	return 0

# Of the world: a pair's question close enough, or a fact or a memory;
# else not. A pair close enough is answered as written.
func _test_on_topic_and_direct() -> int:
	var pairs := [{"q": "Chi sei?", "a": "Ferrand.", "vector": _v(1.0, 0.0)}]
	var facts := [{"text": "F", "vector": _v(0.0, 1.0)}]
	var cases := [
		[_v(0.6, 0.8), true],   # a fact at 0.8
		[_v(0.6, -0.8), true],  # the pair at 0.6
		[_v(0.4, -0.9165), false], # the pair at 0.4, no fact
	]
	for c in cases:
		if NpcBrain.on_topic(pairs, [facts], c[0]) != c[1]:
			print("FAIL _test_on_topic_and_direct: on topic %s" % [c[0]])
			return 1
	var exact: Dictionary = NpcBrain.direct(pairs, _v(1.0, 0.0))
	var near: Dictionary = NpcBrain.direct(pairs, _v(0.6, 0.8))
	if exact.get("a", "") != "Ferrand." or not near.is_empty():
		print("FAIL _test_on_topic_and_direct: direct %s / %s" % [exact, near])
		return 1
	return 0

func _test_messages() -> int:
	var p := NpcBrain.person("ferrand")
	var history := [{"role": "user", "content": "Ciao."}, {"role": "assistant", "content": "Ciao, pilota."}]
	var pairs := [{"q": "Chi sei?", "a": "Ferrand."}, {"q": "Che fai?", "a": "Comando."}]
	var m := NpcBrain.messages(p, PackedStringArray(["Ricordo uno."]), PackedStringArray(["Fatto uno."]), pairs, history, "Dove sono?")
	var roles := []
	for x in m:
		roles.append(x.role)
	var system: String = m[0].content
	if roles != ["system", "user", "assistant", "user", "assistant", "user", "assistant", "user"] or not system.contains("Tomas Ferrand") \
			or not system.contains("Ricordo uno.") or not system.contains("Fatto uno.") or m[1].content != "Chi sei?" or m[4].content != "Comando." \
			or m[-1].content != "Dove sono?" or m[-2].content != "Ciao, pilota.":
		print("FAIL _test_messages: %s\n%s" % [roles, system])
		return 1
	var long := []
	for k in range(20):
		long.append({"role": "user" if k % 2 == 0 else "assistant", "content": str(k)})
	var m2 := NpcBrain.messages(p, PackedStringArray(), PackedStringArray(), [], long, "?")
	if m2.size() != 1 + NpcBrain.HISTORY + 1 or m2[-2].content != "19":
		print("FAIL _test_messages: history %d" % m2.size())
		return 1
	return 0

# The baked vectors joined to a (filled) sheet's pairs and memories by
# their place; a sheet whose counts differ from the baked ones gets none.
func _test_with_vectors() -> int:
	var sheet := {"id": "x", "qa": [{"after": "", "q": "Q1", "a": "A1"}, {"after": "", "q": "Q2", "a": "A2"}], "memories": [{"after": "", "text": "M"}]}
	var knowledge := {"world": [], "people": {"x": {"qa": [{"vector": [1.0, 0.0]}, {"vector": [0.0, 1.0]}], "memories": [{"vector": [0.5, 0.5]}]}}}
	var joined := NpcBrain.with_vectors(sheet, knowledge)
	if joined.qa[1].vector != PackedFloat32Array([0.0, 1.0]) or joined.memories[0].vector.size() != 2 or joined.qa[0].a != "A1":
		print("FAIL _test_with_vectors: %s" % [joined])
		return 1
	var stale := {"world": [], "people": {"x": {"qa": [{"vector": [1.0, 0.0]}], "memories": []}}}
	if NpcBrain.with_vectors(sheet, stale).qa[0].has("vector"):
		print("FAIL _test_with_vectors: stale vectors used")
		return 1
	return 0

func _test_rejected() -> int:
	for bad in ["Sono un sistema operativo.", "Sono un'intelligenza artificiale.", "Come modello linguistico non posso.", "Sono stato creato da Google.", "Sono un programma.", "Sono una IA."]:
		if not NpcBrain.rejected(bad):
			print("FAIL _test_rejected: let through '%s'" % bad)
			return 1
	for good in ["Ciao, via di qui.", "La radio tace da ieri sera.", ""]:
		if NpcBrain.rejected(good) != (good == ""):
			print("FAIL _test_rejected: '%s'" % good)
			return 1
	return 0

func _test_trim() -> int:
	var cases := {
		"Silenzio radio. Nessuno risponde. E poi c": "Silenzio radio. Nessuno risponde.",
		"Va bene!": "Va bene!",
		"Senza punto finale": "Senza punto finale",
		"  *Sospira* Sono stanco.  ": "Sono stanco.",
	}
	for raw in cases:
		if NpcBrain.trim(raw) != cases[raw]:
			print("FAIL _test_trim: '%s' -> '%s'" % [raw, NpcBrain.trim(raw)])
			return 1
	return 0
