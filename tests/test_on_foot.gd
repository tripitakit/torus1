extends SceneTree

# On foot: walking and jogging speeds, looking round, jumping, how far from
# a vehicle's box.

const OnFoot = preload("res://scripts/on_foot.gd")

func _init():
	var failures := 0
	failures += _test_walk_and_jog()
	failures += _test_diagonal_no_faster()
	failures += _test_look_limits_pitch()
	failures += _test_jump_times()
	failures += _test_distance_to_a_box()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_walk_and_jog() -> int:
	var walk: Vector3 = OnFoot.walk_velocity(Vector2(0.0, 1.0), false, Basis())
	var jog: Vector3 = OnFoot.walk_velocity(Vector2(0.0, 1.0), true, Basis())
	var back: Vector3 = OnFoot.walk_velocity(Vector2(0.0, -1.0), false, Basis())
	var right: Vector3 = OnFoot.walk_velocity(Vector2(1.0, 0.0), false, Basis())
	if walk.distance_to(Vector3(0.0, 0.0, -1.5)) > 1e-6 or jog.distance_to(Vector3(0.0, 0.0, -4.0)) > 1e-6 or back.distance_to(Vector3(0.0, 0.0, 1.5)) > 1e-6 or right.distance_to(Vector3(1.5, 0.0, 0.0)) > 1e-6:
		print("FAIL _test_walk_and_jog: %s %s %s %s" % [walk, jog, back, right])
		return 1
	return 0

func _test_diagonal_no_faster() -> int:
	var v: Vector3 = OnFoot.walk_velocity(Vector2(1.0, 1.0), true, Basis())
	if absf(v.length() - 4.0) > 1e-6:
		print("FAIL _test_diagonal_no_faster: %.3f m/s" % v.length())
		return 1
	return 0

func _test_look_limits_pitch() -> int:
	var look: Vector2 = OnFoot.look(Vector2.ZERO, Vector2(100.0, -10000.0))
	var down: Vector2 = OnFoot.look(Vector2.ZERO, Vector2(0.0, 10000.0))
	if absf(look.x + 0.3) > 1e-6 or absf(look.y - OnFoot.PITCH_LIMIT) > 1e-6 or absf(down.y + OnFoot.PITCH_LIMIT) > 1e-6:
		print("FAIL _test_look_limits_pitch: %s, %s" % [look, down])
		return 1
	return 0

func _test_jump_times() -> int:
	var moon: float = OnFoot.air_time(OnFoot.JUMP_MOON, 1.62)
	var inside: float = OnFoot.air_time(OnFoot.JUMP_INTERIOR, 9.81)
	if absf(moon - 2.469) > 0.01 or absf(inside - 0.632) > 0.01:
		print("FAIL _test_jump_times: %.3f s, %.3f s" % [moon, inside])
		return 1
	return 0

func _test_distance_to_a_box() -> int:
	var box := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10.0, 0.0, 0.0))
	var size := Vector3(4.0, 2.0, 8.0)
	# Turned a quarter, the box's long side runs along x: a point 6 m off its
	# middle along z is 4 m from its face, one inside it 0.
	var beside: float = OnFoot.distance_to_box(Vector3(10.0, 0.0, 6.0), box, size)
	var inside: float = OnFoot.distance_to_box(Vector3(11.0, 0.0, 0.0), box, size)
	if absf(beside - 4.0) > 1e-6 or inside != 0.0:
		print("FAIL _test_distance_to_a_box: %.3f, %.3f" % [beside, inside])
		return 1
	return 0
