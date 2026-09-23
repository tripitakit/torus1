extends SceneTree

const WorldRebase = preload("res://scripts/world_rebase.gd")

func _init():
	var failures := 0
	failures += _test_should_rebase_false_under_threshold()
	failures += _test_should_rebase_true_over_threshold()
	failures += _test_should_rebase_boundary_is_false()
	failures += _test_should_rebase_zero_threshold()
	failures += _test_compute_rebase_offset_returns_position()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_should_rebase_false_under_threshold() -> int:
	var result := WorldRebase.should_rebase(Vector3(100.0, 0.0, 0.0), 5000.0)
	if result:
		print("FAIL _test_should_rebase_false_under_threshold: expected false, got true")
		return 1
	return 0

func _test_should_rebase_true_over_threshold() -> int:
	var result := WorldRebase.should_rebase(Vector3(6000.0, 0.0, 0.0), 5000.0)
	if not result:
		print("FAIL _test_should_rebase_true_over_threshold: expected true, got false")
		return 1
	return 0

func _test_should_rebase_boundary_is_false() -> int:
	var result := WorldRebase.should_rebase(Vector3(5000.0, 0.0, 0.0), 5000.0)
	if result:
		print("FAIL _test_should_rebase_boundary_is_false: expected false at exact threshold, got true")
		return 1
	return 0

func _test_should_rebase_zero_threshold() -> int:
	var result := WorldRebase.should_rebase(Vector3(0.001, 0.0, 0.0), 0.0)
	if not result:
		print("FAIL _test_should_rebase_zero_threshold: expected true for any nonzero position with threshold 0")
		return 1
	return 0

func _test_compute_rebase_offset_returns_position() -> int:
	var position := Vector3(123.0, -45.0, 6789.0)
	var offset := WorldRebase.compute_rebase_offset(position)
	if not offset.is_equal_approx(position):
		print("FAIL _test_compute_rebase_offset_returns_position: offset=%s expected=%s" % [offset, position])
		return 1
	return 0
