extends RefCounted

# The passers-by of Torus1 one can talk to. The town walkers are drawn and
# moved by the shader (LoopTraffic, on loop_clock); here the CPU finds the
# one nearest ahead of the pilot from the same data, hides it (instance
# custom x) and puts a real person in its place (SeleneCrew's model in the
# walker's colours) who stops and turns. Who each one is comes from their
# loop's id: the same name every time.

const LoopTraffic = preload("res://scripts/loop_traffic.gd")
const SeleneCrew = preload("res://scripts/selene_crew.gd")

# Talking reach: this far, and this much ahead (cosine).
const REACH := 2.5
const AHEAD := 0.5
# The node names of the animated walkers near the camera.
const NEAR_PREFIX := "WalkersNear_"
const HIDDEN_META := "town_folk_hidden"
const NAMES := ["Lia", "Marco", "Giulia", "Tomás", "Aiko", "Omar", "Sara", "Luca", "Nadia", "Pavel", "Elena", "Kwame",
	"Irene", "Hugo", "Mei", "Davide", "Amara", "Jonas", "Chiara", "Rafael", "Yuki", "Ines", "Bruno", "Leila",
	"Matteo", "Anja", "Samir", "Rosa", "Viktor", "Noemi"]
const SURNAMES := ["Conti", "Moreau", "Okoye", "Tanaka", "Rossi", "Haddad", "Novak", "Silva", "Kowalski", "Bianchi",
	"Lindgren", "Mensah", "Ferreira", "Costa", "Weber", "Nakamura", "Greco", "Abebe", "Marino", "Duarte",
	"Sato", "Fontana", "Petrov", "Gallo", "Achebe", "Ricci", "Hansen", "Kaur", "Romano", "Vidal"]
const JOBS := ["la fornaia", "il tecnico dei filtri d'aria", "l'insegnante", "l'idraulico", "la contadina", "il macchinista del treno",
	"l'infermiera", "il cuoco", "la tecnica del cielo artificiale", "il giardiniere", "la commessa", "il manutentore dei ponti",
	"la biologa", "il postino", "la studentessa", "il pensionato", "l'elettricista", "la pescatrice del lago",
	"il barista", "la meccanica dei cruiser"]

# {name, age, job} of walker `id`.
static func identity(id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, "town folk"])
	return {
		"name": "%s %s" % [NAMES[rng.randi_range(0, NAMES.size() - 1)], SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)]],
		"age": rng.randi_range(18, 78),
		"job": JOBS[rng.randi_range(0, JOBS.size() - 1)],
	}

# A number for walker `index` of `node` (the loop's own id is not in the
# GPU data): its section's node, its group's and its place there.
static func walker_id(node: MultiMeshInstance3D, index: int) -> int:
	var section := String(node.get_parent().name) if node.get_parent() != null else ""
	return hash([section, String(node.name), index])

# The walker of `nodes` (LoopTraffic MultiMeshInstance3Ds, moved only by
# translation) nearest the pilot at `from` (global; facing -Z), within REACH
# and ahead, at loop time `time`; `away.call(pose, alpha)` true for those
# home for the night; hidden ones skipped. {node, index, pose (global)} or {}.
static func nearest(nodes: Array, from: Transform3D, time: float, corner: float, away: Callable) -> Dictionary:
	var forward := -from.basis.z.normalized()
	var best := {}
	var best_distance := REACH
	for node: MultiMeshInstance3D in nodes:
		if not is_instance_valid(node) or node.multimesh == null:
			continue
		var data := node.multimesh.buffer
		var shift := node.global_transform
		var hidden: Dictionary = node.get_meta(HIDDEN_META, {})
		for i in range(node.multimesh.instance_count):
			if hidden.has(i):
				continue
			var pose := shift * LoopTraffic.pose_from_data(data, i, time, corner)
			var offset := pose.origin - from.origin
			var flat := offset - from.basis.y.normalized() * offset.dot(from.basis.y.normalized())
			var distance := flat.length()
			if distance > best_distance or distance < 1e-3 or flat.normalized().dot(forward) < AHEAD:
				continue
			if away.call(pose, data[i * LoopTraffic.INSTANCE_FLOATS + 15]):
				continue
			best_distance = distance
			best = {"node": node, "index": i, "pose": pose}
	return best

# Walker `index` of `node` hidden from the shader, or shown again (also
# noted on the node: the custom data cannot be read back).
static func hide(node: MultiMeshInstance3D, index: int, hidden: bool) -> void:
	node.multimesh.set_instance_custom_data(index, Color(1.0 if hidden else 0.0, 0.0, 0.0, 0.0))
	var noted: Dictionary = node.get_meta(HIDDEN_META, {})
	if hidden:
		noted[index] = true
	else:
		noted.erase(index)
	node.set_meta(HIDDEN_META, noted)

# A real person all in `paint`, standing idle (to be placed).
static func stand_in(paint: Color) -> Node3D:
	var person := SeleneCrew.new_member("", paint)
	person.name = "TownPerson"
	person.ready.connect(person.idle, CONNECT_ONE_SHOT)
	return person

# A walker's colour (its paint) from the instance data.
static func paint(node: MultiMeshInstance3D, index: int) -> Color:
	var b := index * LoopTraffic.INSTANCE_FLOATS
	var data := node.multimesh.buffer
	return Color(data[b + 12], data[b + 13], data[b + 14])
