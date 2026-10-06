extends SceneTree

const OutpostInteriorScript = preload("res://scripts/outpost_interior.gd")
const TelescopeLayout = preload("res://scripts/telescope_layout.gd")
const DepotLayout = preload("res://scripts/depot_layout.gd")
const InteriorWalkerScript = preload("res://scripts/interior_walker.gd")

func _initialize():
	var failures := 0
	for layout in [TelescopeLayout, DepotLayout]:
		var outpost: Node3D = OutpostInteriorScript.new()
		outpost.layout = layout
		outpost.build()
		root.add_child(outpost)
		var walker: CharacterBody3D = InteriorWalkerScript.new()
		walker.flat = true
		walker.add_to_group(OutpostInteriorScript.PEOPLE_GROUP)
		outpost.add_child(walker)
		await physics_frame
		failures += await _test_spawn_by_the_hatch(outpost, walker)
		failures += await _test_hatch_stays_shut(outpost, walker)
		failures += await _test_walks_into_the_room(outpost, walker, layout)
		outpost.free()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func _stand(walker: CharacterBody3D, at: Vector3, facing: Vector3) -> void:
	walker.place(at + Vector3(0.0, 0.1, 0.0), facing)
	walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}
	await _ticks(20)

func _walk(walker: CharacterBody3D, seconds: float) -> void:
	walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	await _ticks(roundi(seconds * 60.0))
	walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}

func _test_spawn_by_the_hatch(outpost: Node3D, walker: CharacterBody3D) -> int:
	var spawn: Transform3D = outpost.spawn_transform()
	await _stand(walker, spawn.origin, -spawn.basis.z)
	if not outpost.near_hatch(walker.position) or outpost.room_name(walker.position) != "AIRLOCK" or absf(walker.position.y) > 0.05:
		print("FAIL _test_spawn_by_the_hatch: at %s, '%s'" % [walker.position, outpost.room_name(walker.position)])
		return 1
	return 0

# The hatch to the surface never opens in here (K takes one out).
func _test_hatch_stays_shut(outpost: Node3D, walker: CharacterBody3D) -> int:
	await _stand(walker, Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 1.0))
	await _walk(walker, 2.5)
	if walker.position.z > 4.8 - 0.25:
		print("FAIL _test_hatch_stays_shut: walker at %s" % walker.position)
		return 1
	return 0

# Through the inner door (it opens) into the room.
func _test_walks_into_the_room(outpost: Node3D, walker: CharacterBody3D, layout) -> int:
	await _stand(walker, Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, -1.0))
	await _walk(walker, 3.0)
	var room: String = layout.room_at(walker.position)
	if room == "airlock" or room == "" or walker.position.z > -1.5:
		print("FAIL _test_walks_into_the_room: at %s in '%s'" % [walker.position, room])
		return 1
	return 0
