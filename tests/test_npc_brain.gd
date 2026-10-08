extends SceneTree

# The people's minds without Ollama: their sheets, the facts picked for a
# question, the prompt's messages, the filters on a reply.

const NpcBrain = preload("res://scripts/npc_brain.gd")

func _init():
	var failures := 0
	failures += _test_sheets()
	failures += _test_fill()
	failures += _test_parse_facts()
	failures += _test_relevant_and_best()
	failures += _test_messages()
	failures += _test_rejected()
	failures += _test_trim()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_sheets() -> int:
	for id in ["ferrand", "okafor", "bastiani", "selene_crew", "townsfolk"]:
		var p := NpcBrain.person(id)
		if p.is_empty() or p.core == "" or p.label == "" or p.examples.size() < 2 or p.dunno.size() < 2 or p.knows.is_empty():
			print("FAIL _test_sheets: %s %s" % [id, p])
			return 1
	var ferrand := NpcBrain.person("ferrand")
	if ferrand.name != "Tomas Ferrand" or not ferrand.remembers or NpcBrain.person("townsfolk").remembers or not ("ferrand" in ferrand.knows):
		print("FAIL _test_sheets: ferrand %s" % ferrand)
		return 1
	return 0

func _test_fill() -> int:
	var p := NpcBrain.fill(NpcBrain.person("townsfolk"), {"name": "Lia Conti", "age": 34, "job": "fornaia", "place": "sezione 1"})
	if not p.core.contains("Lia Conti") or not p.core.contains("fornaia") or p.core.contains("{") or not p.label.contains("CONTI"):
		print("FAIL _test_fill: %s / %s" % [p.label, p.core])
		return 1
	return 0

func _test_parse_facts() -> int:
	var facts := NpcBrain.parse_facts("# commento\n\ntutti | Uno.\nselene|Due.  \n")
	if facts != [{"who": "tutti", "text": "Uno."}, {"who": "selene", "text": "Due."}]:
		print("FAIL _test_parse_facts: %s" % [facts])
		return 1
	var real := NpcBrain.parse_facts(FileAccess.get_file_as_string("res://assets/npc/facts.txt"))
	var kinds := {}
	for f in real:
		kinds[f.who] = true
	for who in ["tutti", "selene", "torus1", "ferrand", "okafor", "bastiani", "chiacchiere"]:
		if not kinds.has(who):
			print("FAIL _test_parse_facts: no '%s' facts" % who)
			return 1
	return 0

func _v(x: float, y: float) -> PackedFloat32Array:
	return PackedFloat32Array([x, y])

func _test_relevant_and_best() -> int:
	var facts := [
		{"who": "tutti", "text": "A", "vector": _v(1.0, 0.0)},
		{"who": "selene", "text": "B", "vector": _v(0.8, 0.6)},
		{"who": "ferrand", "text": "C", "vector": _v(0.6, 0.8)},
		{"who": "chiacchiere", "text": "D", "vector": _v(0.0, 1.0)},
		{"who": "okafor", "text": "E", "vector": _v(0.99, 0.14)},
	]
	var picked := NpcBrain.relevant(facts, _v(0.0, 1.0), PackedStringArray(["tutti", "selene", "ferrand"]), 2)
	if picked != PackedStringArray(["C", "B"]):
		print("FAIL _test_relevant_and_best: picked %s" % [picked])
		return 1
	if not is_equal_approx(NpcBrain.best(facts, _v(0.0, 1.0)), 1.0) or NpcBrain.best(facts, _v(-1.0, 0.0)) > NpcBrain.ON_TOPIC:
		print("FAIL _test_relevant_and_best: best")
		return 1
	return 0

func _test_messages() -> int:
	var p := NpcBrain.person("ferrand")
	var history := [{"role": "user", "content": "Ciao."}, {"role": "assistant", "content": "Ciao, pilota."}]
	var m := NpcBrain.messages(p, PackedStringArray(["Fatto uno.", "Fatto due."]), history, "Dove sono?")
	var roles := []
	for x in m:
		roles.append(x.role)
	var expected := ["system"]
	for k in range(p.examples.size()):
		expected.append_array(["user", "assistant"])
	expected.append_array(["user", "assistant", "user"])
	var system: String = m[0].content
	if roles != expected or not system.contains("Tomas Ferrand") or not system.contains("Fatto due.") or m[-1].content != "Dove sono?" or m[-2].content != "Ciao, pilota.":
		print("FAIL _test_messages: %s\n%s" % [roles, system])
		return 1
	# Only the last HISTORY lines.
	var long := []
	for k in range(20):
		long.append({"role": "user" if k % 2 == 0 else "assistant", "content": str(k)})
	var m2 := NpcBrain.messages(p, PackedStringArray(), long, "?")
	if m2.size() != 1 + p.examples.size() * 2 + NpcBrain.HISTORY + 1 or m2[-2].content != "19":
		print("FAIL _test_messages: history %d" % m2.size())
		return 1
	return 0

func _test_rejected() -> int:
	for bad in ["Sono un sistema operativo.", "Sono un'intelligenza artificiale.", "Come modello linguistico non posso.", "Sono stato creato da Google.", "Sono un assistente.", "Sono un programma.", "Sono una IA."]:
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
