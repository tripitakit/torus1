extends SceneTree

# The landing guide: the target pad and the gates stacked above it.

const LandingGuide = preload("res://scripts/landing_guide.gd")

func _init():
	var failures := 0
	failures += _test_target_is_the_nearest_pad()
	failures += _test_gates_stacked_level_above_the_pad()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _pads() -> Array:
	var tilt := Basis(Vector3(1.0, 0.0, 0.0), 0.3)
	return [Transform3D(tilt, Vector3(0.0, 0.0, 0.0)), Transform3D(tilt, Vector3(100.0, 0.0, 0.0)), Transform3D(tilt, Vector3(200.0, 5.0, 0.0))]

func _test_target_is_the_nearest_pad() -> int:
	if LandingGuide.target_pad(Vector3(90.0, 300.0, 10.0), _pads()) != 1 or LandingGuide.target_pad(Vector3(260.0, 0.0, 0.0), _pads()) != 2:
		print("FAIL _test_target_is_the_nearest_pad")
		return 1
	return 0

func _test_gates_stacked_level_above_the_pad() -> int:
	# Relative to the ship: four level squares GATE_SIZE wide at the gate
	# heights over the pad's top, then a line from the ship to the top gate.
	var pad: Transform3D = _pads()[1]
	var ship := Vector3(400.0, 800.0, -50.0)
	var segments := LandingGuide.gate_segments(pad, ship)
	var up := pad.basis.y.normalized()
	if segments.size() != LandingGuide.GATE_HEIGHTS.size() * 8 + 2:
		print("FAIL _test_gates_stacked_level_above_the_pad: %d points" % segments.size())
		return 1
	for g in range(LandingGuide.GATE_HEIGHTS.size()):
		var centre := Vector3.ZERO
		for k in range(8):
			var world: Vector3 = segments[g * 8 + k] + ship
			var height: float = (world - pad.origin).dot(up)
			if absf(height - LandingGuide.GATE_HEIGHTS[g]) > 0.001:
				print("FAIL _test_gates_stacked_level_above_the_pad: gate %d corner %.3f m up" % [g, height])
				return 1
			centre += world / 8.0
			var across: Vector3 = (world - pad.origin) - up * height
			if absf(maxf(absf(across.dot(pad.basis.x.normalized())), absf(across.dot(pad.basis.z.normalized()))) - LandingGuide.GATE_SIZE * 0.5) > 0.001:
				print("FAIL _test_gates_stacked_level_above_the_pad: gate %d corner off its square" % g)
				return 1
		if centre.distance_to(pad.origin + up * LandingGuide.GATE_HEIGHTS[g]) > 0.001:
			print("FAIL _test_gates_stacked_level_above_the_pad: gate %d not centred over the pad" % g)
			return 1
	var line_start: Vector3 = segments[segments.size() - 2]
	var line_end: Vector3 = segments[segments.size() - 1] + ship
	if line_start != Vector3.ZERO or line_end.distance_to(pad.origin + up * LandingGuide.GATE_HEIGHTS[-1]) > 0.001:
		print("FAIL _test_gates_stacked_level_above_the_pad: line from %s to %s" % [line_start, line_end])
		return 1
	return 0
