extends SceneTree

# Which context panel the HUD shows, and which sensor lines.

const HudLayout = preload("res://scripts/hud_layout.gd")

func _init():
	var failures := 0
	failures += _test_context_priority()
	failures += _test_sensors_only_when_near()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_context_priority() -> int:
	var moon := {"alt": "ALT 120 m"}
	var gate := {"gate": "GATE > LUNA  2.0 km"}
	var dock := {"dist": "DIST  3.0 km"}
	var cases := [
		# Landing low over the moon beats a gate nearby.
		[moon, 1200.0, gate, {}, HudLayout.Context.LANDING],
		# High in the moon's frame (the moon portal's exit), the gate first.
		[moon, 19000.0, gate, {}, HudLayout.Context.GATE],
		[{}, INF, gate, dock, HudLayout.Context.GATE],
		[{}, INF, {}, dock, HudLayout.Context.DOCK],
		# High in the moon's frame, nothing else: the landing panel still.
		[moon, 19000.0, {}, {}, HudLayout.Context.LANDING],
		[{}, INF, {}, {}, HudLayout.Context.NONE],
	]
	for c in cases:
		var got := HudLayout.context(c[0], c[1], c[2], c[3])
		if got != c[4]:
			print("FAIL _test_context_priority: %s at %.0f m, gate %s, dock %s gave %d" % [c[0], c[1], c[2], c[3], got])
			return 1
	return 0

func _test_sensors_only_when_near() -> int:
	var near := HudLayout.near_sensors({"bow": 819.6, "stern": -1.0, "port": 3140.0, "dorsal": 1999.0, "ventral": 0.0})
	if near != {"bow": 819.6, "dorsal": 1999.0, "ventral": 0.0}:
		print("FAIL _test_sensors_only_when_near: %s" % near)
		return 1
	return 0
