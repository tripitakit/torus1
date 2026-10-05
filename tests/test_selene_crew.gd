extends SceneTree

const SeleneCrew = preload("res://scripts/selene_crew.gd")
const SeleneInteriorScript = preload("res://scripts/selene_interior.gd")
const PeopleModel = preload("res://scripts/people_model.gd")

func _initialize():
	var failures := 0
	failures += _test_sleeve_is_the_left_arm()
	failures += _test_department_colours()
	failures += await _test_walker_follows_route()
	failures += await _test_walker_stops_for_the_player()
	failures += await _test_walker_waits_then_goes_on()
	failures += await _test_seated_knees_bent()
	failures += await _test_twenty_in_the_base()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

# UV.x parts: 0 suit, 1 boots, 2 skin, 3 the left sleeve (the department's
# colour).
func _test_sleeve_is_the_left_arm() -> int:
	var mesh: ArrayMesh = SeleneCrew.member_mesh()
	var uv: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var bones: PackedStringArray = PeopleModel.bake().bones
	var sleeve := 0
	var skin := {}
	for i in range(uv.size()):
		var part := roundi(uv[i].x)
		if part == 3:
			sleeve += 1
			if not (bones[i] in ["LeftArm", "LeftForeArm"]):
				print("FAIL _test_sleeve_is_the_left_arm: sleeve on %s" % bones[i])
				return 1
		if part == 2:
			skin[bones[i]] = true
		if bones[i] in ["RightArm", "RightForeArm"] and part != 0:
			print("FAIL _test_sleeve_is_the_left_arm: right arm part %d" % part)
			return 1
	if sleeve < 30 or not skin.has("Head") or not skin.has("LeftHand"):
		print("FAIL _test_sleeve_is_the_left_arm: %d sleeve vertices, skin on %s" % [sleeve, skin.keys()])
		return 1
	return 0

func _test_department_colours() -> int:
	var expected := {"main_mission": Color(0.95, 0.45, 0.1), "medical": Color(0.95, 0.95, 0.95), "security": Color(0.45, 0.2, 0.6),
		"technical": Color(0.95, 0.8, 0.15), "command": Color(0.08, 0.08, 0.09)}
	var result := 0
	for name: String in expected:
		var member: Node3D = SeleneCrew.new_member(name)
		var colour: Color = (member.body().material_override as ShaderMaterial).get_shader_parameter("sleeve")
		if not SeleneCrew.DEPARTMENTS.has(name) or not (SeleneCrew.DEPARTMENTS[name] as Color).is_equal_approx(expected[name]) or not colour.is_equal_approx(expected[name]):
			print("FAIL _test_department_colours: %s" % name)
			result = 1
		member.free()
	return result

func _walker_on(points: Array) -> Node3D:
	var member: Node3D = SeleneCrew.new_member("technical")
	root.add_child(member)
	member.walk_route(PackedVector3Array(points), 7)
	return member

func _test_walker_follows_route() -> int:
	var member := _walker_on([Vector3.ZERO, Vector3(0.0, 0.0, -6.0)])
	await _ticks(120)
	var at := member.global_position
	var facing := -member.global_transform.basis.z
	member.free()
	if absf(at.z + 2.4) > 0.2 or absf(at.x) > 0.01 or facing.dot(Vector3(0.0, 0.0, -1.0)) < 0.99:
		print("FAIL _test_walker_follows_route: at %s facing %s" % [at, facing])
		return 1
	return 0

func _test_walker_stops_for_the_player() -> int:
	var pilot := Node3D.new()
	pilot.add_to_group(SeleneCrew.PILOT_GROUP)
	root.add_child(pilot)
	pilot.position = Vector3(0.0, 0.0, -3.5)
	var member := _walker_on([Vector3.ZERO, Vector3(0.0, 0.0, -6.0)])
	await _ticks(240)
	var at := member.global_position
	member.free()
	pilot.free()
	if at.z < -2.4 or at.z > -2.0:
		print("FAIL _test_walker_stops_for_the_player: at %s" % at)
		return 1
	return 0

# Never stuck for good behind the pilot: after a while it walks on.
func _test_walker_waits_then_goes_on() -> int:
	var pilot := Node3D.new()
	pilot.add_to_group(SeleneCrew.PILOT_GROUP)
	root.add_child(pilot)
	pilot.position = Vector3(0.0, 0.0, -3.5)
	var member := _walker_on([Vector3.ZERO, Vector3(0.0, 0.0, -9.0)])
	await _ticks(60 * 14)
	var at := member.global_position
	member.free()
	pilot.free()
	if at.z > -4.0:
		print("FAIL _test_walker_waits_then_goes_on: still at %s" % at)
		return 1
	return 0

func _test_seated_knees_bent() -> int:
	var member: Node3D = SeleneCrew.new_member("main_mission")
	root.add_child(member)
	member.sit()
	await _ticks(2)
	var hips: Vector3 = member.bone_point("LeftUpLeg")
	var knee: Vector3 = member.bone_point("LeftLeg")
	var foot: Vector3 = member.bone_point("LeftFoot")
	var ahead := -member.global_transform.basis.z
	member.free()
	if hips.y > 0.65 or hips.y < 0.35 or (knee - hips).dot(ahead) < 0.3 or absf(knee.y - hips.y) > 0.15 or foot.y > 0.2:
		print("FAIL _test_seated_knees_bent: hips %s knee %s foot %s" % [hips, knee, foot])
		return 1
	return 0

func _test_twenty_in_the_base() -> int:
	var base: Node3D = SeleneInteriorScript.new()
	base.build()
	root.add_child(base)
	await _ticks(2)
	var crew := base.get_node_or_null("Crew")
	var seated := 0
	if crew != null:
		for member in crew.get_children():
			if member.is_seated():
				seated += 1
	var count := crew.get_child_count() if crew != null else 0
	base.free()
	if count < 18 or count > 24 or seated != 8:
		print("FAIL _test_twenty_in_the_base: %d crew, %d seated" % [count, seated])
		return 1
	return 0
