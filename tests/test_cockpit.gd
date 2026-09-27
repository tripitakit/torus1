extends SceneTree

const CockpitScript = preload("res://scripts/cockpit.gd")

func _init():
	var failures := 0
	failures += _test_pilot_camera_is_live_with_ninety_degree_horizontal_view()
	failures += _test_pilot_camera_sees_world_but_not_ship_exterior()
	failures += _test_cockpit_has_no_screens_or_3d_geometry()
	failures += _test_hud_is_a_2d_overlay_in_the_top_left_corner()
	failures += _test_hud_lines_in_display_order()
	failures += _test_update_hud_writes_speed_and_distances()
	failures += _test_update_hud_missing_distances_show_no_reading()
	failures += _test_dock_prompt_hidden_until_docking_is_possible()
	failures += _test_cruise_line_shown_only_while_cruising()
	failures += _test_hud_hosts_the_velocity_cross_bottom_left()
	failures += _test_hud_hosts_the_navball_bottom_centre()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cockpit() -> Node3D:
	var cockpit: Node3D = CockpitScript.new()
	cockpit.build()
	return cockpit

func _test_pilot_camera_is_live_with_ninety_degree_horizontal_view() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var node := cockpit.get_node_or_null("PilotCamera")
	if node == null or not (node is Camera3D):
		print("FAIL _test_pilot_camera_is_live_with_ninety_degree_horizontal_view: no PilotCamera Camera3D")
		cockpit.free()
		return 1
	var camera: Camera3D = node
	if not camera.current:
		print("FAIL _test_pilot_camera_is_live_with_ninety_degree_horizontal_view: PilotCamera is not current")
		result = 1
	if camera.keep_aspect != Camera3D.KEEP_WIDTH or not is_equal_approx(camera.fov, 90.0):
		print("FAIL _test_pilot_camera_is_live_with_ninety_degree_horizontal_view: keep_aspect=%d fov=%f expected KEEP_WIDTH and 90 (horizontal)" % [camera.keep_aspect, camera.fov])
		result = 1
	# The eye is 7 m behind the bow face: the near plane must stay well inside that.
	if camera.near > 2.0:
		print("FAIL _test_pilot_camera_is_live_with_ninety_degree_horizontal_view: near=%f would clip a surface touching the bow" % camera.near)
		result = 1
	cockpit.free()
	return result

func _test_pilot_camera_sees_world_but_not_ship_exterior() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var camera: Camera3D = cockpit.get_node("PilotCamera")
	if (camera.cull_mask & 1) == 0 or (camera.cull_mask & 4) != 0:
		print("FAIL _test_pilot_camera_sees_world_but_not_ship_exterior: cull_mask=%d must include world (1) and exclude ship exterior (4)" % camera.cull_mask)
		result = 1
	cockpit.free()
	return result

func _test_cockpit_has_no_screens_or_3d_geometry() -> int:
	# Single full-screen view: no camera screens, no cockpit meshes. The
	# navball's little world (its own SubViewport and sphere) is a HUD
	# instrument, not cockpit geometry.
	var cockpit := _make_cockpit()
	var result := 0
	var navball := cockpit.get_node_or_null("Hud/Navball")
	var outside_navball := func(node: Node) -> bool: return navball == null or not navball.is_ancestor_of(node)
	var viewports := cockpit.find_children("*", "SubViewport", true, false).filter(outside_navball)
	var meshes := cockpit.find_children("*", "MeshInstance3D", true, false).filter(outside_navball)
	if viewports.size() > 0 or meshes.size() > 0:
		print("FAIL _test_cockpit_has_no_screens_or_3d_geometry: %d SubViewports, %d meshes, expected none" % [viewports.size(), meshes.size()])
		result = 1
	cockpit.free()
	return result

func _test_hud_is_a_2d_overlay_in_the_top_left_corner() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var hud := cockpit.get_node_or_null("Hud")
	if hud == null or not (hud is CanvasLayer):
		print("FAIL _test_hud_is_a_2d_overlay_in_the_top_left_corner: no Hud CanvasLayer")
		cockpit.free()
		return 1
	var panel := hud.get_node_or_null("Panel") as Control
	if panel == null:
		print("FAIL _test_hud_is_a_2d_overlay_in_the_top_left_corner: no Hud/Panel Control")
		result = 1
	elif not panel.position.is_equal_approx(Vector2(24.0, 24.0)):
		print("FAIL _test_hud_is_a_2d_overlay_in_the_top_left_corner: Panel position=%s expected (24, 24)" % panel.position)
		result = 1
	cockpit.free()
	return result

func _test_hud_lines_in_display_order() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var lines := cockpit.get_node("Hud/Panel/Lines")
	var names: Array = []
	for child in lines.get_children():
		names.append(String(child.name))
	var expected := ["SpeedLabel", "CruiseLabel", "BowLabel", "SternLabel", "PortLabel", "StarboardLabel", "DorsalLabel", "VentralLabel", "DockLabel"]
	if names != expected:
		print("FAIL _test_hud_lines_in_display_order: %s expected %s" % [names, expected])
		result = 1
	cockpit.free()
	return result

