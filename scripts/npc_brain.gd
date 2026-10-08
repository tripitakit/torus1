extends RefCounted

# The people's minds, without Ollama. Each person has a folder
# (assets/npc/people/<id>/): sheet.cfg (who they are), qa.txt (question |
# answer pairs in their own voice) and memories.txt (what they remember and
# think, first person); the world's facts are in assets/npc/facts.txt. The
# vectors of all of it (embeddinggemma) are baked into knowledge.json by
# tools/bake_npc_knowledge.gd. For a question: the pairs whose question is
# most like it, the nearest memories and facts, into the prompt; filters on
# what comes back. A line starting "[dopo:<clue>]" stays hidden until the
# player has that clue.

const PEOPLE_DIR := "res://assets/npc/people/"
const FACTS_TEXT := "res://assets/npc/facts.txt"
const KNOWLEDGE_JSON := "res://assets/npc/knowledge.json"
# Of the world: a question this like one of their pairs' questions, or this
# like a fact or memory; else they answer "don't know" without the model.
# This like a pair's question, its written answer is said as it is (the 1B
# model does not keep to examples it is shown). Measured on Ferrand's: a
# question as written 1.0, the same in other words 0.65-0.91, a wrong match
# up to 0.60 (so 0.63, just above); the real world 0.33-0.45 to pairs, under 0.30 to facts and
# memories.
const PAIR_TOPIC := 0.55
const ON_TOPIC := 0.30
const DIRECT := 0.63
# Put in the prompt: pairs, memories, world facts; lines of the talk kept.
const PAIRS := 3
const MEMORIES := 3
const FACTS := 2
const HISTORY := 6
const PLAYER := "TU"
const RULES := "Rispondi sempre in italiano, al massimo due frasi brevi, restando nel personaggio. Rispondi alla domanda in modo diretto e concreto, senza metafore. Dai del tu al pilota. Usa i tuoi ricordi e i fatti qui sotto; se non sai una cosa, dillo con parole tue, da persona. Non dire mai di essere un programma o un'intelligenza artificiale."
# A reply with one of these is the model speaking, not the person.
const BANNED := ["intelligenza artificiale", "modello linguistico", "modello di linguaggio", "google", "assistente virtuale", "sono un assistente", "sono un programma", "un programma informatico", "sistema operativo", "un'istanza", "chatbot", "openai"]
const CLUE_TAG := "[dopo:"

# The person `id`: {id, name, label, core, knows, dunno, remembers, qa:
# [{after, q, a}], memories: [{after, text}]}; {} if there is none.
static func person(id: String) -> Dictionary:
	var dir := PEOPLE_DIR + id + "/"
	var file := ConfigFile.new()
	if file.load(dir + "sheet.cfg") != OK:
		return {}
	return {
		"id": id,
		"name": str(file.get_value("person", "name", "")),
		"label": str(file.get_value("person", "label", "")),
		"core": str(file.get_value("person", "core", "")),
		"knows": PackedStringArray(file.get_value("person", "knows", [])),
		"dunno": PackedStringArray(file.get_value("person", "dunno", [])),
		"remembers": bool(file.get_value("person", "remembers", false)),
		"qa": parse_qa(FileAccess.get_file_as_string(dir + "qa.txt")),
		"memories": parse_lines(FileAccess.get_file_as_string(dir + "memories.txt")),
	}

# A generic person made someone: {name}, {surname}, {age}, {job}, {place}
# replaced from `identity` everywhere (the label upper case).
static func fill(sheet: Dictionary, identity: Dictionary) -> Dictionary:
	var out := sheet.duplicate(true)
	var words := {"name": str(identity.get("name", "")), "age": str(identity.get("age", "")), "job": str(identity.get("job", "")), "place": str(identity.get("place", ""))}
	words["surname"] = words.name.get_slice(" ", words.name.get_slice_count(" ") - 1)
	for key in ["name", "label", "core"]:
		out[key] = (out[key] as String).format(words)
	out.label = (out.label as String).to_upper()
	for pair in out.qa:
		pair.q = (pair.q as String).format(words)
		pair.a = (pair.a as String).format(words)
	for m in out.memories:
		m.text = (m.text as String).format(words)
	var dunno := PackedStringArray()
	for line in out.dunno:
		dunno.append(line.format(words))
	out.dunno = dunno
	return out

# A line's clue tag split off: [after ("" if none), the rest].
static func _clue(line: String) -> Array:
	if not line.begins_with(CLUE_TAG) or not line.contains("]"):
		return ["", line]
	var close := line.find("]")
	return [line.substr(CLUE_TAG.length(), close - CLUE_TAG.length()).strip_edges(), line.substr(close + 1).strip_edges()]

static func _clean_lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var clean := line.strip_edges()
		if clean != "" and not clean.begins_with("#"):
			out.append(clean)
	return out

