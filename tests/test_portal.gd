extends SceneTree

# A portal's build: frame, horizon, lamps and beacon; the opening clear of
# every collider; the earth portal on its place.

const PortalScript = preload("res://scripts/portal.gd")
const PortalRules = preload("res://scripts/portal_rules.gd")

func _init():
	var failures := 0
	failures += _test_parts()
	failures += _test_opening_is_clear()
	failures += _test_earth_portal_places_itself()
	failures += _test_lamp_shader_has_phase()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _portal() -> Node3D:
	var portal: Node3D = PortalScript.new()
	portal.build()
	return portal

func _test_parts() -> int:
	var portal := _portal()
	var result := 0
	var frame := portal.get_node_or_null("Frame")
	if not frame is StaticBody3D or not frame.is_in_group("portal_frames") or not portal.is_in_group("portals"):
		print("FAIL _test_parts: no solid frame, or not grouped")
		result = 1
	if portal.get_node_or_null("Horizon") == null or portal.get_node_or_null("Beacon") == null or portal.get_node("Lamps").get_child_count() != PortalScript.LAMP_COUNT:
		print("FAIL _test_parts: horizon, beacon or lamps missing")
		result = 1
	var horizon := portal.get_node("Horizon")
	if horizon.get_child_count() != 0 or not horizon is MeshInstance3D:
		print("FAIL _test_parts: the horizon must not collide")
		result = 1
	portal.free()
	return result

func _test_opening_is_clear() -> int:
	# Every collider's inner face at or past the opening's radius.
	var portal := _portal()
	var result := 0
	var count := 0
	for child in portal.get_node("Frame").get_children():
		if not child is CollisionShape3D:
			continue
		count += 1
		var box := (child as CollisionShape3D).shape as BoxShape3D
		var at := (child as Node3D).position
		var radial := Vector2(at.x, at.y).length()
		if radial - box.size.x * 0.5 < PortalRules.APERTURE_RADIUS - 0.01 or absf(at.z) > 0.01:
			print("FAIL _test_opening_is_clear: %s reaches %.1f m from the centre" % [child.name, radial - box.size.x * 0.5])
			result = 1
	if count < PortalScript.FRAME_SEGMENTS:
		print("FAIL _test_opening_is_clear: only %d colliders" % count)
		result = 1
	portal.free()
	return result

func _test_earth_portal_places_itself() -> int:
	var portal: Node3D = PortalScript.new()
	portal.place_on_ring = true
	portal._ready()
	var expected := PortalRules.earth_transform(portal.ring_radius)
	var result := 0
	if not portal.transform.is_equal_approx(expected):
		print("FAIL _test_earth_portal_places_itself: %s" % portal.transform)
		result = 1
	portal.free()
	return result

func _test_lamp_shader_has_phase() -> int:
	var code := PortalScript.lamp_shader_code()
	if not "uniform float phase" in code or not "TIME + period - phase" in code or not "both_sides ? 1.0" in code:
		print("FAIL _test_lamp_shader_has_phase: the station's lamp shader changed shape")
		return 1
	return 0
