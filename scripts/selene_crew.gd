extends RefCounted

# Selene's crew: Quaternius' Animated Human (CC0) with its real skeleton and
# clips (a handful of people seen up close), in Moonbase Alpha's oatmeal
# suits with the left sleeve in the department's colour. They walk their
# rounds (SeleneLayout.routes), sit at Main Mission's desks, or work on
# their feet.

const PeopleModel = preload("res://scripts/people_model.gd")

const DEPARTMENTS := {
	"main_mission": Color(0.95, 0.45, 0.1),
	"medical": Color(0.95, 0.95, 0.95),
	"security": Color(0.45, 0.2, 0.6),
	"technical": Color(0.95, 0.8, 0.15),
	"command": Color(0.08, 0.08, 0.09),
}
# The pilot on foot: the crew stop for them.
const PILOT_GROUP := "selene_pilot"
const SPEED := 1.2
const WAITS := Vector2(3.0, 8.0)
# The pilot this close ahead stops a walker, for this long at most.
const BLOCK_REACH := 1.2
const BLOCK_MAX := 10.0
const RADIUS := 0.3
const HEIGHT := 1.8

const SLEEVE_BONES := ["LeftArm", "LeftForeArm"]
const SKIN_BONES := ["Head", "HeadTop_End", "Neck"]
const BOOT_BONES := ["LeftFoot", "LeftToeBase", "LeftToe_End", "RightFoot", "RightToeBase", "RightToe_End"]

const SHADER := """
shader_type spatial;
uniform vec3 sleeve : source_color = vec3(0.95, 0.45, 0.1);
varying flat float part;
void vertex() {
	part = UV.x;
}
void fragment() {
	vec3 colour = vec3(0.78, 0.72, 0.6);
	if (part > 3.5) {
		colour = vec3(0.16, 0.1, 0.06);
	} else if (part > 2.5) {
		colour = sleeve;
	} else if (part > 1.5) {
		colour = vec3(0.85, 0.66, 0.52);
	} else if (part > 0.5) {
		colour = vec3(0.2, 0.17, 0.15);
	}
	ALBEDO = colour;
	ROUGHNESS = 0.8;
}
"""

static var _template: Node3D
static var _mesh: ArrayMesh
static var _materials := {}

# The glTF scene once: clips looping, the walk on the spot (no drift of the
# hips along the floor).
static func _scene() -> Node3D:
	if _template != null:
		return _template
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_file(PeopleModel.PATH, state)
	_template = document.generate_scene(state)
	var player := _template.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in [PeopleModel.WALK, PeopleModel.IDLE, "Human Armature|Working"]:
		var animation := player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR
		if clip != PeopleModel.WALK:
			continue
		for t in range(animation.get_track_count()):
			if animation.track_get_type(t) == Animation.TYPE_POSITION_3D and animation.track_get_path(t).get_concatenated_subnames() == "Hips":
				var start: Vector3 = animation.track_get_key_value(t, 0)
				for k in range(animation.track_get_key_count(t)):
					var at: Vector3 = animation.track_get_key_value(t, k)
					animation.track_set_key_value(t, k, Vector3(start.x, at.y, start.z))
	return _template

