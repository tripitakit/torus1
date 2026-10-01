extends SceneTree

# The portals' rules: pure math.

const PortalRules = preload("res://scripts/portal_rules.gd")

const RING_RADIUS := 6949600.0

func _init():
	var failures := 0
	failures += _test_crossing_from_the_active_side()
	failures += _test_no_crossing_from_behind_or_outside()
	failures += _test_entry_speed_limit()
	failures += _test_exit_keeps_offset_heading_and_speed()
	failures += _test_round_trip_comes_back()
	failures += _test_earth_portal_place()
	failures += _test_moon_portal_place()
	failures += _test_readout()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# A portal at (100, 0, 0) facing +X (its active side).
func _portal() -> Transform3D:
	var z := Vector3(1, 0, 0)
	var y := Vector3(0, 1, 0)
	return Transform3D(Basis(y.cross(z), y, z), Vector3(100, 0, 0))

func _test_crossing_from_the_active_side() -> int:
	var t := PortalRules.crossing(Vector3(110, 20, 0), Vector3(90, 20, 0), _portal())
	if absf(t - 0.5) > 1e-9:
		print("FAIL _test_crossing_from_the_active_side: %f" % t)
		return 1
	return 0

func _test_no_crossing_from_behind_or_outside() -> int:
	var portal := _portal()
	var behind := PortalRules.crossing(Vector3(90, 0, 0), Vector3(110, 0, 0), portal)
	var outside := PortalRules.crossing(Vector3(110, 160, 0), Vector3(90, 160, 0), portal)
	var short := PortalRules.crossing(Vector3(130, 0, 0), Vector3(110, 0, 0), portal)
	if behind >= 0.0 or outside >= 0.0 or short >= 0.0:
		print("FAIL _test_no_crossing_from_behind_or_outside: %f %f %f" % [behind, outside, short])
		return 1
	if not PortalRules.in_front(Vector3(120, 0, 0), portal) or PortalRules.in_front(Vector3(80, 0, 0), portal):
		print("FAIL _test_no_crossing_from_behind_or_outside: in_front wrong")
		return 1
	return 0

func _test_entry_speed_limit() -> int:
	if not PortalRules.speed_ok(299.0) or PortalRules.speed_ok(300.0) or PortalRules.MAX_ENTRY_SPEED != 300.0 or PortalRules.TRANSIT_TIME != 3.0:
		print("FAIL _test_entry_speed_limit")
		return 1
	return 0

func _test_exit_keeps_offset_heading_and_speed() -> int:
	var entry := _portal()
	# The exit: at (0, 5000, 0) facing down (-Y).
	var z := Vector3(0, -1, 0)
	var y := Vector3(0, 0, 1)
	var exit := Transform3D(Basis(y.cross(z), y, z), Vector3(0, 5000, 0))
	# On the entry plane, 40 m to the entry's +Y, nose along -X (into it).
	var ship := Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP), Vector3(100, 40, 0))
	var out := PortalRules.exit_transform(ship, entry, exit)
	var velocity := PortalRules.exit_velocity(Vector3(-120, 0, 0), entry, exit)
	var result := 0
	# The entry's +Y maps to the exit's +Y (no flip of up), so 40 m along +Z.
	if not out.origin.is_equal_approx(Vector3(0, 5000, 40)):
		print("FAIL _test_exit_keeps_offset_heading_and_speed: at %s" % out.origin)
		result = 1
	# Out of the exit's active side: along its +Z (down), nose down too.
	if not velocity.is_equal_approx(Vector3(0, -120, 0)) or not (-out.basis.z).is_equal_approx(Vector3(0, -1, 0)):
		print("FAIL _test_exit_keeps_offset_heading_and_speed: velocity %s nose %s" % [velocity, -out.basis.z])
		result = 1
	return result

func _test_round_trip_comes_back() -> int:
	var a := _portal()
	var b := Transform3D(Basis(Vector3(0, 1, 0), 0.7), Vector3(-3000, 200, 9000))
	var ship := Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.4), Vector3(100, 30, -50))
	var back := PortalRules.exit_transform(PortalRules.exit_transform(ship, a, b), b, a)
	if not back.is_equal_approx(ship):
		print("FAIL _test_round_trip_comes_back: %s vs %s" % [back, ship])
		return 1
	return 0

func _test_earth_portal_place() -> int:
	# In the planet system's axes: 100 km past the ring, toward -X from the
	# start (+Z), active side facing the planet, up along the axis.
	var place := PortalRules.earth_transform(RING_RADIUS)
	var start := Vector3(0, 4000, 6959600)
	var radius := place.origin.length()
	var facing: float = place.basis.z.dot(-place.origin.normalized())
	var from_start := place.origin.distance_to(start)
	if absf(radius - (RING_RADIUS + 100000.0)) > 1.0 or place.origin.x >= 0.0 or facing < 0.9999 or place.basis.y.dot(Vector3.UP) < 0.9999 or from_start < 100000.0 or from_start > 140000.0:
		print("FAIL _test_earth_portal_place: radius %.0f at %s facing %.4f, %.0f m from the start" % [radius, place.origin, facing, from_start])
		return 1
	return 0

func _test_moon_portal_place() -> int:
	var up := Vector3(-0.5, 0.8, 0.2).normalized()
	var east := Vector3(0, 0.2, -0.8).normalized()
	east = (east - up * east.dot(up)).normalized()
	var base := Transform3D(Basis(east, up, east.cross(up)), up * 250000.0)
	var place := PortalRules.moon_local_transform(base)
	if not place.origin.is_equal_approx(up * 270000.0) or not place.basis.z.is_equal_approx(-up) or absf(place.basis.determinant() - 1.0) > 1e-9:
		print("FAIL _test_moon_portal_place: %s" % place)
		return 1
	return 0

func _test_readout() -> int:
	var ok := PortalRules.readout("LUNA", 3200.0, 120.0, true)
	var fast := PortalRules.readout("TERRA", 800.0, 350.0, true)
	var behind := PortalRules.readout("LUNA", 800.0, 50.0, false)
	var result := 0
	if ok.gate != "GATE > LUNA  3.2 km" or ok.approach != "APPROACH 120 m/s  OK" or ok.colors.approach != PortalRules.GOOD or ok.side != "":
		print("FAIL _test_readout: %s" % ok)
		result = 1
	if fast.approach != "APPROACH 350 m/s  TOO FAST!" or fast.colors.approach != PortalRules.BAD or fast.gate != "GATE > TERRA  800 m":
		print("FAIL _test_readout: %s" % fast)
		result = 1
	if behind.side != "WRONG SIDE":
		print("FAIL _test_readout: %s" % behind)
		result = 1
	return result
