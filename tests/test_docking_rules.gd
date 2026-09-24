extends SceneTree

const DockingRules = preload("res://scripts/docking_rules.gd")

func _init():
	var failures := 0
	failures += _check("close and slow", DockingRules.can_dock(100.0, 5.0), true)
	failures += _check("exactly at both limits", DockingRules.can_dock(150.0, 20.0), true)
	failures += _check("just too far", DockingRules.can_dock(150.1, 0.0), false)
	failures += _check("just too fast", DockingRules.can_dock(0.0, 20.1), false)
	failures += _check("far and fast", DockingRules.can_dock(5000.0, 300.0), false)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _check(case_name: String, actual: bool, expected: bool) -> int:
	if actual != expected:
		print("FAIL _test_can_dock (%s): got %s expected %s" % [case_name, actual, expected])
		return 1
	return 0