# The skinned mesh with UV.x parts: 0 suit, 1 boots, 2 skin (face, hands),
# 3 the left sleeve, 4 hair.
static func member_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var source := (_scene().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var arrays: Array = source.surface_get_arrays(0)
	var bones: PackedStringArray = PeopleModel.bake().bones
	# The head's extent (facing +Z): hair over the top and down the back.
	var points := PeopleModel.frame_points(0)
	var low := INF
	var high := -INF
	var front := -INF
	for i in range(bones.size()):
		if bones[i] == "Head":
			low = minf(low, points[i].y)
			high = maxf(high, points[i].y)
			front = maxf(front, points[i].z)
	var uv := PackedVector2Array()
	uv.resize(bones.size())
	for i in range(bones.size()):
		var part := 0.0
		var up := (points[i].y - low) / (high - low)
		if bones[i] in ["Head", "HeadTop_End"] and (up > 0.72 or (up > 0.35 and points[i].z < front - 0.14)):
			part = 4.0
		elif bones[i] in SLEEVE_BONES:
			part = 3.0
		elif bones[i] in SKIN_BONES or bones[i].contains("Hand"):
			part = 2.0
		elif bones[i] in BOOT_BONES:
			part = 1.0
		uv[i] = Vector2(part, 0.0)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var per: int = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / bones.size()
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	return _mesh

static func _material(department: String) -> ShaderMaterial:
	if not _materials.has(department):
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = SHADER
		material.set_shader_parameter("sleeve", DEPARTMENTS[department])
		_materials[department] = material
	return _materials[department]

static func new_member(department: String) -> CrewMember:
	var member := CrewMember.new()
	member.name = "CrewMember"
	var model := _scene().duplicate() as Node3D
	model.name = "Model"
	# The frame faces +Z; a member faces -Z like every node.
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * (PeopleModel.bake().frame as Transform3D)
	member.add_child(model)
	var body := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	body.mesh = member_mesh()
	body.material_override = _material(department)
	member.setup(department, model, body)
	return member

# One of the crew: a kinematic capsule (the pilot bumps into it) carrying
# the model; walking a route there and back, sitting, working or idle.
class CrewMember extends AnimatableBody3D:
	var department := ""
	var _model: Node3D
	var _body: MeshInstance3D
	var _skeleton: Skeleton3D
	var _player: AnimationPlayer
	var _seated := false
	var _route := PackedVector3Array()
	var _target := 1
	var _step := 1
	var _wait := 0.0
	var _blocked := 0.0
	var _rng := RandomNumberGenerator.new()

	func setup(dept: String, model: Node3D, body: MeshInstance3D) -> void:
		department = dept
		_model = model
		_body = body
		_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		_player = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		sync_to_physics = false
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = RADIUS
		capsule.height = HEIGHT
		shape.shape = capsule
		shape.position.y = HEIGHT * 0.5
		add_child(shape)

	func body() -> MeshInstance3D:
		return _body

	func is_seated() -> bool:
		return _seated

	func idle() -> void:
		_play(PeopleModel.IDLE, 1.0)

	func work() -> void:
		_play("Human Armature|Working", 1.0)

	func _play(clip: String, speed: float) -> void:
		if _player.current_animation != clip:
			_player.play(clip)
		_player.speed_scale = speed

	# Walk `points` there and back, waiting a few seconds at each end.
	func walk_route(points: PackedVector3Array, seed: int) -> void:
		_route = points
		_rng.seed = seed
		_target = 1
		_step = 1
		position = points[0]
		_face(points[1] - points[0])

	func _face(direction: Vector3) -> void:
		direction.y = 0.0
		if direction.length() > 1e-4:
			transform.basis = Basis.looking_at(direction.normalized(), Vector3.UP)

	func _physics_process(delta: float) -> void:
		if _route.size() < 2:
			return
		if _wait > 0.0:
			_wait -= delta
			idle()
			return
		var forward := -transform.basis.z
		if _pilot_ahead(forward):
			_blocked += delta
			if _blocked < BLOCK_MAX:
				idle()
				return
		else:
			_blocked = 0.0
		var goal: Vector3 = _route[_target]
		var to_goal := goal - position
		var reach := SPEED * delta
		_play(PeopleModel.WALK, SPEED / PeopleModel.STRIDE)
		if to_goal.length() <= reach:
			position = goal
			var last := _target + _step
			if last < 0 or last >= _route.size():
				_step = -_step
				_wait = _rng.randf_range(WAITS.x, WAITS.y)
			_target += _step
			_face(_route[_target] - position)
			return
		position += to_goal.normalized() * reach
		_face(to_goal)

	func _pilot_ahead(forward: Vector3) -> bool:
		for pilot in get_tree().get_nodes_in_group(PILOT_GROUP):
			var offset: Vector3 = (pilot as Node3D).global_position - global_position
			offset.y = 0.0
			if offset.length() <= BLOCK_REACH and offset.normalized().dot(forward) > 0.5:
				return true
		return false

	# Seated: the idle pose with the thighs turned forward level, the shins
	# straight down, the hips lowered until the feet are back on the floor.
	func sit() -> void:
		_seated = true
		_route = PackedVector3Array()
		_player.stop()
		_player.active = false
		if not is_inside_tree():
			# Posed again once in the scene.
			ready.connect(_pose_seated, CONNECT_ONE_SHOT)
		_pose_seated()

	func _pose_seated() -> void:
		var animation := _player.get_animation(PeopleModel.IDLE)
		_skeleton.reset_bone_poses()
		for t in range(animation.get_track_count()):
			var bone := _skeleton.find_bone(animation.track_get_path(t).get_concatenated_subnames())
			if bone < 0:
				continue
			match animation.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					_skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(t, 0.0))
				Animation.TYPE_ROTATION_3D:
					_skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(t, 0.0))
		var to_member := _model.transform * _armature()
		var forward := (to_member.basis.inverse() * Vector3.FORWARD).normalized()
		var down := (to_member.basis.inverse() * Vector3.DOWN).normalized()
		var standing := _globals()
		for side in ["Left", "Right"]:
			var global := _globals()
			var thigh := _skeleton.find_bone(side + "UpLeg")
			var shin := _skeleton.find_bone(side + "Leg")
			var foot := _skeleton.find_bone(side + "Foot")
			var parent := _skeleton.get_bone_parent(thigh)
			# Thigh level and forward, shin straight down.
			var turn_thigh := Basis(Quaternion((global[shin].origin - global[thigh].origin).normalized(), forward))
			var thigh_new: Basis = turn_thigh * global[thigh].basis
			var shin_dir: Vector3 = turn_thigh * (global[foot].origin - global[shin].origin).normalized()
			var shin_new: Basis = Basis(Quaternion(shin_dir, down)) * turn_thigh * global[shin].basis
			_skeleton.set_bone_pose_rotation(thigh, (global[parent].basis.inverse() * thigh_new).get_rotation_quaternion())
			_skeleton.set_bone_pose_rotation(shin, (thigh_new.inverse() * shin_new).get_rotation_quaternion())
		# Down until the feet are where they stood.
		var seated := _globals()
		var foot_bone := _skeleton.find_bone("LeftFoot")
		var rise := (seated[foot_bone].origin - standing[foot_bone].origin).dot(-down)
		var hips := _skeleton.find_bone("Hips")
		_skeleton.set_bone_pose_position(hips, _skeleton.get_bone_pose_position(hips) + down * rise)

	# Where a bone is now (world).
	func bone_point(bone_name: String) -> Vector3:
		var global := _globals()
		return global_transform * _model.transform * _armature() * global[_skeleton.find_bone(bone_name)].origin

	func _armature() -> Transform3D:
		var path := Transform3D()
		var node: Node = _skeleton
		while node != _model:
			path = (node as Node3D).transform * path
			node = node.get_parent()
		return path

	# Every bone's pose in the skeleton's space, from the local poses.
	func _globals() -> Array[Transform3D]:
		var out: Array[Transform3D] = []
		out.resize(_skeleton.get_bone_count())
		for b in range(_skeleton.get_bone_count()):
			var parent := _skeleton.get_bone_parent(b)
			out[b] = _skeleton.get_bone_pose(b) if parent < 0 else out[parent] * _skeleton.get_bone_pose(b)
		return out