# One entry a line: [{after, text}].
static func parse_lines(text: String) -> Array:
	var out := []
	for line in _clean_lines(text):
		var tagged := _clue(line)
		out.append({"after": tagged[0], "text": tagged[1]})
	return out

# "question | answer" a line: [{after, q, a}]; lines without a bar skipped.
static func parse_qa(text: String) -> Array:
	var out := []
	for line in _clean_lines(text):
		var tagged := _clue(line)
		var rest: String = tagged[1]
		if not rest.contains("|"):
			continue
		out.append({"after": tagged[0], "q": rest.get_slice("|", 0).strip_edges(), "a": rest.substr(rest.find("|") + 1).strip_edges()})
	return out

# facts.txt: "who | fact" a line: [{after, who, text}].
static func parse_facts(text: String) -> Array:
	var out := []
	for pair in parse_qa(text):
		out.append({"after": pair.after, "who": pair.q, "text": pair.a})
	return out

# The entries whose clue (if any) is among `clues` (clue -> true).
static func visible(entries: Array, clues: Dictionary) -> Array:
	return entries.filter(func(e): return e.get("after", "") == "" or clues.has(e.after))

# The baked vectors: {world: [{who, after, text, vector}], people: {id:
# {qa: [{vector}], memories: [{vector}]}}}; empty lists if not baked.
static func load_knowledge(path: String = KNOWLEDGE_JSON) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {"world": [], "people": {}}
	var world := []
	for f in data.get("world", []):
		world.append({"who": f.who, "after": f.get("after", ""), "text": f.text, "vector": vector_of(f.vector)})
	return {"world": world, "people": data.get("people", {})}

# A baked vector: base64 of its float32 bytes (or a plain list).
static func vector_of(baked) -> PackedFloat32Array:
	if baked is String:
		return Marshalls.base64_to_raw(baked).to_float32_array()
	return PackedFloat32Array(baked)

static func baked_vector(vector: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(vector.to_byte_array())

# `sheet` (filled or not) with the baked vectors of its pairs and memories,
# joined by place; none when the counts differ (baked before an edit).
static func with_vectors(sheet: Dictionary, knowledge: Dictionary) -> Dictionary:
	var out := sheet.duplicate(true)
	var baked: Dictionary = knowledge.get("people", {}).get(sheet.id, {})
	for key in ["qa", "memories"]:
		var vectors: Array = baked.get(key, [])
		if vectors.size() != (out[key] as Array).size():
			continue
		for i in range(vectors.size()):
			out[key][i]["vector"] = vector_of(vectors[i].vector)
	return out

static func _dot(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var sum := 0.0
	for i in range(mini(a.size(), b.size())):
		sum += a[i] * b[i]
	return sum

# How like `vector` the most alike entry of any of `lists` is (unit vectors).
static func best(lists: Array, vector: PackedFloat32Array) -> float:
	var top := -1.0
	for entries in lists:
		for e in entries:
			if e.has("vector"):
				top = maxf(top, _dot(e.vector, vector))
	return top

# Whether a question with `vector` is of their world: near one of `pairs`,
# or one of the entries of `others` (lists of facts, memories).
static func on_topic(pairs: Array, others: Array, vector: PackedFloat32Array) -> bool:
	return best([pairs], vector) >= PAIR_TOPIC or best(others, vector) >= ON_TOPIC

# The pair to answer with as written ({} if none is close enough).
static func direct(pairs: Array, vector: PackedFloat32Array) -> Dictionary:
	var top := pick(pairs, vector, 1)
	return top[0] if not top.is_empty() and _dot(top[0].vector, vector) >= DIRECT else {}

# The `count` entries most like `vector`, most alike first (entries without
# a vector skipped).
static func pick(entries: Array, vector: PackedFloat32Array, count: int) -> Array:
	var scored := []
	for e in entries:
		if e.has("vector"):
			scored.append([_dot(e.vector, vector), e])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for k in range(mini(count, scored.size())):
		out.append(scored[k][1])
	return out

# The world's facts `sheet` knows (by who).
static func known_facts(world: Array, sheet: Dictionary) -> Array:
	return world.filter(func(f): return f.who in sheet.knows)

# The chat for Ollama: who they are, the rules, their memories and facts;
# the pairs as earlier turns; the last HISTORY lines; the question.
static func messages(sheet: Dictionary, memories: PackedStringArray, facts: PackedStringArray, pairs: Array, history: Array, question: String) -> Array:
	var system: String = sheet.core + "\n" + RULES
	if not memories.is_empty():
		system += "\nI tuoi ricordi:\n- " + "\n- ".join(memories)
	if not facts.is_empty():
		system += "\nFatti che conosci:\n- " + "\n- ".join(facts)
	var out := [{"role": "system", "content": system}]
	for pair in pairs:
		out.append({"role": "user", "content": pair.q})
		out.append({"role": "assistant", "content": pair.a})
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
