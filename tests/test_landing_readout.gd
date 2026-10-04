extends SceneTree

# The moon panel's lines and colours.

const LandingReadout = preload("res://scripts/landing_readout.gd")

func _init():
	var failures := 0
	failures += _test_lines()
	failures += _test_colours_at_the_limits()
	failures += _test_status()
	failures += _test_rover_hint()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_lines() -> int:
	var r := LandingReadout.readout(123.4, -3.26, 1.12, 12.3, 3, false)
	var none := LandingReadout.readout(5000.0, 0.0, 0.0, 0.0, 0, false)
	# Resting, the hull's bottom can read a hair under the pad.
	if LandingReadout.readout(-0.2, 0.0, 0.0, 0.0, 1, true).alt != "ALT 0 m":
		print("FAIL _test_lines: a hair under the pad reads below zero")
		return 1
	if r.pad != "PAD 3" or r.alt != "ALT 123 m" or r.vs != "V/S -3.3 m/s" or r.drift != "DRIFT 1.1 m/s" or r.level != "LEVEL 12°" or none.pad != "":
		print("FAIL _test_lines: %s / %s" % [r, none.pad])
		return 1
	return 0

func _test_colours_at_the_limits() -> int:
	# Green within the landing limits (descent 5 m/s, drift 2 m/s, 25
	# degrees), red past them.
	var inside := LandingReadout.readout(50.0, -4.99, 1.99, 24.9, 1, false)
	var outside := LandingReadout.readout(50.0, -5.01, 2.01, 25.1, 1, false)
	var climbing := LandingReadout.readout(50.0, 30.0, 0.0, 0.0, 1, false)
	for key in ["vs", "drift", "level"]:
		if inside.colors[key] != LandingReadout.GOOD or outside.colors[key] != LandingReadout.BAD:
			print("FAIL _test_colours_at_the_limits: %s %s inside, %s outside" % [key, inside.colors[key], outside.colors[key]])
			return 1
	if climbing.colors.vs != LandingReadout.GOOD:
		print("FAIL _test_colours_at_the_limits: climbing fast shown as too fast")
		return 1
	return 0

func _test_status() -> int:
	var landed := LandingReadout.readout(0.0, 0.0, 0.0, 0.0, 2, true)
	var fast_low := LandingReadout.readout(150.0, -8.0, 0.0, 0.0, 2, false)
	var fast_high := LandingReadout.readout(250.0, -8.0, 0.0, 0.0, 2, false)
	var drifting_low := LandingReadout.readout(150.0, -1.0, 3.0, 0.0, 2, false)
	if landed.status != "LANDED" or fast_low.status != "TOO FAST" or fast_high.status != "" or drifting_low.status != "TOO FAST":
		print("FAIL _test_status: %s / %s / %s / %s" % [landed.status, fast_low.status, fast_high.status, drifting_low.status])
		return 1
	return 0

func _test_rover_hint() -> int:
	var landed := LandingReadout.readout(0.0, 0.0, 0.0, 0.0, 1, true)
	var flying := LandingReadout.readout(50.0, -1.0, 0.0, 0.0, 1, false)
	if landed.get("hint", null) != "V ROVER" or flying.get("hint", null) != "":
		print("FAIL _test_rover_hint: landed '%s', flying '%s'" % [landed.get("hint", null), flying.get("hint", null)])
		return 1
	return 0
