extends SceneTree

const Attitude = preload("res://scripts/attitude.gd")

# Planet at the origin, ring axis +Y, ship on +X: east +X, up +Y, north -Z,
# so the reference is the identity.
var _reference: Basis = Attitude.ring_reference(Vector3(100.0, 0.0, 0.0), Vector3.ZERO, Vector3.UP)

func _init():
	var failures := 0
	failures += _test_reference_axes()
	failures += _test_reference_on_the_axis_is_still_a_frame()
	failures += _test_level_facing_north()
	failures += _test_yawed_east()
	failures += _test_rolled_upside_down()
	failures += _test_nose_up()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _orthonormal(frame: Basis) -> bool:
	return is_equal_approx(frame.x.length(), 1.0) and is_equal_approx(frame.y.length(), 1.0) and is_equal_approx(frame.z.length(), 1.0) and absf(frame.x.dot(frame.y)) < 1e-6 and absf(frame.y.dot(frame.z)) < 1e-6 and absf(frame.x.dot(frame.z)) < 1e-6 and frame.determinant() > 0.0

func _test_reference_axes() -> int:
	var result := 0
	if not _reference.is_equal_approx(Basis()):
		print("FAIL _test_reference_axes: on +X with axis +Y got %s, expected identity" % _reference)
		result = 1
	# Elsewhere: east points away from the planet within the ring's plane,
	# north is up x east.
	var where := Vector3(30.0, 500.0, -400.0)
	var frame: Basis = Attitude.ring_reference(where, Vector3(30.0, 0.0, 0.0), Vector3.UP)
	var east := Vector3(0.0, 0.0, -1.0)
	if not _orthonormal(frame) or not frame.x.is_equal_approx(east) or not frame.y.is_equal_approx(Vector3.UP) or not (-frame.z).is_equal_approx(Vector3.UP.cross(east)):
		print("FAIL _test_reference_axes: at %s got %s" % [where, frame])
		result = 1
	return result

func _test_reference_on_the_axis_is_still_a_frame() -> int:
	var frame: Basis = Attitude.ring_reference(Vector3(0.0, 800.0, 0.0), Vector3.ZERO, Vector3.UP)
	if not _orthonormal(frame) or not frame.y.is_equal_approx(Vector3.UP):
		print("FAIL _test_reference_on_the_axis_is_still_a_frame: %s" % frame)
		return 1
	return 0

# Screen points of the ball: +z toward its camera (centre), +x right, +y up.
# Reference directions: +x east, +y up, -z north.
func _check(test_name: String, ship: Basis, screen: Vector3, expected: Vector3) -> int:
	var got: Vector3 = Attitude.navball_matrix(ship, _reference) * screen
	if not got.is_equal_approx(expected):
		print("FAIL %s: screen %s shows %s, expected %s" % [test_name, screen, got, expected])
		return 1
	return 0

func _test_level_facing_north() -> int:
	var result := 0
	result += _check("_test_level_facing_north", Basis(), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	result += _check("_test_level_facing_north", Basis(), Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	result += _check("_test_level_facing_north", Basis(), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0))
	return mini(result, 1)

func _test_yawed_east() -> int:
	# Turned right 90 degrees: the nose (-Z) now points east (+X).
	var ship := Basis(Vector3.UP, -PI / 2.0)
	return _check("_test_yawed_east", ship, Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0))

func _test_rolled_upside_down() -> int:
	# Rolled 180 degrees about the nose: the top of the ball shows down.
	var ship := Basis(Vector3.BACK, PI)
	var result := 0
	result += _check("_test_rolled_upside_down", ship, Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0))
	result += _check("_test_rolled_upside_down", ship, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	return mini(result, 1)

func _test_nose_up() -> int:
	var ship := Basis(Vector3.RIGHT, PI / 2.0)
	return _check("_test_nose_up", ship, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0))
