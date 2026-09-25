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
	failures += _test_still_on_the_ring_is_a_circular_orbit()
	failures += _test_slower_than_circular_drops_the_periapsis()
	failures += _test_faster_than_escape_is_an_open_orbit()
	failures += _test_radial_fall_is_an_impact_without_nan()
	failures += _test_orbit_points_follow_the_conic()
	failures += _test_gravity_inside_the_planet_falls_to_zero_at_the_centre()
	failures += _test_orbit_at_the_centre_has_no_nan()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _omega() -> Vector3:
	return Vector3.UP * OrbitalFrame.orbit_angular_velocity(GM, RING)

func _circular_speed(radius: float) -> float:
	return sqrt(GM / radius)

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

func _test_still_on_the_ring_is_a_circular_orbit() -> int:
	var offset := Vector3(RING, 0.0, 0.0)
	var inertial: Vector3 = OrbitalFrame.inertial_velocity(offset, Vector3.ZERO, _omega())
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, inertial, GM)
	var result := 0
	if absf(inertial.length() - 840.0995) > 0.01:
		print("FAIL _test_still_on_the_ring_is_a_circular_orbit: true speed %.4f expected 840.0995" % inertial.length())
		result = 1
	if absf(orbit.periapsis - RING) > 1.0 or absf(orbit.apoapsis - RING) > 1.0 or orbit.escape:
		print("FAIL _test_still_on_the_ring_is_a_circular_orbit: periapsis %.1f apoapsis %.1f escape %s" % [orbit.periapsis, orbit.apoapsis, orbit.escape])
		result = 1
	return result

func _test_slower_than_circular_drops_the_periapsis() -> int:
	var offset := Vector3(RING, 0.0, 0.0)
	var inertial := Vector3(0.0, 0.0, -0.9 * _circular_speed(RING))
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, inertial, GM)
	if orbit.periapsis > RING - 1000.0 or absf(orbit.apoapsis - RING) > 1.0 or orbit.escape:
		print("FAIL _test_slower_than_circular_drops_the_periapsis: periapsis %.1f apoapsis %.1f" % [orbit.periapsis, orbit.apoapsis])
		return 1
	return 0

func _test_faster_than_escape_is_an_open_orbit() -> int:
	var offset := Vector3(RING, 0.0, 0.0)
	var inertial := Vector3(0.0, 0.0, -1.5 * _circular_speed(RING))
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, inertial, GM)
	if not orbit.escape or not is_inf(orbit.apoapsis) or absf(orbit.periapsis - RING) > 1.0:
		print("FAIL _test_faster_than_escape_is_an_open_orbit: escape %s apoapsis %f periapsis %.1f" % [orbit.escape, orbit.apoapsis, orbit.periapsis])
		return 1
	return 0

func _test_radial_fall_is_an_impact_without_nan() -> int:
	# At rest relative to the stars: no angular momentum, straight down.
	var offset := Vector3(RING, 0.0, 0.0)
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, Vector3.ZERO, GM)
	var points: PackedVector3Array = OrbitalFrame.orbit_points(orbit, 16, RING * 5.0)
	var result := 0
	if is_nan(orbit.periapsis) or orbit.periapsis > PLANET_RADIUS or is_nan(orbit.apoapsis):
		print("FAIL _test_radial_fall_is_an_impact_without_nan: periapsis %f apoapsis %f" % [orbit.periapsis, orbit.apoapsis])
		result = 1
	for p in points:
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			print("FAIL _test_radial_fall_is_an_impact_without_nan: NaN in the orbit points")
			result = 1
			break
	return result

func _test_orbit_points_follow_the_conic() -> int:
	var result := 0
	var offset := Vector3(RING, 0.0, 0.0)
	# Closed: every point between periapsis and apoapsis, in the orbit plane, loop closed.
	var closed: Dictionary = OrbitalFrame.orbit_of(offset, Vector3(0.0, 0.0, -0.9 * _circular_speed(RING)), GM)
	var points: PackedVector3Array = OrbitalFrame.orbit_points(closed, 256, RING * 5.0)
	if points.size() != 256 or points[0].distance_to(points[255]) > 1.0:
		print("FAIL _test_orbit_points_follow_the_conic: %d points, loop gap %.1f m" % [points.size(), points[0].distance_to(points[points.size() - 1])])
		result = 1
	for p in points:
		var r := p.length()
		if r < closed.periapsis - 1.0 or r > closed.apoapsis + 1.0 or absf(p.dot(closed.normal)) > 1.0:
			print("FAIL _test_orbit_points_follow_the_conic: point %s off the ellipse (r %.1f)" % [p, r])
			result = 1
			break
	# Open: stops where the radius reaches the limit.
	var open: Dictionary = OrbitalFrame.orbit_of(offset, Vector3(0.0, 0.0, -1.5 * _circular_speed(RING)), GM)
	var branch: PackedVector3Array = OrbitalFrame.orbit_points(open, 64, RING * 5.0)
	if absf(branch[0].length() - RING * 5.0) > 1.0 or absf(branch[63].length() - RING * 5.0) > 1.0:
		print("FAIL _test_orbit_points_follow_the_conic: open branch ends at %.1f / %.1f, expected %.1f" % [branch[0].length(), branch[63].length(), RING * 5.0])
		result = 1
	for p in branch:
		if p.length() > RING * 5.0 + 1.0 or p.length() < open.periapsis - 1.0:
			print("FAIL _test_orbit_points_follow_the_conic: open branch point at %.1f m" % p.length())
			result = 1
			break
	return result

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

func _test_orbit_at_the_centre_has_no_nan() -> int:
	var orbit: Dictionary = OrbitalFrame.orbit_of(Vector3.ZERO, Vector3(0.0, 0.0, -100.0), GM)
	var points: PackedVector3Array = OrbitalFrame.orbit_points(orbit, 16, RING)
	var result := 0
	if is_nan(orbit.periapsis) or is_nan(orbit.apoapsis) or orbit.periapsis > PLANET_RADIUS:
		print("FAIL _test_orbit_at_the_centre_has_no_nan: periapsis %f apoapsis %f" % [orbit.periapsis, orbit.apoapsis])
		result = 1
	for p in points:
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			print("FAIL _test_orbit_at_the_centre_has_no_nan: NaN in the orbit points")
			result = 1
			break
	return result
