extends Node3D

# Quaternius' detailed trees (TreeModels) round the camera in the sections:
# every REBUILD_STEP the camera moves, the trees within REACH of it are taken
# from the chunks' tree buffers (TerrainDressing, registered here) on worker
# threads and put in one MultiMesh per variant, children of the chunk's
# Trees node (its frame: an origin shift moves them along). The detailed
# trees hide beyond TreeModels.DETAIL and the simple shapes within it, both
# measured from the camera each frame: no tree twice, none missing.

const TreeModels = preload("res://scripts/tree_models.gd")

const GROUP := "near_tree_chunks"
const REBUILD_STEP := 40.0
const REACH := TreeModels.DETAIL + REBUILD_STEP + 20.0
# As TerrainDressing.TREE_SINK and TREE_FLOATS (no preload: it preloads us).
const TREE_SINK := 0.5
const TREE_FLOATS := 16

var _last := Vector3(INF, INF, INF)
var _task := -1
var _jobs: Array = []
var _results: Array = []
var _built: Array = []

# Marks a chunk's Trees node as having trees: its buffers (conifers,
# broadleaves, TerrainDressing's layout), the section's radius and the
# trees' bounds in the node's frame.
static func register(trees: Node3D, conifers: PackedFloat32Array, broadleaves: PackedFloat32Array, radius: float, bounds: AABB) -> void:
	trees.add_to_group(GROUP)
	trees.set_meta("near_conifers", conifers)
	trees.set_meta("near_broadleaves", broadleaves)
	trees.set_meta("near_radius", radius)
	trees.set_meta("near_bounds", bounds)

# The trees of `buffer` within `reach` of `camera` (the buffer's frame), one
# transform buffer (12 floats a tree) per variant: where they stand, scaled
# evenly to their height. Pure: safe on a worker thread.
static func select(buffer: PackedFloat32Array, conifer: bool, camera: Vector3, reach: float, radius: float) -> Array:
	var parts := []
	for k in range(TreeModels.variants().size()):
		parts.append(PackedFloat32Array())
	@warning_ignore("integer_division")
	for i in range(buffer.size() / TREE_FLOATS):
		var b := i * TREE_FLOATS
		var origin := Vector3(buffer[b + 3], buffer[b + 7], buffer[b + 11])
		if origin.distance_to(camera) > reach:
			continue
		var height := radius + TREE_SINK - Vector2(origin.x, origin.y).length()
		var by := Vector3(buffer[b + 1], buffer[b + 5], buffer[b + 9])
		var tall := by.length()
		var side := Vector3(buffer[b], buffer[b + 4], buffer[b + 8]).normalized() * tall
		var front := Vector3(buffer[b + 2], buffer[b + 6], buffer[b + 10]).normalized() * tall
		var variant := TreeModels.variant_for(origin, conifer, height)
		var part: PackedFloat32Array = parts[variant]
		part.append_array(PackedFloat32Array([side.x, by.x, front.x, origin.x, side.y, by.y, front.y, origin.y, side.z, by.z, front.z, origin.z]))
		parts[variant] = part
	return parts

func _ready() -> void:
	# Read the models here, on the main thread, before any worker wants them.
	TreeModels.variants()

func _process(_delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_task):
			return
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
		_apply()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	if at.distance_to(_last) < REBUILD_STEP:
		return
	_last = at
	_jobs = []
	for trees: Node3D in get_tree().get_nodes_in_group(GROUP):
		var local := trees.to_local(at)
		if _distance_to_box(local, trees.get_meta("near_bounds")) > REACH:
			continue
		_jobs.append({"node": trees, "camera": local, "conifers": trees.get_meta("near_conifers"), "broadleaves": trees.get_meta("near_broadleaves"), "radius": trees.get_meta("near_radius")})
	_results = []
	_results.resize(_jobs.size())
	if _jobs.is_empty():
		_apply()
		return
	_task = WorkerThreadPool.add_group_task(_run, _jobs.size(), -1, true, "NearTrees")

func _run(index: int) -> void:
	var job: Dictionary = _jobs[index]
	var parts := select(job.conifers, true, job.camera, REACH, job.radius)
	var broad := select(job.broadleaves, false, job.camera, REACH, job.radius)
	for k in range(parts.size()):
		var merged: PackedFloat32Array = parts[k]
		merged.append_array(broad[k])
		parts[k] = merged
	_results[index] = parts

# The new detailed trees into their chunks; chunks no longer near emptied.
func _apply() -> void:
	var variants := TreeModels.variants()
	var now: Array = []
	for i in range(_jobs.size()):
		var trees: Node3D = _jobs[i].node
		if not is_instance_valid(trees) or _results[i] == null:
			continue
		now.append(trees)
		var holder := trees.get_node_or_null("NearTrees") as Node3D
		if holder == null:
			holder = Node3D.new()
			holder.name = "NearTrees"
			trees.add_child(holder)
			for k in range(variants.size()):
				var multimesh := MultiMesh.new()
				multimesh.transform_format = MultiMesh.TRANSFORM_3D
				multimesh.mesh = variants[k].mesh
				var node := MultiMeshInstance3D.new()
				node.name = "Near_%02d" % k
				node.multimesh = multimesh
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.custom_aabb = trees.get_meta("near_bounds")
				holder.add_child(node)
		var parts: Array = _results[i]
		for k in range(variants.size()):
			var multimesh := (holder.get_child(k) as MultiMeshInstance3D).multimesh
			var data: PackedFloat32Array = parts[k]
			@warning_ignore("integer_division")
			multimesh.instance_count = data.size() / 12
			if not data.is_empty():
				multimesh.buffer = data
	for trees in _built:
		if is_instance_valid(trees) and not now.has(trees):
			var holder := (trees as Node3D).get_node_or_null("NearTrees")
			if holder != null:
				for node: MultiMeshInstance3D in holder.get_children():
					node.multimesh.instance_count = 0
	_built = now

static func _distance_to_box(point: Vector3, box: AABB) -> float:
	var d := Vector3(maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0.0), maxf(maxf(box.position.y - point.y, point.y - box.end.y), 0.0), maxf(maxf(box.position.z - point.z, point.z - box.end.z), 0.0))
	return d.length()