func _test_update_hud_writes_speed_and_distances() -> int:
	var cockpit := _make_cockpit()
	cockpit.update_hud(1240.4, {"bow": 819.6, "stern": -1.0, "port": 3140.0, "starboard": -1.0, "dorsal": 410.0, "ventral": -1.0})
	var result := 0
	var expected := {
		"SpeedLabel": "SPEED  1240 m/s",
		"BowLabel": "BOW  820 m",
		"SternLabel": "STERN  —",
		"PortLabel": "PORT  3.1 km",
		"StarboardLabel": "STARBOARD  —",
		"DorsalLabel": "DORSAL  410 m",
		"VentralLabel": "VENTRAL  —",
	}
	for label_name in expected:
		var label: Label = cockpit.get_node("Hud/Panel/Lines/" + label_name)
		if label.text != expected[label_name]:
			print("FAIL _test_update_hud_writes_speed_and_distances: %s='%s' expected '%s'" % [label_name, label.text, expected[label_name]])
			result = 1
	cockpit.free()
	return result

func _test_update_hud_missing_distances_show_no_reading() -> int:
	var cockpit := _make_cockpit()
	cockpit.update_hud(0.0, {})
	var result := 0
	var label: Label = cockpit.get_node("Hud/Panel/Lines/BowLabel")
	if label.text != "BOW  —":
		print("FAIL _test_update_hud_missing_distances_show_no_reading: BowLabel='%s' expected 'BOW  —'" % label.text)
		result = 1
	cockpit.free()
	return result

func _test_dock_prompt_hidden_until_docking_is_possible() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var label := cockpit.get_node_or_null("Hud/Panel/Lines/DockLabel") as Label
	if label == null or label.text != "DOCK  [F]":
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: no DockLabel reading 'DOCK  [F]'")
		cockpit.free()
		return 1
	if label.visible:
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: visible before any check")
		result = 1
	cockpit.set_dock_prompt(true)
	if not label.visible:
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: not shown by set_dock_prompt(true)")
		result = 1
	cockpit.set_dock_prompt(false)
	if label.visible:
		print("FAIL _test_dock_prompt_hidden_until_docking_is_possible: not hidden by set_dock_prompt(false)")
		result = 1
	cockpit.free()
	return result

func _test_cruise_line_shown_only_while_cruising() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var label := cockpit.get_node_or_null("Hud/Panel/Lines/CruiseLabel") as Label
	if label == null or label.text != "CRUISE":
		print("FAIL _test_cruise_line_shown_only_while_cruising: no CruiseLabel reading 'CRUISE'")
		cockpit.free()
		return 1
	if label.visible:
		print("FAIL _test_cruise_line_shown_only_while_cruising: visible before cruise is on")
		result = 1
	cockpit.set_cruise(true)
	if not label.visible:
		print("FAIL _test_cruise_line_shown_only_while_cruising: not shown by set_cruise(true)")
		result = 1
	cockpit.set_cruise(false)
	if label.visible:
		print("FAIL _test_cruise_line_shown_only_while_cruising: not hidden by set_cruise(false)")
		result = 1
	cockpit.free()
	return result

func _test_hud_hosts_the_velocity_cross_bottom_left() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var cross := cockpit.get_node_or_null("Hud/VelocityCross") as Control
	if cross == null:
		print("FAIL _test_hud_hosts_the_velocity_cross_bottom_left: no Hud/VelocityCross")
		cockpit.free()
		return 1
	if not is_equal_approx(cross.anchor_left, 0.0) or not is_equal_approx(cross.anchor_top, 1.0) or cross.offset_bottom > 0.0 or cross.offset_left < 0.0:
		print("FAIL _test_hud_hosts_the_velocity_cross_bottom_left: anchors %f/%f offsets %f/%f" % [cross.anchor_left, cross.anchor_top, cross.offset_left, cross.offset_bottom])
		result = 1
	cockpit.update_velocity(Vector3(-5.0, 0.0, 120.0), true)
	if not cross.components.is_equal_approx(Vector3(-5.0, 0.0, 120.0)) or not cross.cruise:
		print("FAIL _test_hud_hosts_the_velocity_cross_bottom_left: update_velocity did not reach the cross")
		result = 1
	cockpit.free()
	return result

func _test_hud_hosts_the_navball_bottom_centre() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var navball := cockpit.get_node_or_null("Hud/Navball") as Control
	if navball == null:
		print("FAIL _test_hud_hosts_the_navball_bottom_centre: no Hud/Navball")
		cockpit.free()
		return 1
	if not is_equal_approx(navball.anchor_left, 0.5) or not is_equal_approx(navball.anchor_top, 1.0) or navball.offset_bottom > 0.0:
		print("FAIL _test_hud_hosts_the_navball_bottom_centre: anchors %f/%f bottom %f" % [navball.anchor_left, navball.anchor_top, navball.offset_bottom])
		result = 1
	var matrix := Basis(Vector3.UP, 0.7)
	cockpit.update_attitude(matrix)
	if not navball.attitude().is_equal_approx(matrix):
		print("FAIL _test_hud_hosts_the_navball_bottom_centre: update_attitude did not reach the navball")
		result = 1
	cockpit.free()
	return result
