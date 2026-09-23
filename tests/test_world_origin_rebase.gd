extends SceneTree

const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

func _init():
	var failures := 0
	failures += _test_no_rebase_under_threshold()
	failures += _test_rebase_shifts_both_nodes_over_threshold()
	failures += _test_missing_nodes_does_not_crash()

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
	var rebasing := Node3D.new()
	rebasing.name = "Rebasing"
	rebasing.position = Vector3(10.0, 20.0, 30.0)
	rebase.add_child(tracked)
	rebase.add_child(rebasing)
	rebase.tracked_node = NodePath("Tracked")
	rebase.rebasing_node = NodePath("Rebasing")
	rebase.rebase_threshold = threshold
	return {"rebase": rebase, "tracked": tracked, "rebasing": rebasing}

func _test_no_rebase_under_threshold() -> int:
	var nodes := _make_rebase_node(Vector3(100.0, 0.0, 0.0), 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var rebasing: Node3D = nodes["rebasing"]
	rebase._check_and_rebase()
	var result := 0
	if not tracked.position.is_equal_approx(Vector3(100.0, 0.0, 0.0)):
		print("FAIL _test_no_rebase_under_threshold: tracked moved to %s" % tracked.position)
		result = 1
	if not rebasing.position.is_equal_approx(Vector3(10.0, 20.0, 30.0)):
		print("FAIL _test_no_rebase_under_threshold: rebasing moved to %s" % rebasing.position)
		result = 1
	rebase.free()
	return result

func _test_rebase_shifts_both_nodes_over_threshold() -> int:
	var tracked_start := Vector3(6000.0, 0.0, 0.0)
	var rebasing_start := Vector3(10.0, 20.0, 30.0)
	var nodes := _make_rebase_node(tracked_start, 5000.0)
	var rebase: Node = nodes["rebase"]
	var tracked: Node3D = nodes["tracked"]
	var rebasing: Node3D = nodes["rebasing"]
	rebase._check_and_rebase()
	var result := 0
	if not tracked.position.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_rebase_shifts_both_nodes_over_threshold: tracked=%s expected ZERO" % tracked.position)
		result = 1
	var expected_rebasing := rebasing_start - tracked_start
	if not rebasing.position.is_equal_approx(expected_rebasing):
		print("FAIL _test_rebase_shifts_both_nodes_over_threshold: rebasing=%s expected=%s" % [rebasing.position, expected_rebasing])
		result = 1
	rebase.free()
	return result

func _test_missing_nodes_does_not_crash() -> int:
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.tracked_node = NodePath("DoesNotExist")
	rebase.rebasing_node = NodePath("AlsoMissing")
	rebase.rebase_threshold = 5000.0
	rebase._check_and_rebase()
	rebase.free()
	return 0
