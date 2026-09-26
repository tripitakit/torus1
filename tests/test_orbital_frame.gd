extends SceneTree

const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

const GM := 4.9048e12
const RING := 6949600.0
const PLANET_RADIUS := 1737400.0

func _init():
	var failures := 0
	failures += _test_ring_turns_once_in_about_14_hours()
	failures += _test_forces_cancel_on_the_ring()
	failures += _test_on_the_axis_only_gravity_pulls()
	failures += _test_coriolis_is_across_the_motion()
	failures += _test_gravity_inside_the_planet_falls_to_zero_at_the_centre()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _omega() -> Vector3:
	return Vector3.UP * OrbitalFrame.orbit_angular_velocity(GM, RING)

func _test_ring_turns_once_in_about_14_hours() -> int:
	var w: float = OrbitalFrame.orbit_angular_velocity(GM, RING)
	if absf(w - 1.2088459e-4) > 1e-9 or absf(w * RING - 840.0995) > 0.01:
		print("FAIL _test_ring_turns_once_in_about_14_hours: omega %.10f, ring speed %.4f" % [w, w * RING])
		return 1
	return 0

func _test_forces_cancel_on_the_ring() -> int:
	var result := 0
	for offset in [Vector3(RING, 0.0, 0.0), Vector3(0.0, 0.0, -RING), Vector3(RING * 0.6, 0.0, RING * 0.8)]:
		var a: Vector3 = OrbitalFrame.frame_acceleration(offset, Vector3.ZERO, GM, _omega())
		if a.length() > 1e-9:
			print("FAIL _test_forces_cancel_on_the_ring: at %s the net pull is %s" % [offset, a])
			result = 1
	return result

func _test_on_the_axis_only_gravity_pulls() -> int:
	# On the turning axis there is no centrifugal push: gravity alone.
	var offset := Vector3(0.0, 3.0e6, 0.0)
	var a: Vector3 = OrbitalFrame.frame_acceleration(offset, Vector3.ZERO, GM, _omega())
	var expected := Vector3(0.0, -GM / (3.0e6 * 3.0e6), 0.0)
	if not a.is_equal_approx(expected):
		print("FAIL _test_on_the_axis_only_gravity_pulls: %s expected %s" % [a, expected])
		return 1
	return 0

func _test_coriolis_is_across_the_motion() -> int:
	# On the ring gravity and centrifugal cancel: what is left is Coriolis.
	var v := Vector3(0.0, 0.0, -1000.0)
	var a: Vector3 = OrbitalFrame.frame_acceleration(Vector3(RING, 0.0, 0.0), v, GM, _omega())
	var w: float = _omega().length()
	if absf(a.dot(v)) > 1e-9 or absf(a.length() - 2.0 * w * 1000.0) > 1e-9:
		print("FAIL _test_coriolis_is_across_the_motion: %s (length %.6f, expected %.6f, across the motion)" % [a, a.length(), 2.0 * w * 1000.0])
		return 1
	return 0

func _test_gravity_inside_the_planet_falls_to_zero_at_the_centre() -> int:
	# The planet has no collision: a ship can fly through it. Inside, the
	# pull is a uniform sphere's (linear in r), never the 1/r^2 blow-up.
	var result := 0
	var half := Vector3(0.0, PLANET_RADIUS * 0.5, 0.0)
	var a: Vector3 = OrbitalFrame.frame_acceleration(half, Vector3.ZERO, GM, _omega(), PLANET_RADIUS)
	var expected := -half * (GM / pow(PLANET_RADIUS, 3.0))
	if not a.is_equal_approx(expected):
		print("FAIL _test_gravity_inside_the_planet_falls_to_zero_at_the_centre: halfway in %s, expected %s" % [a, expected])
		result = 1
	var centre: Vector3 = OrbitalFrame.frame_acceleration(Vector3.ZERO, Vector3.ZERO, GM, _omega(), PLANET_RADIUS)
	if not centre.is_zero_approx():
		print("FAIL _test_gravity_inside_the_planet_falls_to_zero_at_the_centre: %s at the centre" % centre)
		result = 1
	var outside := Vector3(0.0, 3.0e6, 0.0)
	var out: Vector3 = OrbitalFrame.frame_acceleration(outside, Vector3.ZERO, GM, _omega(), PLANET_RADIUS)
	if not out.is_equal_approx(Vector3(0.0, -GM / (3.0e6 * 3.0e6), 0.0)):
		print("FAIL _test_gravity_inside_the_planet_falls_to_zero_at_the_centre: outside the planet %s is not GM/r^2" % out)
		result = 1
	return result
