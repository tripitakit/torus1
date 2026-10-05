extends RefCounted

# The interior's people: Quaternius' "Animated Human" (CC0), read from the
# raw glTF at run time, its walk baked into textures for the MultiMesh
# shaders (a vertex animation texture: every vertex's point and normal in
# every frame). Skinned on the CPU, so the bake runs headless too.
# 1.8 m tall, feet at y = 0, facing +Z, walking on the spot (the shader
# moves them along).

const PATH := "res://assets/people/animated_human.glb"
const WALK := "Human Armature|Walk"
const IDLE := "Human Armature|Idle"
const FRAMES := 16
# Metres covered by one walk cycle.
const STRIDE := 1.4
# Texels per texture row.
const ROW := 1024
const HEIGHT := 1.8
const LEG_BONES := ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End"]

static var _baked := {}
static var _points: Array = []

# Where in the walk cycle (0..1) a walker is after `distance` metres.
static func cycle_phase(distance: float) -> float:
	return fposmod(distance / STRIDE, 1.0)

# The skinned points of walk frame `frame`.
static func frame_points(frame: int) -> PackedVector3Array:
	bake()
	return _points[frame]

# {mesh, positions, normals, idle, frames, vertices, bones}: the walk mesh
# (frame 0 points; UV.x the part, UV.y the vertex's texel), the frames'
# points and normals (texel vertex + frame * vertices, ROW to a row), the
# idle pose as a plain mesh, and each vertex's heaviest bone. Baked once.
static func bake() -> Dictionary:
	if not _baked.is_empty():
		return _baked
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(PATH, state) != OK:
		push_error("PeopleModel: cannot read %s" % PATH)
		return _baked
	var root := document.generate_scene(state)
	var skin_node := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var armature: Transform3D = (skeleton.get_parent() as Node3D).transform * skeleton.transform
	var arrays: Array = skin_node.mesh.surface_get_arrays(0)
	var source := {"points": arrays[Mesh.ARRAY_VERTEX], "normals": arrays[Mesh.ARRAY_NORMAL],
		"bones": arrays[Mesh.ARRAY_BONES], "weights": arrays[Mesh.ARRAY_WEIGHTS], "skin": skin_node.skin}
	var count: int = source.points.size()
	var per: int = source.bones.size() / count

	# Each vertex's heaviest bone, by name.
	var bones := PackedStringArray()
	bones.resize(count)
	for i in range(count):
		var best := 0
		for k in range(per):
			if source.weights[i * per + k] > source.weights[i * per + best]:
				best = k
		bones[i] = skeleton.get_bone_name(source.skin.get_bind_bone(source.bones[i * per + best]))

	# Idle sets the scale and the feet, the walk the facing, for every frame.
	var idle := _skinned(skeleton, player.get_animation(IDLE), 0.0, armature, source)
	var walk := player.get_animation(WALK)
	var raw: Array = []
	for f in range(FRAMES):
		raw.append(_skinned(skeleton, walk, walk.length * f / FRAMES, armature, source))
	var frame := _normalising(idle[0], raw, bones)
	var points: Array = []
	var normals: Array = []
	for skinned in raw:
		points.append(_moved(skinned[0], frame))
		normals.append(_turned(skinned[1], frame.basis))
	# On the spot: the hips' sideways and forward drift taken off, frame by frame.
	var start := _bone_mean(points[0], bones, "Hips")
	for f in range(FRAMES):
		var drift := _bone_mean(points[f], bones, "Hips") - start
		drift.y = 0.0
		var moved: PackedVector3Array = points[f]
		for i in range(count):
			moved[i] -= drift
		points[f] = moved
	_points = points
	var idle_points := _moved(idle[0], frame)

	var parts := _parts(idle_points, bones)
	var uv := PackedVector2Array()
	uv.resize(count)
	for i in range(count):
		uv[i] = Vector2(parts[i], i)
	var walk_arrays := []
	walk_arrays.resize(Mesh.ARRAY_MAX)
	walk_arrays[Mesh.ARRAY_VERTEX] = points[0]
	walk_arrays[Mesh.ARRAY_NORMAL] = normals[0]
	walk_arrays[Mesh.ARRAY_TEX_UV] = uv
	walk_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, walk_arrays)
	var idle_arrays := walk_arrays.duplicate()
	idle_arrays[Mesh.ARRAY_VERTEX] = idle_points
	idle_arrays[Mesh.ARRAY_NORMAL] = _turned(idle[1], frame.basis)
	var idle_mesh := ArrayMesh.new()
	idle_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, idle_arrays)
	root.free()

	_baked = {"mesh": mesh, "positions": _texture(points), "normals": _texture(normals), "idle": idle_mesh,
		"frames": FRAMES, "vertices": count, "bones": bones}
	return _baked

