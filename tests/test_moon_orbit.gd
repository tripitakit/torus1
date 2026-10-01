extends SceneTree

# The moon's orbit and frames: pure math.

const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

const RING_RADIUS := 6949600.0

func _init():
	var failures := 0
	failures += _test_rates()
	failures += _test_centre_and_tidal_lock()
	failures += _test_spin_about_the_planet()
	failures += _test_velocity_between_frames()
	failures += _test_gravity()
	failures += _test_marker_range()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _close(value: float, expected: float, share: float) -> bool:
	return absf(value - expected) <= absf(expected) * share

func _test_rates() -> int:
	var moon := MoonOrbit.moon_rate(OrbitalFrame.MOON_GM)
	var relative := MoonOrbit.relative_rate(OrbitalFrame.MOON_GM, RING_RADIUS)
	var hours: float = TAU / moon / 3600.0
	if not _close(moon, 2.476e-5, 0.005) or not _close(hours, 70.5, 0.01) or not _close(relative, -9.61e-5, 0.005):
		print("FAIL _test_rates: moon %e rad/s (%.1f h), relative %e rad/s" % [moon, hours, relative])
		return 1
	return 0

func _test_centre_and_tidal_lock() -> int:
	for angle in [0.0, 1.0, -2.5, MoonOrbit.START_ANGLE]:
		var centre := MoonOrbit.centre_offset(angle)
		var facing: Vector3 = MoonOrbit.moon_basis(angle) * Vector3(-1.0, 0.0, 0.0)
		if not _close(centre.length(), MoonOrbit.ORBIT_RADIUS, 1e-9) or absf(centre.y) > 1e-6 or not centre.is_equal_approx(MoonOrbit.moon_basis(angle) * Vector3(MoonOrbit.ORBIT_RADIUS, 0.0, 0.0)) or facing.dot(-centre.normalized()) < 0.999999:
			print("FAIL _test_centre_and_tidal_lock: angle %f centre %s facing %s" % [angle, centre, facing])
			return 1
	return 0

func _test_spin_about_the_planet() -> int:
	var pivot := Vector3(10.0, -4000.0, -6959600.0)
	var spin := MoonOrbit.spin(Vector3.UP, 0.3, pivot)
	if not (spin * pivot).is_equal_approx(pivot):
		print("FAIL _test_spin_about_the_planet: the pivot moved")
		return 1
	var start := pivot + MoonOrbit.centre_offset(0.2)
	var turned: Vector3 = MoonOrbit.spin(Vector3.UP, 0.05, pivot) * start
	if turned.distance_to(pivot + MoonOrbit.centre_offset(0.25)) > 1e-3:
		print("FAIL _test_spin_about_the_planet: turned %s, expected %s" % [turned, pivot + MoonOrbit.centre_offset(0.25)])
		return 1
	return 0

func _test_velocity_between_frames() -> int:
	var rate := MoonOrbit.relative_rate(OrbitalFrame.MOON_GM, RING_RADIUS)
	var offset := Vector3(1.2e7, 300.0, -1.5e7)
	var v := Vector3(12.0, -3.0, 40.0)
	var back := MoonOrbit.to_moon_velocity(MoonOrbit.to_ring_velocity(v, offset, Vector3.UP, rate), offset, Vector3.UP, rate)
	var fixed := MoonOrbit.to_ring_velocity(Vector3.ZERO, offset, Vector3.UP, rate)
	if not back.is_equal_approx(v) or not fixed.is_equal_approx(Vector3.UP.cross(offset) * rate):
		print("FAIL _test_velocity_between_frames: round trip %s, fixed point %s" % [back, fixed])
		return 1
	return 0

func _test_gravity() -> int:
	var surface := MoonOrbit.gravity(Vector3(MoonOrbit.RADIUS, 0.0, 0.0))
	var half := MoonOrbit.gravity(Vector3(0.0, MoonOrbit.RADIUS * 0.5, 0.0))
	if not _close(surface.length(), 0.976, 0.01) or surface.x >= 0.0 or not _close(half.length(), surface.length() * 0.5, 1e-6) or half.y >= 0.0:
		print("FAIL _test_gravity: surface %s, half way %s" % [surface, half])
		return 1
	return 0

func _test_marker_range() -> int:
	# From Torus1 (about 13,000 km from the moon's centre) no marker; inside
	# MARKER_RANGE it shows.
	var far := MoonOrbit.marker_in_range(Vector3(1.3e7, 0.0, 0.0))
	var near := MoonOrbit.marker_in_range(Vector3(0.0, 4.0e6, 0.0))
	if far or not near or MoonOrbit.MARKER_RANGE != 5.0e6:
		print("FAIL _test_marker_range: far %s, near %s" % [far, near])
		return 1
	return 0
