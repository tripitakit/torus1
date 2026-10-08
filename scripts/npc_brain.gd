extends RefCounted

# The people's minds, without Ollama: their sheets (assets/npc/people/*.cfg),
# the world's facts (assets/npc/facts.txt, their vectors baked into
# facts.json by tools/bake_npc_facts.gd), the facts picked for a question,
# the messages sent to the model and the filters on what comes back.

const PEOPLE_DIR := "res://assets/npc/people/"
const FACTS_TEXT := "res://assets/npc/facts.txt"
const FACTS_JSON := "res://assets/npc/facts.json"
# Questions less like every fact than this are not of the world: the person
# answers "don't know" without asking the model (measured: the world's
# questions 0.43-0.62, small talk 0.29-0.33, the real world 0.17-0.22).
const ON_TOPIC := 0.25
# Facts put in the prompt, lines of the talk kept.
const FACTS := 4
const HISTORY := 6
# Lines of facts that only say a question is of the world.
const SMALL_TALK := "chiacchiere"
const PLAYER := "TU"
const RULES := "Rispondi sempre in italiano, al massimo due frasi brevi, restando nel personaggio. Rispondi alla domanda in modo diretto e concreto, senza metafore; se ti chiedono chi sei, di' il tuo nome e il tuo lavoro. Dai del tu al pilota. Usa solo quello che sai; se non sai una cosa, dillo con parole tue, da persona. Non dire mai di essere un programma o un'intelligenza artificiale."
# A reply with one of these is the model speaking, not the person.
const BANNED := ["intelligenza artificiale", "modello linguistico", "modello di linguaggio", "google", "assistente virtuale", "sono un assistente", "sono un programma", "un programma informatico", "sistema operativo", "un'istanza", "chatbot", "openai"]

# The sheet `id`: {id, name, label, core, knows, examples, dunno, remembers};
# {} if there is none.
static func person(id: String) -> Dictionary:
	var file := ConfigFile.new()
	if file.load(PEOPLE_DIR + id + ".cfg") != OK:
		return {}
	return {
		"id": id,
		"name": str(file.get_value("person", "name", "")),
		"label": str(file.get_value("person", "label", "")),
		"core": str(file.get_value("person", "core", "")),
		"knows": PackedStringArray(file.get_value("person", "knows", [])),
		"examples": file.get_value("person", "examples", []),
		"dunno": PackedStringArray(file.get_value("person", "dunno", [])),
		"remembers": bool(file.get_value("person", "remembers", false)),
	}

# A generic sheet made someone: {name}, {surname}, {age}, {job}, {place}
# replaced from `identity` (the label upper case).
static func fill(sheet: Dictionary, identity: Dictionary) -> Dictionary:
	var out := sheet.duplicate(true)
	var words := {"name": str(identity.get("name", "")), "age": str(identity.get("age", "")), "job": str(identity.get("job", "")), "place": str(identity.get("place", ""))}
	words["surname"] = words.name.get_slice(" ", words.name.get_slice_count(" ") - 1)
	for key in ["name", "label", "core"]:
		out[key] = (out[key] as String).format(words)
	out.label = (out.label as String).to_upper()
	return out

# facts.txt's lines: [{who, text}], comments and blank lines skipped.
static func parse_facts(text: String) -> Array:
	var out := []
	for line in text.split("\n"):
		var clean := line.strip_edges()
		if clean == "" or clean.begins_with("#") or not clean.contains("|"):
			continue
		out.append({"who": clean.get_slice("|", 0).strip_edges(), "text": clean.substr(clean.find("|") + 1).strip_edges()})
	return out

# The baked facts: [{who, text, vector}]; [] if not baked.
static func load_facts(path: String = FACTS_JSON) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Array:
		return []
	var out := []
	for f in data:
		out.append({"who": f.who, "text": f.text, "vector": PackedFloat32Array(f.vector)})
	return out

static func _dot(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var sum := 0.0
	for i in range(mini(a.size(), b.size())):
		sum += a[i] * b[i]
	return sum

# How like the most alike fact `vector` is (the vectors are unit long).
static func best(facts: Array, vector: PackedFloat32Array) -> float:
	var top := -1.0
	for f in facts:
		top = maxf(top, _dot(f.vector, vector))
	return top

# The `count` facts most like `vector` among those whose who is in `knows`
# (small talk never).
static func relevant(facts: Array, vector: PackedFloat32Array, knows: PackedStringArray, count: int) -> PackedStringArray:
	var scored := []
	for f in facts:
		if f.who != SMALL_TALK and f.who in knows:
			scored.append([_dot(f.vector, vector), f.text])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := PackedStringArray()
	for k in range(mini(count, scored.size())):
		out.append(scored[k][1])
	return out

# The chat for Ollama: who they are, the rules and the facts; the example
# lines as earlier turns; the last HISTORY lines; the question.
static func messages(sheet: Dictionary, facts: PackedStringArray, history: Array, question: String) -> Array:
	var system: String = sheet.core + "\n" + RULES
	if not facts.is_empty():
		system += "\nFatti che conosci:\n- " + "\n- ".join(facts)
	var out := [{"role": "system", "content": system}]
	for pair in sheet.examples:
		out.append({"role": "user", "content": pair[0]})
		out.append({"role": "assistant", "content": pair[1]})
	out.append_array(history.slice(maxi(0, history.size() - HISTORY)))
	out.append({"role": "user", "content": question})
	return out

# The model speaking as itself (or nothing said): not to be shown.
static func rejected(reply: String) -> bool:
	if reply.strip_edges() == "":
		return true
	var low := reply.to_lower()
	for word in BANNED:
		if low.contains(word):
			return true
	var ia := RegEx.create_from_string("\\b(IA|AI)\\b")
	return ia.search(reply) != null

# The reply cleaned: stage directions (*sighs*, (pausa)) out, cut after its
# last whole sentence when it ran out mid-way.
static func trim(reply: String) -> String:
	var text := RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)").sub(reply, "", true)
	text = RegEx.create_from_string("\\s+").sub(text, " ", true).strip_edges()
	var last := -1
	for mark in [".", "!", "?", "…"]:
		last = maxi(last, text.rfind(mark))
	if last >= 0 and last < text.length() - 1:
		text = text.substr(0, last + 1)
	return text

# One of their "don't know" lines.
static func dunno(sheet: Dictionary, rng: RandomNumberGenerator) -> String:
	var lines: PackedStringArray = sheet.dunno
	return lines[rng.randi_range(0, lines.size() - 1)] if not lines.is_empty() else "Non lo so."
