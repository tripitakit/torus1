extends SceneTree

# The interior's time of day: 24 game minutes a day, time zones round the
# ring (24 h over all sections), daylight down to 15% at night.

const Clock = preload("res://scripts/interior_clock.gd")

var _failures := 0

func _initialize():
	_failures += _test_base_hour()
	_failures += _test_ring_position_at_section_centres()
	_failures += _test_hour_round_the_ring()
	_failures += _test_daylight_curve()
	_failures += _test_night_share()
	_failures += _test_sun_colour_warmer_at_dusk()
	_failures += _test_hour_line_matches_hour_at()
	_failures += _test_format()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _near(a: float, b: float, tolerance := 0.0001) -> bool:
	return absf(a - b) <= tolerance

func _test_base_hour() -> int:
	var cases := [[0.0, 10.0], [60.0, 11.0], [90.0, 11.5], [14.0 * 60.0, 0.0], [24.0 * 60.0, 10.0]]
	for c in cases:
		if not _near(Clock.base_hour(c[0]), c[1]):
			print("FAIL _test_base_hour: %.0f s gives %.3f, expected %.3f" % [c[0], Clock.base_hour(c[0]), c[1]])
			return 1
	return 0

func _test_ring_position_at_section_centres() -> int:
	# Section slot s is centred at -(s + 0.5) * period, ring index docked + s + 1.
	var period := 21834.0
	for docked in [0, 7, 1999]:
		for slot in [-1, 0, 3]:
			var z: float = -(slot + 0.5) * period
			var expected: float = docked + slot + 1
			if not _near(Clock.ring_position(z, docked, period), expected):
				print("FAIL _test_ring_position_at_section_centres: docked %d slot %d gives %.4f" % [docked, slot, Clock.ring_position(z, docked, period)])
				return 1
	return 0

func _test_hour_round_the_ring() -> int:
	if not _near(Clock.hour_at(10.0, 0.0, 2000), 10.0) or not _near(Clock.hour_at(10.0, 1000.0, 2000), 22.0):
		print("FAIL _test_hour_round_the_ring: opposite side not 12 h on")
		return 1
	if not _near(Clock.hour_at(10.0, 2000.0, 2000), 10.0) or not _near(Clock.hour_at(10.0, -500.0, 2000), 4.0):
		print("FAIL _test_hour_round_the_ring: not wrapped round the ring")
		return 1
	# One section later: 24/2000 h (43.2 s of the day).
	if not _near(Clock.hour_at(10.0, 1.0, 2000) - 10.0, 0.012):
		print("FAIL _test_hour_round_the_ring: one section is not 0.012 h")
		return 1
	return 0

func _test_daylight_curve() -> int:
	if not _near(Clock.daylight(12.0), 1.0) or not _near(Clock.daylight(7.0), 1.0) or not _near(Clock.daylight(17.0), 1.0):
		print("FAIL _test_daylight_curve: day not full")
		return 1
	for h in [0.0, 2.0, 4.0, 20.0, 23.9]:
		if not _near(Clock.daylight(h), Clock.NIGHT_LIGHT):
			print("FAIL _test_daylight_curve: %.1f h gives %.3f" % [h, Clock.daylight(h)])
			return 1
	var last := Clock.daylight(4.0)
	for k in range(1, 31):
		var d := Clock.daylight(4.0 + k * 0.1)
		if d < last:
			print("FAIL _test_daylight_curve: dawn not rising at %.1f" % (4.0 + k * 0.1))
			return 1
		last = d
	last = Clock.daylight(17.0)
	for k in range(1, 31):
		var d := Clock.daylight(17.0 + k * 0.1)
		if d > last:
			print("FAIL _test_daylight_curve: dusk not falling at %.1f" % (17.0 + k * 0.1))
			return 1
		last = d
	return 0

func _test_night_share() -> int:
	if not _near(Clock.night(12.0), 0.0) or not _near(Clock.night(0.0), 1.0) or not (Clock.night(18.5) > 0.2 and Clock.night(18.5) < 0.8):
		print("FAIL _test_night_share: %.2f %.2f %.2f" % [Clock.night(12.0), Clock.night(0.0), Clock.night(18.5)])
		return 1
	return 0

func _test_sun_colour_warmer_at_dusk() -> int:
	var noon := Clock.sun_color(12.0)
	var dusk := Clock.sun_color(18.5)
	if not (dusk.r / dusk.b > noon.r / noon.b * 1.3):
		print("FAIL _test_sun_colour_warmer_at_dusk: noon %s dusk %s" % [noon, dusk])
		return 1
	return 0

func _test_hour_line_matches_hour_at() -> int:
	# The shaders' hour = origin + slope * z, for z in the interior world
	# (chain moved by `offset`): the same as hour_at of ring_position.
	var period := 21834.0
	var offset := -30000.0
	var line := Clock.hour_line(3.0, 12, period, offset, 2000)
	for z in [-15000.0, 0.0, 8000.0]:
		var expected := Clock.hour_at(3.0, Clock.ring_position(z - offset, 12, period), 2000)
		var got: float = fposmod(line.x + line.y * z, 24.0)
		if not _near(got, expected):
			print("FAIL _test_hour_line_matches_hour_at: z %.0f gives %.4f, expected %.4f" % [z, got, expected])
			return 1
	return 0

func _test_format() -> int:
	if Clock.format(21.6667) != "ORA 21:40" or Clock.format(0.0) != "ORA 00:00" or Clock.format(9.999) != "ORA 09:59":
		print("FAIL _test_format: %s %s %s" % [Clock.format(21.6667), Clock.format(0.0), Clock.format(9.999)])
		return 1
	return 0