# Points and normals of the skin posed by `animation` at `time`.
static func _skinned(skeleton: Skeleton3D, animation: Animation, time: float, armature: Transform3D, source: Dictionary) -> Array:
	skeleton.reset_bone_poses()
	for t in range(animation.get_track_count()):
		var bone := skeleton.find_bone(animation.track_get_path(t).get_concatenated_subnames())
		if bone < 0:
			continue
		match animation.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(t, time))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(t, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(t, time))
	# Global poses by hand: out of the tree the skeleton never refreshes them.
	var global: Array[Transform3D] = []
	global.resize(skeleton.get_bone_count())
	var done := PackedByteArray()
	done.resize(skeleton.get_bone_count())
	for b in range(skeleton.get_bone_count()):
		_global_pose(skeleton, b, global, done)
	var skin: Skin = source.skin
	var matrices: Array[Transform3D] = []
	for b in range(skin.get_bind_count()):
		matrices.append(armature * global[skin.get_bind_bone(b)] * skin.get_bind_pose(b))
	var count: int = source.points.size()
	var per: int = source.bones.size() / count
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	points.resize(count)
	normals.resize(count)
	for i in range(count):
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for k in range(per):
			var w: float = source.weights[i * per + k]
			if w > 0.0:
				var m: Transform3D = matrices[source.bones[i * per + k]]
				p += w * (m * source.points[i])
				n += w * (m.basis * source.normals[i])
		points[i] = p
		normals[i] = n.normalized()
	return [points, normals]

static func _global_pose(skeleton: Skeleton3D, bone: int, global: Array[Transform3D], done: PackedByteArray) -> Transform3D:
	if done[bone] == 0:
		var parent := skeleton.get_bone_parent(bone)
		var own := skeleton.get_bone_pose(bone)
		global[bone] = own if parent < 0 else _global_pose(skeleton, parent, global, done) * own
		done[bone] = 1
	return global[bone]

# Scale to HEIGHT, feet on y = 0 under the hips (from the idle points),
# turned so the walk goes toward +Z: the foot on the ground slides back.
static func _normalising(points: PackedVector3Array, walk: Array, bones: PackedStringArray) -> Transform3D:
	var low := INF
	var high := -INF
	for p in points:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var scale := HEIGHT / (high - low)
	var back := Vector3.ZERO
	for bone in ["LeftFoot", "RightFoot"]:
		var feet: Array[Vector3] = []
		var lowest := INF
		for skinned in walk:
			feet.append(_bone_mean(skinned[0], bones, bone))
			lowest = minf(lowest, feet[-1].y)
		var near := 0.03 * (high - low)
		for f in range(feet.size()):
			var next: Vector3 = feet[(f + 1) % feet.size()]
			if feet[f].y < lowest + near and next.y < lowest + near:
				back += next - feet[f]
	var yaw := Basis(Vector3.UP, atan2(-back.x, -back.z)).inverse()
	var hips := yaw * _bone_mean(points, bones, "Hips")
	var shift := Vector3(-hips.x, -low, -hips.z) * scale
	return Transform3D(yaw.scaled(Vector3.ONE * scale), shift)

static func _moved(points: PackedVector3Array, frame: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in range(points.size()):
		out[i] = frame * points[i]
	return out

static func _turned(normals: PackedVector3Array, basis: Basis) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(normals.size())
	var rotation := basis.orthonormalized()
	for i in range(normals.size()):
		out[i] = rotation * normals[i]
	return out

static func _bone_mean(points: PackedVector3Array, bones: PackedStringArray, bone: String) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for i in range(points.size()):
		if bones[i] == bone:
			sum += points[i]
			n += 1
	return sum / maxf(n, 1)

# UV.x parts as LoopTraffic's shader reads them: 1 the legs (dark), 2 the
# visor across the front of the head at eye height, 0 the suit and helmet.
static func _parts(points: PackedVector3Array, bones: PackedStringArray) -> PackedFloat32Array:
	var head_low := INF
	var head_high := -INF
	var head_front := -INF
	for i in range(points.size()):
		if bones[i] == "Head":
			head_low = minf(head_low, points[i].y)
			head_high = maxf(head_high, points[i].y)
			head_front = maxf(head_front, points[i].z)
	var parts := PackedFloat32Array()
	parts.resize(points.size())
	for i in range(points.size()):
		if bones[i] in LEG_BONES:
			parts[i] = 1.0
		elif bones[i] == "Head":
			var height := (points[i].y - head_low) / (head_high - head_low)
			parts[i] = 2.0 if height > 0.35 and height < 0.65 and points[i].z > head_front - 0.05 else 0.0
		else:
			parts[i] = 0.0
	return parts

# Frames of points (or normals) as one RGBAF texture, vertex + frame *
# vertices texels, ROW to a row.
static func _texture(frames: Array) -> ImageTexture:
	var count: int = (frames[0] as PackedVector3Array).size()
	var total := count * frames.size()
	var rows := ceili(float(total) / ROW)
	var data := PackedFloat32Array()
	data.resize(ROW * rows * 4)
	for f in range(frames.size()):
		var values: PackedVector3Array = frames[f]
		for i in range(count):
			var at := (f * count + i) * 4
			data[at] = values[i].x
			data[at + 1] = values[i].y
			data[at + 2] = values[i].z
			data[at + 3] = 1.0
	return ImageTexture.create_from_image(Image.create_from_data(ROW, rows, false, Image.FORMAT_RGBAF, data.to_byte_array()))
