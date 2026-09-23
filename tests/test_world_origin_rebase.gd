extends SceneTree

const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

func _init():
	var failures := 0
	failures += _test_no_rebase_under_threshold()
	failures += _test_rebase_shifts_sibling_over_threshold()
	failures += _test_rebase_shifts_every_node3d_sibling_not_just_one()
	failures += _test_rebase_ignores_non_node3d_siblings()
	failures += _test_missing_tracked_node_does_not_crash()
	failures += _test_repeated_rebase_bounds_tracked_and_preserves_relative_positions()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_rebase_node(tracked_position: Vector3, threshold: float) -> Dictionary:
	var rebase: Node = WorldOriginRebaseScript.new()
	var tracked := Node3D.new()
	tracked.name = "Tracked"
	tracked.position = tracked_position
	var sibling := Node3D.new()
	sibling.name = "Sibling"
	sibling.position = Vector3(10.0, 20.0, 30.0)
	rebase.add_child(tracked)
	rebase.add_child(sibling)
	rebase.tracked_node = NodePath("Tracked")
	rebase.rebase_threshold = threshold
	return {"rebase": rebase, "tracked": tracked, "sibling": sibling}

func _test_no_rebase_under_threshold() -> int:
	var nodes := _make_rebase_node(Vector3(100.0, 0.0, 0.0), 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var sibling: Node3D = nodes["sibling"]
	rebase._check_and_rebase()
	var result := 0
	if not tracked.position.is_equal_approx(Vector3(100.0, 0.0, 0.0)):
		print("FAIL _test_no_rebase_under_threshold: tracked moved to %s" % tracked.position)
		result = 1
	if not sibling.position.is_equal_approx(Vector3(10.0, 20.0, 30.0)):
		print("FAIL _test_no_rebase_under_threshold: sibling moved to %s" % sibling.position)
		result = 1
	rebase.free()
	return result

func _test_rebase_shifts_sibling_over_threshold() -> int:
	var tracked_start := Vector3(6000.0, 0.0, 0.0)
	var sibling_start := Vector3(10.0, 20.0, 30.0)
	var nodes := _make_rebase_node(tracked_start, 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var sibling: Node3D = nodes["sibling"]
	rebase._check_and_rebase()
	var result := 0
	if not tracked.position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_rebase_shifts_sibling_over_threshold: tracked=%s expected ZERO" % tracked.position)
		result = 1
	var expected_sibling := sibling_start - tracked_start
	if not sibling.position.is_equal_approx(expected_sibling):
		print("FAIL _test_rebase_shifts_sibling_over_threshold: sibling=%s expected=%s" % [sibling.position, expected_sibling])
		result = 1
	rebase.free()
	return result

func _test_rebase_shifts_every_node3d_sibling_not_just_one() -> int:
	# Regression test: an earlier version only shifted one hardcoded
	# "rebasing_node" sibling. Any second positioned sibling (a debris
	# field, a second ship, a beacon) must shift too, with no
	# configuration required, or it silently desyncs from the world.
	var tracked_start := Vector3(6000.0, 0.0, 0.0)
	var nodes := _make_rebase_node(tracked_start, 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var second_sibling := Node3D.new()
	second_sibling.name = "SecondSibling"
	second_sibling.position = Vector3(-500.0, 4.0, 9.0)
	rebase.add_child(second_sibling)
	var expected_second := second_sibling.position - tracked_start
	rebase._check_and_rebase()
	var result := 0
	if not second_sibling.position.is_equal_approx(expected_second):
		print("FAIL _test_rebase_shifts_every_node3d_sibling_not_just_one: second_sibling=%s expected=%s" % [second_sibling.position, expected_second])
		result = 1
	rebase.free()
	return result

func _test_rebase_ignores_non_node3d_siblings() -> int:
	var tracked_start := Vector3(6000.0, 0.0, 0.0)
	var nodes := _make_rebase_node(tracked_start, 5000.0)
	var rebase: Node = nodes["rebase"]
	var plain_node := Node.new()
	plain_node.name = "PlainNode"
	rebase.add_child(plain_node)
	var result := 0
	rebase._check_and_rebase()
	if plain_node.get_parent() != rebase:
		print("FAIL _test_rebase_ignores_non_node3d_siblings: plain Node sibling was reparented or removed")
		result = 1
	rebase.free()
	return result

func _test_missing_tracked_node_does_not_crash() -> int:
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.tracked_node = NodePath("DoesNotExist")
	rebase.rebase_threshold = 5000.0
	rebase._check_and_rebase()
	rebase.free()
	return 0

func _test_repeated_rebase_bounds_tracked_and_preserves_relative_positions() -> int:
	# Simulates a ship flying in a straight line while a large, distant
	# body (the planet/station system) sits far away. Across many rebases,
	# the tracked node's local distance from origin must stay bounded, and
	# its position relative to the sibling must never change (the rigid
	# shift invariant the whole feature exists for).
	var rebase: Node = WorldOriginRebaseScript.new()
	var tracked := Node3D.new()
	tracked.name = "Tracked"
	var sibling := Node3D.new()
	sibling.name = "Sibling"
	sibling.position = Vector3(500000.0, -20000.0, 300.0)
	rebase.add_child(tracked)
	rebase.add_child(sibling)
	rebase.tracked_node = NodePath("Tracked")
	rebase.rebase_threshold = 5000.0

	var step := Vector3(400.0, 0.0, 0.0)
	var result := 0
	for i in range(30):
		tracked.position += step
		var relative_before := sibling.position - tracked.position
		rebase._check_and_rebase()
		var relative_after := sibling.position - tracked.position
		if not relative_after.is_equal_approx(relative_before):
			print("FAIL _test_repeated_rebase_bounds_tracked_and_preserves_relative_positions: rebase changed relative position at tick %d: before=%s after=%s" % [i, relative_before, relative_after])
			result = 1
			break
		if tracked.position.length() > rebase.rebase_threshold + step.length():
			print("FAIL _test_repeated_rebase_bounds_tracked_and_preserves_relative_positions: tracked drifted too far at tick %d: %s" % [i, tracked.position])
			result = 1
			break
	rebase.free()
	return result
