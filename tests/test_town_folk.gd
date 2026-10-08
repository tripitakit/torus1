extends SceneTree

# The passers-by of Torus1 one can talk to: who each one is (the same every
# time), the one nearest ahead of the pilot among the walkers drawn by the
# shader, and the person standing in for them.

const TownFolk = preload("res://scripts/town_folk.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")

func _initialize():
	var failures := 0
	failures += _test_identity()
	failures += await _test_nearest()
	failures += await _test_stand_in()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_identity() -> int:
	var names := {}
	for id in range(100):
		var who := TownFolk.identity(id)
		if who != TownFolk.identity(id) or who.name.split(" ").size() < 2 or who.age < 18 or who.age > 80 or who.job == "":
			print("FAIL _test_identity: %d %s" % [id, who])
			return 1
		names[who.name] = true
	if names.size() < 30:
		print("FAIL _test_identity: %d names in 100" % names.size())
		return 1
	return 0

# Three walkers standing still (laps 0 is not allowed: a huge loop walked
# slowly, looked at near t = 0), on a flat floor in a node moved along x.
func _walkers() -> MultiMeshInstance3D:
	var loops := []
	for k in range(3):
		var loop := LoopTraffic.make_loop(LoopTraffic.FLAT, -1000.0, -1000.0 + k * 0.3, 100000.0, 100000.0, 4.0, 0.001, 0.0, 0.0, k)
		loop.phase = 1000.0 + [0.0, 0.6, -6.0][k]
		loops.append(loop)
	var node := LoopTraffic.multimesh_instance("WalkersNear_test", LoopTraffic.instance_buffer(loops), BoxMesh.new(), StandardMaterial3D.new(), AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10)))
	node.position = Vector3(10.0, 0.0, 0.0)
	return node

func _test_nearest() -> int:
	var node := _walkers()
	root.add_child(node)
	await process_frame
	var corner := 4.0
	# Walker k at x = 10 + 4 + (0, 0.6, -6) on z = -1000 + 0.3 k (the bottom
	# edge); the pilot 1.5 m before walker 0, walker 1 also in reach ahead.
	var pose0 := node.global_transform * LoopTraffic.pose_from_data(node.multimesh.buffer, 0, 0.0, corner)
	var pilot := Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), pose0.origin - Vector3(1.5, 0.0, 0.0))
	var none := func(_pose: Transform3D, _alpha: float) -> bool: return false
	var found: Dictionary = TownFolk.nearest([node], pilot, 0.0, corner, none)
	if found.is_empty() or found.index != 0 or found.pose.origin.distance_to(pose0.origin) > 0.01:
		print("FAIL _test_nearest: ahead %s" % [found])
		return 1
	# Turned away: nobody.
	var away := Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP), pilot.origin)
	if not TownFolk.nearest([node], away, 0.0, corner, none).is_empty():
		print("FAIL _test_nearest: found someone behind")
		return 1
	# Home for the night: the next one.
	var night := func(_pose: Transform3D, alpha: float) -> bool: return is_equal_approx(alpha, fposmod(0 * 0.618034, 1.0))
	found = TownFolk.nearest([node], pilot, 0.0, corner, night)
	if found.is_empty() or found.index == 0:
		print("FAIL _test_nearest: the one at home was found %s" % [found])
		return 1
	# Hidden (already talking): not found again.
	TownFolk.hide(node, 0, true)
	found = TownFolk.nearest([node], pilot, 0.0, corner, none)
	TownFolk.hide(node, 0, false)
	if found.is_empty() or found.index == 0 or TownFolk.nearest([node], pilot, 0.0, corner, none).index != 0:
		print("FAIL _test_nearest: hidden one found")
		return 1
	node.free()
	return 0

func _test_stand_in() -> int:
	var person: Node3D = TownFolk.stand_in(Color(1.0, 0.5, 0.12))
	root.add_child(person)
	await process_frame
	if not person.has_method("idle") or person.find_children("*", "MeshInstance3D", true, false).is_empty():
		print("FAIL _test_stand_in")
		return 1
	person.free()
	return 0
